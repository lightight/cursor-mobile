import crypto from "node:crypto";
import http from "node:http";
import os from "node:os";
import { Bonjour } from "bonjour-service";
import { WebSocketServer, type WebSocket } from "ws";
import { AcpSession, type AcpHandlers } from "./acp";
import { authStatus, fetchMe, loginWithCursor, logout } from "./auth";
import { readApprovalMode, writeApprovalMode } from "./cli-config";
import { cloudWorkspaces, listCloudThreads, listModels } from "./cloud";
import { LocalChatIndexer } from "./indexer";
import type {
  ApprovalMode,
  ConversationMode,
  Counts,
  Envelope,
  PermissionRequest,
  ThreadSummary,
  Workspace,
} from "./types";

const PORT = Number(process.env.CURSOR_MOBILE_PORT || 17890);
const SERVICE = "cursormobile";

function counts(threads: ThreadSummary[]): Counts {
  return {
    all: threads.length,
    needsAttention: threads.filter((t) => t.status === "needsAttention" || t.status === "waiting" || t.status === "error").length,
    working: threads.filter((t) => t.status === "running").length,
    inReview: threads.filter((t) => t.status === "inReview").length,
  };
}

function send(ws: WebSocket, type: string, payload: unknown, id?: string): void {
  if (ws.readyState !== ws.OPEN) return;
  ws.send(JSON.stringify({ type, id, payload } satisfies Envelope));
}

export class CompanionServer {
  pairingCode = String(Math.floor(100000 + Math.random() * 900000));
  private indexer = new LocalChatIndexer();
  private wss: WebSocketServer | null = null;
  private http: http.Server | null = null;
  private bonjour: Bonjour | null = null;
  private clients = new Set<WebSocket>();
  private pendingPermissions = new Map<string, PermissionRequest>();
  private sessions = new Map<string, AcpSession>();
  port = PORT;

