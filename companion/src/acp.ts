import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import readline from "node:readline";
import type { ConversationMode, PermissionRequest, Subagent } from "./types";

type Pending = {
  resolve: (value: unknown) => void;
  reject: (err: Error) => void;
};

export type AcpHandlers = {
  onPermission: (req: PermissionRequest) => void;
  onQuestion: (req: {
    requestId: string;
    threadId: string;
    title: string;
    questions: unknown[];
  }) => void;
  onPlan: (req: {
    requestId: string;
    threadId: string;
    name?: string;
    overview?: string;
    plan: string;
    todos: unknown[];
  }) => void;
  onUpdate: (threadId: string, update: unknown) => void;
  onTask: (threadId: string, subagent: Subagent) => void;
};

function findAgentBin(): string {
  return process.env.CURSOR_AGENT_BIN || "agent";
}

export class AcpSession {
  private proc: ChildProcessWithoutNullStreams;
  private nextId = 1;
  private pending = new Map<number, Pending>();
  private incoming = new Map<
    number | string,
    { method: string; threadId: string }
  >();
  sessionId: string | null = null;
  cwd: string;
  threadId: string;
  private handlers: AcpHandlers;

  constructor(cwd: string, threadId: string, handlers: AcpHandlers) {
    this.cwd = cwd;
    this.threadId = threadId;
    this.handlers = handlers;
    this.proc = spawn(findAgentBin(), ["acp"], {
      cwd,
      stdio: ["pipe", "pipe", "pipe"],
      env: process.env,
    });
    const rl = readline.createInterface({ input: this.proc.stdout });
    rl.on("line", (line) => this.onLine(line));
    this.proc.on("exit", () => {
      for (const p of this.pending.values()) {
        p.reject(new Error("ACP process exited"));
      }
      this.pending.clear();
    });
  }

  private send(method: string, params: unknown): Promise<unknown> {
    const id = this.nextId++;
    this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }

  respond(id: number | string, result: unknown): void {
    this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
  }

  private onLine(line: string): void {
    let msg: {
      id?: number | string;
      method?: string;
      params?: Record<string, unknown>;
      result?: unknown;
      error?: { message?: string };
    };
    try {
      msg = JSON.parse(line);
    } catch {
      return;
    }
    if (msg.id != null && (msg.result !== undefined || msg.error)) {
      const waiter = this.pending.get(Number(msg.id));
      if (waiter) {
        this.pending.delete(Number(msg.id));
        msg.error ? waiter.reject(new Error(msg.error.message || "ACP error")) : waiter.resolve(msg.result);
      }
      return;
    }
    if (!msg.method) return;
    const params = msg.params || {};
    if (msg.method === "session/update") {
      this.handlers.onUpdate(this.threadId, params.update ?? params);
      return;
    }
    if (msg.method === "session/request_permission" && msg.id != null) {
      const toolCall = (params.toolCall || params) as Record<string, unknown>;
      const req: PermissionRequest = {
        requestId: String(msg.id),
        threadId: this.threadId,
        subagentId: toolCall.subagentId ? String(toolCall.subagentId) : undefined,
        subagentName: toolCall.subagentName ? String(toolCall.subagentName) : undefined,
        title: String(toolCall.title || toolCall.name || "Permission required"),
        detail: String(
          toolCall.command ||
            toolCall.rawInput ||
            JSON.stringify(toolCall.content || toolCall.args || toolCall).slice(0, 2000),
        ),
        workspace: this.cwd,
      };
      this.incoming.set(msg.id, { method: msg.method, threadId: this.threadId });
      this.handlers.onPermission(req);
      return;
    }
    if (msg.method === "cursor/ask_question" && msg.id != null) {
      this.incoming.set(msg.id, { method: msg.method, threadId: this.threadId });
      this.handlers.onQuestion({
        requestId: String(msg.id),
        threadId: this.threadId,
        title: String(params.title || "Need input"),
        questions: (params.questions as unknown[]) || [],
      });
      return;
    }
    if (msg.method === "cursor/create_plan" && msg.id != null) {
      this.incoming.set(msg.id, { method: msg.method, threadId: this.threadId });
      this.handlers.onPlan({
        requestId: String(msg.id),
        threadId: this.threadId,
        name: params.name ? String(params.name) : undefined,
        overview: params.overview ? String(params.overview) : undefined,
        plan: String(params.plan || ""),
        todos: (params.todos as unknown[]) || [],
      });
      return;
    }
    if (msg.method === "cursor/task") {
      const p = params as Record<string, unknown>;
      this.handlers.onTask(this.threadId, {
        id: String(p.agentId || p.toolCallId || crypto.randomUUID()),
        parentId: this.threadId,
        name: String(p.subagentType || p.description || "Subagent"),
        kind: typeof p.subagentType === "string" ? p.subagentType : "custom",
        status: "working",
        summary: String(p.description || p.prompt || ""),
      });
    }
  }