  async start(): Promise<void> {
    this.indexer.onChange = (threads, workspaces) => {
      this.broadcastCatalog(threads, workspaces).catch(() => undefined);
    };
    this.indexer.start();

    this.http = http.createServer((req, res) => {
      if (req.url === "/health") {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ ok: true, pairing: this.pairingCode.length === 6 }));
        return;
      }
      res.writeHead(404);
      res.end();
    });
    this.wss = new WebSocketServer({ server: this.http });
    this.wss.on("connection", (ws) => this.onSocket(ws));
    await new Promise<void>((resolve) => this.http!.listen(this.port, "0.0.0.0", () => resolve()));

    this.bonjour = new Bonjour();
    this.bonjour.publish({
      name: `Cursor Mobile on ${os.hostname()}`,
      type: SERVICE,
      port: this.port,
      txt: { proto: "1" },
    });
  }

  stop(): void {
    this.indexer.stop();
    for (const s of this.sessions.values()) s.dispose();
    this.wss?.close();
    this.http?.close();
    this.bonjour?.destroy();
  }

  rotateCode(): string {
    this.pairingCode = String(Math.floor(100000 + Math.random() * 900000));
    return this.pairingCode;
  }

  private async merged(): Promise<{ threads: ThreadSummary[]; workspaces: Workspace[] }> {
    const local = this.indexer.list();
    const cloud = await listCloudThreads();
    const byId = new Map<string, ThreadSummary>();
    for (const t of local.threads) byId.set(t.id, t);
    for (const t of cloud) if (!byId.has(t.id)) byId.set(t.id, t);
    const threads = [...byId.values()].sort((a, b) => b.updatedAt - a.updatedAt);
    const wsMap = new Map<string, Workspace>();
    for (const w of [...local.workspaces, ...cloudWorkspaces(cloud)]) {
      const existing = wsMap.get(w.id);
      if (existing) existing.badge += w.badge;
      else wsMap.set(w.id, { ...w });
    }
    return { threads, workspaces: [...wsMap.values()] };
  }

  private async broadcastCatalog(
    _threads?: ThreadSummary[],
    _workspaces?: Workspace[],
  ): Promise<void> {
    const { threads, workspaces } = await this.merged();
    const payload = { workspaces, threads, counts: counts(threads) };
    for (const ws of this.clients) send(ws, "chats.catalog", payload);
  }

  private broadcast(type: string, payload: unknown): void {
    for (const ws of this.clients) send(ws, type, payload);
  }

  private acpHandlers(threadId: string): AcpHandlers {
    return {
      onPermission: (req) => {
        this.pendingPermissions.set(req.requestId, req);
        this.broadcast("permission.request", req);
      },
      onQuestion: (req) => this.broadcast("question.request", req),
      onPlan: (req) => this.broadcast("plan.request", req),
      onUpdate: (tid, update) => this.broadcast("stream.delta", { threadId: tid, event: update }),
      onTask: (tid, subagent) => {
        this.broadcast("subagent.upserted", { ...subagent, parentId: tid || threadId });
      },
    };
  }

  private async ensureSession(
    threadId: string,
    cwd: string,
    mode: ConversationMode,
    resume: boolean,
  ): Promise<AcpSession> {
    const existing = this.sessions.get(threadId);
    if (existing) {
      await existing.applyMode(mode);
      return existing;
    }
    const session = new AcpSession(cwd, threadId, this.acpHandlers(threadId));
    if (resume) await session.load(threadId, mode);
    else await session.start(mode);
    this.sessions.set(threadId, session);
    return session;
  }

  private onSocket(ws: WebSocket): void {
    let authed = false;
    ws.on("message", async (raw) => {
      let msg: Envelope;
      try {
        msg = JSON.parse(String(raw));
      } catch {
        return;
      }
      try {
        await this.handle(ws, msg, () => authed, (v) => {
          authed = v;
        });
      } catch (err) {
        send(ws, "error", { message: err instanceof Error ? err.message : String(err) }, msg.id);
      }
    });
    ws.on("close", () => this.clients.delete(ws));
  }

  private async handle(
    ws: WebSocket,
    msg: Envelope,
    isAuthed: () => boolean,
    setAuthed: (v: boolean) => void,
  ): Promise<void> {
    if (msg.type === "hello") {
      const code = String((msg.payload as { pairingCode?: string }).pairingCode || "");
      if (code !== this.pairingCode) {
        send(ws, "hello.denied", { reason: "bad-code" }, msg.id);
        ws.close();
        return;
      }
      setAuthed(true);
      this.clients.add(ws);
      const me = await fetchMe();
      send(
        ws,
        "hello.ok",
        {
          computerName: os.hostname(),
          user: me,
          approvalMode: readApprovalMode(),
        },
        msg.id,
      );
      const { threads, workspaces } = await this.merged();
      send(ws, "chats.catalog", { workspaces, threads, counts: counts(threads) });
      send(ws, "models.list", { items: await listModels() });
      send(ws, "me", me);
      for (const pending of this.pendingPermissions.values()) {
        send(ws, "permission.request", pending);
      }
      return;
    }
    if (!isAuthed()) {
      send(ws, "hello.denied", { reason: "not-paired" }, msg.id);
      return;
    }

    switch (msg.type) {
      case "chats.open": {
        const id = String((msg.payload as { id: string }).id);
        const thread = this.indexer.getThread(id);
        if (thread) {
          send(ws, "chats.thread", thread, msg.id);
          const tokens = thread.bubbles.reduce((n, b) => n + Math.ceil((b.text?.length || 0) / 4), 0);
          const windowSize = 128000;
          send(ws, "context.usage", {
            threadId: id,
            percent: Math.min(100, Math.round((tokens / windowSize) * 100)),
            tokens,
            windowSize,
            categories: [{ id: "conversation", label: "Conversation", tokens, percent: Math.min(100, (tokens / windowSize) * 100) }],
          });
        } else send(ws, "error", { message: "Thread not found" }, msg.id);
        break;
      }
      case "followup": {
        const p = msg.payload as {
          threadId: string;
          text: string;
          mode?: ConversationMode;
          model?: { id: string };
        };
        const thread = this.indexer.getThread(p.threadId);
        const cwd = thread?.cwd || process.cwd();
        const mode = p.mode || thread?.mode || "agent";
        const session = await this.ensureSession(
          p.threadId,
          cwd,
          mode,
          Boolean(thread && thread.source !== "app"),
        );
        await session.prompt(p.text, mode);
        break;
      }
      case "cancel": {
        const id = String((msg.payload as { threadId: string }).threadId);
        await this.sessions.get(id)?.cancel();
        break;
      }
      case "permission.decide": {
        const p = msg.payload as { requestId: string; optionId: string };
        for (const session of this.sessions.values()) {
          session.decidePermission(p.requestId, p.optionId);
        }
        this.pendingPermissions.delete(p.requestId);
        this.broadcast("permission.resolved", { requestId: p.requestId });
        break;
      }
      case "permission.setMode": {
        const p = msg.payload as { mode: ApprovalMode; sandbox?: boolean };
        writeApprovalMode(p.mode, p.sandbox);
        if (p.mode === "unrestricted") {
          for (const [id] of this.pendingPermissions) {
            for (const session of this.sessions.values()) {
              session.decidePermission(id, "allow-once");
            }
            this.pendingPermissions.delete(id);
            this.broadcast("permission.resolved", { requestId: id });
          }
        }
        break;
      }
      case "mode.set": {
        const p = msg.payload as { threadId: string; mode: ConversationMode };
        await this.sessions.get(p.threadId)?.applyMode(p.mode);
        break;
      }
      case "plan.decide": {
        const p = msg.payload as {
          requestId: string;
          outcome: "accepted" | "rejected";
          build?: "agent" | "multitask";
          threadId?: string;
        };
        for (const session of this.sessions.values()) {
          session.decidePlan(p.requestId, p.outcome === "accepted");
          if (p.outcome === "accepted" && p.build) {
            await session.applyMode(p.build === "multitask" ? "multitask" : "agent");
          }
        }
        break;
      }
      case "question.answer": {
        const p = msg.payload as {
          requestId: string;
          answers: { questionId: string; selectedOptionIds: string[] }[];
        };
        for (const session of this.sessions.values()) {
          session.answerQuestion(p.requestId, p.answers);
        }
        break;
      }
      case "models.refresh":
        send(ws, "models.list", { items: await listModels() }, msg.id);
        break;
      case "login.status": {
        const status = await authStatus();
        const me = await fetchMe();
        send(ws, "me", { ...me, ...status }, msg.id);
        break;
      }
      default:
        send(ws, "error", { message: `Unknown type ${msg.type}` }, msg.id);
    }
  }
}

export async function desktopLogin(): Promise<{ email?: string }> {
  return loginWithCursor();
}

export async function desktopLogout(): Promise<void> {
  await logout();
}

export function newId(): string {
  return crypto.randomUUID();
}