  async start(mode: ConversationMode): Promise<void> {
    await this.send("initialize", {
      protocolVersion: 1,
      clientCapabilities: {
        fs: { readTextFile: false, writeTextFile: false },
        terminal: false,
      },
      clientInfo: { name: "cursor-mobile-companion", version: "1.0.0" },
    });
    try {
      await this.send("authenticate", { methodId: "cursor_login" });
    } catch {
      /* already logged in via env / sdk */
    }
    const created = (await this.send("session/new", {
      cwd: this.cwd,
      mcpServers: [],
    })) as { sessionId?: string };
    this.sessionId = created.sessionId || null;
    await this.applyMode(mode);
  }

  async load(sessionId: string, mode: ConversationMode): Promise<void> {
    await this.send("initialize", {
      protocolVersion: 1,
      clientCapabilities: {
        fs: { readTextFile: false, writeTextFile: false },
        terminal: false,
      },
      clientInfo: { name: "cursor-mobile-companion", version: "1.0.0" },
    });
    try {
      await this.send("authenticate", { methodId: "cursor_login" });
    } catch {
      /* ignore */
    }
    try {
      await this.send("session/load", { sessionId, cwd: this.cwd });
      this.sessionId = sessionId;
    } catch {
      await this.start(mode);
      return;
    }
    await this.applyMode(mode);
  }

  async applyMode(mode: ConversationMode): Promise<void> {
    if (!this.sessionId) return;
    const acpMode = mode === "debug" || mode === "multitask" ? "agent" : mode;
    try {
      await this.send("session/set_config_option", {
        sessionId: this.sessionId,
        configId: "mode",
        value: acpMode,
      });
    } catch {
      try {
        await this.send("session/set_mode", {
          sessionId: this.sessionId,
          modeId: acpMode,
        });
      } catch {
        /* mode switch optional */
      }
    }
  }

  async prompt(text: string, mode: ConversationMode): Promise<void> {
    if (!this.sessionId) throw new Error("No ACP session");
    await this.applyMode(mode);
    let promptText = text;
    if (mode === "debug") promptText = `/debug ${text}`;
    if (mode === "multitask") promptText = `/multitask ${text}`;
    await this.send("session/prompt", {
      sessionId: this.sessionId,
      prompt: [{ type: "text", text: promptText }],
    });
  }

  async cancel(): Promise<void> {
    if (!this.sessionId) return;
    try {
      await this.send("session/cancel", { sessionId: this.sessionId });
    } catch {
      /* ignore */
    }
  }

  decidePermission(requestId: string, optionId: string): void {
    this.respond(requestId, { outcome: { outcome: "selected", optionId } });
  }

  decidePlan(requestId: string, accepted: boolean): void {
    this.respond(
      requestId,
      accepted
        ? { outcome: { outcome: "accepted" } }
        : { outcome: { outcome: "rejected", reason: "Rejected from phone" } },
    );
  }

  answerQuestion(
    requestId: string,
    answers: { questionId: string; selectedOptionIds: string[] }[],
  ): void {
    this.respond(requestId, { outcome: { outcome: "answered", answers } });
  }

  dispose(): void {
    try {
      this.proc.kill();
    } catch {
      /* ignore */
    }
  }
}
