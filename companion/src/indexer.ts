import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import {
  chatsDir,
  cursorUserDir,
  exists,
  globalStateDb,
  projectsDir,
  unsanitizeProjectDir,
  workspaceDisplayName,
  workspaceStorageDir,
} from "./paths";
import type {
  Bubble,
  ConversationMode,
  FileChange,
  Subagent,
  ThreadDetail,
  ThreadSource,
  ThreadStatus,
  ThreadSummary,
  Workspace,
} from "./types";

const SKIP_KEY = /cookie|secret|password|token|auth|credential|apikey|api_key/i;

function parseJson(value: unknown): unknown {
  if (value == null) return null;
  if (typeof value === "object") return value;
  let text: string;
  if (typeof value === "string") text = value;
  else if (Buffer.isBuffer(value)) text = value.toString("utf8");
  else if (value instanceof Uint8Array) text = Buffer.from(value).toString("utf8");
  else text = String(value);
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function snapshotSqlite(dbPath: string): string | null {
  if (!exists(dbPath)) return null;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cursorsnap-"));
  const dest = path.join(dir, "state.vscdb");
  fs.copyFileSync(dbPath, dest);
  for (const extra of ["-wal", "-shm"]) {
    const src = dbPath + extra;
    if (exists(src)) {
      try {
        fs.copyFileSync(src, dest + extra);
      } catch {
        /* ignore */
      }
    }
  }
  return dest;
}

function openReadonly(dbPath: string): DatabaseSync | null {
  try {
    return new DatabaseSync(dbPath, { readOnly: true });
  } catch {
    return null;
  }
}

function tableRows(
  db: DatabaseSync,
  table: string,
): { key: string; value: unknown }[] {
  try {
    const stmt = db.prepare(`SELECT key, value FROM ${table}`);
    return stmt.all() as { key: string; value: unknown }[];
  } catch {
    return [];
  }
}

function asMode(raw: unknown): ConversationMode {
  const v = String(raw ?? "agent").toLowerCase();
  if (v === "plan" || v === "ask" || v === "debug" || v === "multitask") return v;
  if (v === "chat") return "ask";
  return "agent";
}

function composerStatus(data: Record<string, unknown>, updatedAt: number): ThreadStatus {
  const status = String(data.status ?? data.unifiedStatus ?? "").toLowerCase();
  if (status.includes("error") || status === "aborted") return "error";
  if (status.includes("running") || status.includes("generating") || data.isQueued) {
    return "running";
  }
  if (data.hasBlockingPendingActions || status.includes("wait")) return "waiting";
  const pr = String(data.prUrl ?? data.pullRequestUrl ?? "");
  if (pr) return "inReview";
  if (Date.now() - updatedAt < 15_000) return "running";
  return "finished";
}

function textFromBubble(bubble: Record<string, unknown>): string {
  if (typeof bubble.text === "string" && bubble.text.trim()) return bubble.text;
  if (typeof bubble.thinking === "object" && bubble.thinking && "text" in bubble.thinking) {
    return String((bubble.thinking as { text?: string }).text ?? "");
  }
  const rich = bubble.richText;
  if (typeof rich === "string") {
    try {
      const parsed = JSON.parse(rich) as { root?: { children?: { text?: string }[] } };
      const parts = parsed.root?.children?.map((c) => c.text).filter(Boolean);
      if (parts?.length) return parts.join("\n");
    } catch {
      /* ignore */
    }
  }
  return "";
}

export class LocalChatIndexer {
  private catalog = new Map<string, ThreadSummary>();
  private details = new Map<string, ThreadDetail>();
  private workspaces = new Map<string, Workspace>();
  private watchers: fs.FSWatcher[] = [];
  private timer: NodeJS.Timeout | null = null;
  onChange: ((threads: ThreadSummary[], workspaces: Workspace[]) => void) | null = null;

  start(): void {
    this.scan();
    this.watch();
    this.timer = setInterval(() => this.scan(), 4000);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    for (const w of this.watchers) {
      try {
        w.close();
      } catch {
        /* ignore */
      }
    }
    this.watchers = [];
  }

  list(): { threads: ThreadSummary[]; workspaces: Workspace[] } {
    const threads = [...this.catalog.values()].sort((a, b) => b.updatedAt - a.updatedAt);
    const workspaces = [...this.workspaces.values()].sort((a, b) => a.name.localeCompare(b.name));
    return { threads, workspaces };
  }

  getThread(id: string): ThreadDetail | undefined {
    const cached = this.details.get(id);
    if (cached) return cached;
    this.scan();
    return this.details.get(id);
  }

  private watch(): void {
    const roots = [
      globalStateDb(),
      workspaceStorageDir(),
      projectsDir(),
      chatsDir(),
      cursorUserDir(),
    ];
    for (const root of roots) {
      if (!exists(root)) continue;
      try {
        const w = fs.watch(root, { recursive: true }, () => {
          this.scan();
        });
        this.watchers.push(w);
      } catch {
        /* some platforms reject recursive */
        try {
          this.watchers.push(fs.watch(root, () => this.scan()));
        } catch {
          /* ignore */
        }
      }
    }
  }

  scan(): void {
    const nextCatalog = new Map<string, ThreadSummary>();
    const nextDetails = new Map<string, ThreadDetail>();
    const nextWorkspaces = new Map<string, Workspace>();

    this.ingestAppDb(nextCatalog, nextDetails, nextWorkspaces);
    this.ingestTranscripts(nextCatalog, nextDetails, nextWorkspaces);
    this.ingestCliChats(nextCatalog, nextDetails, nextWorkspaces);

    this.catalog = nextCatalog;
    this.details = nextDetails;
    this.workspaces = nextWorkspaces;
    this.rebuildWorkspaceBadges();
    this.onChange?.([...this.catalog.values()], [...this.workspaces.values()]);
  }

  private upsertWorkspace(map: Map<string, Workspace>, cwd: string | null): Workspace {
    const id = cwd ? crypto.createHash("md5").update(cwd).digest("hex") : "no-repo";
    const existing = map.get(id);
    if (existing) return existing;
    const ws: Workspace = {
      id,
      name: workspaceDisplayName(cwd),
      cwd,
      badge: 0,
    };
    map.set(id, ws);
    return ws;
  }

  private rebuildWorkspaceBadges(): void {
    for (const ws of this.workspaces.values()) ws.badge = 0;
    for (const t of this.catalog.values()) {
      const ws = this.workspaces.get(t.workspaceId);
      if (ws) ws.badge += 1;
    }
  }

  private ingestAppDb(
    catalog: Map<string, ThreadSummary>,
    details: Map<string, ThreadDetail>,
    workspaces: Map<string, Workspace>,
  ): void {
    const cwdByComposer = new Map<string, string | null>();
    const wsDir = workspaceStorageDir();
    if (exists(wsDir)) {
      for (const hash of fs.readdirSync(wsDir)) {
        const folder = path.join(wsDir, hash);
        let cwd: string | null = null;
        const wsJson = path.join(folder, "workspace.json");
        if (exists(wsJson)) {
          try {
            const parsed = JSON.parse(fs.readFileSync(wsJson, "utf8")) as {
              folder?: string;
              workspace?: { folder?: string };
            };
            const uri = parsed.folder || parsed.workspace?.folder || "";
            cwd = uri.replace(/^file:\/\//, "");
            try {
              cwd = decodeURIComponent(cwd);
            } catch {
              /* ignore */
            }
          } catch {
            /* ignore */
          }
        }
        const snap = snapshotSqlite(path.join(folder, "state.vscdb"));
        if (!snap) continue;
        const db = openReadonly(snap);
        if (!db) continue;
        try {
          for (const row of tableRows(db, "ItemTable")) {
            if (SKIP_KEY.test(row.key)) continue;
            if (row.key !== "composer.composerData" && !row.key.includes("aichat.chatdata")) {
              continue;
            }
            const json = parseJson(row.value) as Record<string, unknown> | null;
            if (!json) continue;
            const composers = (json.allComposers as Record<string, unknown>[]) || [];
            for (const c of composers) {
              const id = String(c.composerId ?? c.id ?? "");
              if (id) cwdByComposer.set(id, cwd);
            }
            if (row.key.includes("aichat.chatdata")) {
              this.ingestLegacyChat(json, cwd, catalog, details, workspaces);
            }
          }
        } finally {
          db.close();
        }
      }
    }

    const globalSnap = snapshotSqlite(globalStateDb());
    if (!globalSnap) return;
    const gdb = openReadonly(globalSnap);
    if (!gdb) return;
    const bubblesByComposer = new Map<string, Record<string, unknown>[]>();
    const composerData = new Map<string, Record<string, unknown>>();
    try {
      for (const row of tableRows(gdb, "ItemTable")) {
        if (SKIP_KEY.test(row.key)) continue;
        if (row.key === "composer.composerHeaders") {
          const json = parseJson(row.value) as Record<string, unknown> | null;
          const headers = (json?.allComposers || json?.headers || []) as Record<string, unknown>[];
          if (Array.isArray(headers)) {
            for (const h of headers) {
              const id = String(h.composerId ?? h.id ?? "");
              const ident = h.workspaceIdentifier as { uri?: string } | undefined;
              const uri = ident?.uri || String(h.cwd ?? "");
              if (id && uri) cwdByComposer.set(id, String(uri).replace(/^file:\/\//, ""));
            }
          }
        }
      }
      for (const row of tableRows(gdb, "cursorDiskKV")) {
        const key = String(row.key ?? "");
        if (SKIP_KEY.test(key)) continue;
        if (key.startsWith("composerData:")) {
          const id = key.slice("composerData:".length);
          const json = parseJson(row.value) as Record<string, unknown> | null;
          if (json) composerData.set(id, json);
        } else if (key.startsWith("bubbleId:")) {
          const parts = key.split(":");
          const id = parts[1];
          const json = parseJson(row.value) as Record<string, unknown> | null;
          if (id && json) {
            const list = bubblesByComposer.get(id) ?? [];
            list.push(json);
            bubblesByComposer.set(id, list);
          }
        }
      }
    } finally {
      gdb.close();
    }

    for (const [id, data] of composerData) {
      const cwd = cwdByComposer.get(id) ?? null;
      const ws = this.upsertWorkspace(workspaces, cwd);
      const createdAt = Number(data.createdAt ?? data.createdAtMs ?? Date.now());
      const updatedAt = Number(data.lastUpdatedAt ?? data.updatedAt ?? createdAt);
      const rawBubbles = bubblesByComposer.get(id) ?? [];
      const bubbles = this.normalizeBubbles(id, data, rawBubbles);
      const preview =
        [...bubbles].reverse().find((b) => b.text.trim())?.text.slice(0, 140) || "";
      const mode = asMode(data.unifiedMode ?? data.forceMode ?? data.mode);
      const status = composerStatus(data, updatedAt);
      const name = String(data.name || data.title || preview || "Untitled chat");
      const subagents = this.subagentsFromData(id, data);
      const summary: ThreadSummary = {
        id,
        name,
        cwd,
        workspaceId: ws.id,
        workspaceName: ws.name,
        source: "app",
        status,
        unread: Boolean(data.isUnread),
        preview,
        updatedAt,
        createdAt,
        mode,
        model: String(
          (data.modelConfig as { modelName?: string } | undefined)?.modelName ?? data.model ?? "",
        ),
        gitBranch: String(data.createdOnBranch ?? data.gitBranch ?? "") || undefined,
        prUrl: String(data.prUrl ?? data.pullRequestUrl ?? "") || undefined,
        runningSubagentCount: subagents.filter((s) => s.status === "working").length,
        runningSubagentName: subagents.find((s) => s.status === "working")?.name,
      };
      catalog.set(id, summary);
      details.set(id, {
        ...summary,
        bubbles,
        subagents,
        changes: this.changesFromData(data),
        pullRequests: [],
      });
    }
  }

  private ingestLegacyChat(
    json: Record<string, unknown>,
    cwd: string | null,
    catalog: Map<string, ThreadSummary>,
    details: Map<string, ThreadDetail>,
    workspaces: Map<string, Workspace>,
  ): void {
    const tabs = (json.tabs || json.conversations || []) as Record<string, unknown>[];
    for (const tab of tabs) {
      const id = String(tab.tabId ?? tab.id ?? crypto.randomUUID());
      if (catalog.has(id)) continue;
      const ws = this.upsertWorkspace(workspaces, cwd);
      const bubbles: Bubble[] = ((tab.bubbles || tab.messages || []) as Record<string, unknown>[]).map(
        (b, i) => ({
          id: String(b.id ?? i),
          role: Number(b.type) === 1 ? "user" : "assistant",
          text: textFromBubble(b),
          createdAt: Number(b.createdAt ?? Date.now()),
        }),
      );
      const updatedAt = Number(tab.lastUpdatedAt ?? Date.now());
      const summary: ThreadSummary = {
        id,
        name: String(tab.chatTitle ?? tab.title ?? "Chat"),
        cwd,
        workspaceId: ws.id,
        workspaceName: ws.name,
        source: "app",
        status: "finished",
        unread: false,
        preview: bubbles.at(-1)?.text.slice(0, 140) ?? "",
        updatedAt,
        createdAt: Number(tab.createdAt ?? updatedAt),
        mode: "agent",
      };
      catalog.set(id, summary);
      details.set(id, { ...summary, bubbles, subagents: [], changes: [], pullRequests: [] });
    }
  }

  private normalizeBubbles(
    composerId: string,
    data: Record<string, unknown>,
    raw: Record<string, unknown>[],
  ): Bubble[] {
    const headers = (data.fullConversationHeadersOnly || data.conversationHeaders || []) as {
      bubbleId?: string;
      type?: number;
    }[];
    const byId = new Map<string, Record<string, unknown>>();
    for (const b of raw) {
      const id = String(b.bubbleId ?? b.id ?? "");
      if (id) byId.set(id, b);
    }
    const ordered: Record<string, unknown>[] = [];
    if (headers.length) {
      for (const h of headers) {
        const b = byId.get(String(h.bubbleId));
        if (b) ordered.push(b);
      }
    }
    if (!ordered.length) ordered.push(...raw);
    const conversation = data.conversation as Record<string, unknown>[] | undefined;
    if (!ordered.length && Array.isArray(conversation)) ordered.push(...conversation);

    return ordered.map((b, i) => {
      const type = Number(b.type ?? b.role ?? 2);
      const thinking =
        typeof b.thinking === "object" && b.thinking
          ? String((b.thinking as { text?: string }).text ?? "")
          : undefined;
      return {
        id: String(b.bubbleId ?? b.id ?? `${composerId}-${i}`),
        role: type === 1 ? "user" : thinking && !textFromBubble(b) ? "thinking" : "assistant",
        text: textFromBubble(b),
        createdAt: Number(b.createdAt ?? b.timestamp ?? Date.now()),
        thinking,
        toolName: (b.toolFormerData as { name?: string } | undefined)?.name,
      };
    });
  }

  private subagentsFromData(parentId: string, data: Record<string, unknown>): Subagent[] {
    const list =
      (data.subagents as Record<string, unknown>[]) ||
      (data.agentTasks as Record<string, unknown>[]) ||
      [];
    return list.map((s, i) => ({
      id: String(s.id ?? s.subagentId ?? `${parentId}-sub-${i}`),
      parentId,
      name: String(s.name ?? s.title ?? s.subagentType ?? "Subagent"),
      kind: String(s.kind ?? s.subagentType ?? s.name ?? "custom").toLowerCase(),
      status: (["waiting", "working", "completed", "error"].includes(String(s.status))
        ? s.status
        : "completed") as Subagent["status"],
      summary: String(s.summary ?? s.description ?? s.prompt ?? ""),
    }));
  }

  private changesFromData(data: Record<string, unknown>): FileChange[] {
    const code = data.codeBlockData as Record<string, { diffId?: string }[]> | undefined;
    if (!code) return [];
    return Object.keys(code).map((filePath) => ({
      path: filePath,
      added: 0,
      removed: 0,
    }));
  }

  private ingestTranscripts(
    catalog: Map<string, ThreadSummary>,
    details: Map<string, ThreadDetail>,
    workspaces: Map<string, Workspace>,
  ): void {
    const root = projectsDir();
    if (!exists(root)) return;
    for (const project of fs.readdirSync(root)) {
      const tdir = path.join(root, project, "agent-transcripts");
      if (!exists(tdir)) continue;
      const cwd = unsanitizeProjectDir(project);
      this.walkTranscripts(tdir, cwd, null, catalog, details, workspaces);
    }
  }

  private walkTranscripts(
    dir: string,
    cwd: string,
    parentId: string | null,
    catalog: Map<string, ThreadSummary>,
    details: Map<string, ThreadDetail>,
    workspaces: Map<string, Workspace>,
  ): void {
    let entries: fs.Dirent[] = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "subagents") {
          const parent = parentId || path.basename(dir);
          this.walkTranscripts(full, cwd, parent, catalog, details, workspaces);
          continue;
        }
        this.walkTranscripts(full, cwd, parentId, catalog, details, workspaces);
        continue;
      }
      if (!entry.name.endsWith(".jsonl")) continue;
      const id = entry.name.replace(/\.jsonl$/, "");
      const bubbles = this.readJsonl(full);
      if (parentId) {
        const parent = details.get(parentId);
        if (parent) {
          const existing = parent.subagents.find((s) => s.id === id);
          const sub: Subagent = {
            id,
            parentId,
            name: existing?.name || "Subagent",
            kind: existing?.kind || "custom",
            status: "completed",
            summary: bubbles.at(-1)?.text.slice(0, 180) || "",
          };
          if (!existing) parent.subagents.push(sub);
          const childDetail: ThreadDetail = {
            id,
            name: sub.name,
            cwd,
            workspaceId: parent.workspaceId,
            workspaceName: parent.workspaceName,
            source: "cli",
            status: "finished",
            unread: false,
            preview: sub.summary,
            updatedAt: bubbles.at(-1)?.createdAt || Date.now(),
            createdAt: bubbles[0]?.createdAt || Date.now(),
            mode: "agent",
            bubbles,
            subagents: [],
            changes: [],
            pullRequests: [],
          };
          details.set(id, childDetail);
        }
        continue;
      }
      if (catalog.has(id)) {
        const detail = details.get(id);
        if (detail && detail.bubbles.length < bubbles.length) detail.bubbles = bubbles;
        continue;
      }
      const ws = this.upsertWorkspace(workspaces, cwd);
      const updatedAt = bubbles.at(-1)?.createdAt || fs.statSync(full).mtimeMs;
      const summary: ThreadSummary = {
        id,
        name: bubbles.find((b) => b.role === "user")?.text.slice(0, 80) || id.slice(0, 8),
        cwd,
        workspaceId: ws.id,
        workspaceName: ws.name,
        source: "cli",
        status: "finished",
        unread: false,
        preview: bubbles.at(-1)?.text.slice(0, 140) || "",
        updatedAt,
        createdAt: bubbles[0]?.createdAt || updatedAt,
        mode: "agent",
      };
      catalog.set(id, summary);
      details.set(id, { ...summary, bubbles, subagents: [], changes: [], pullRequests: [] });
    }
  }

  private readJsonl(file: string): Bubble[] {
    const bubbles: Bubble[] = [];
    let text = "";
    try {
      text = fs.readFileSync(file, "utf8");
    } catch {
      return bubbles;
    }
    const lines = text.split("\n");
    lines.forEach((line, i) => {
      if (!line.trim()) return;
      try {
        const ev = JSON.parse(line) as Record<string, unknown>;
        const roleRaw = String(ev.role ?? ev.type ?? "");
        const msg = (ev.message as Record<string, unknown>) || ev;
        const content = msg.content ?? ev.content ?? ev.text;
        let body = "";
        if (typeof content === "string") body = content;
        else if (Array.isArray(content)) {
          body = content
            .map((c: { text?: string }) => (typeof c === "string" ? c : c.text || ""))
            .join("");
        }
        if (!body && typeof ev.text === "string") body = ev.text;
        if (!body) return;
        const role: Bubble["role"] =
          roleRaw.includes("user") || ev.type === "user"
            ? "user"
            : roleRaw.includes("think")
              ? "thinking"
              : "assistant";
        bubbles.push({
          id: String(ev.uuid ?? ev.id ?? `${file}-${i}`),
          role,
          text: body,
          createdAt: Number(ev.timestamp ?? ev.createdAt ?? Date.now()),
        });
      } catch {
        /* skip bad line */
      }
    });
    return bubbles;
  }

  private ingestCliChats(
    catalog: Map<string, ThreadSummary>,
    details: Map<string, ThreadDetail>,
    workspaces: Map<string, Workspace>,
  ): void {
    const root = chatsDir();
    if (!exists(root)) return;
    let hashes: string[] = [];
    try {
      hashes = fs.readdirSync(root);
    } catch {
      return;
    }
    for (const hash of hashes) {
      const bucket = path.join(root, hash);
      let sessions: string[] = [];
      try {
        sessions = fs.readdirSync(bucket);
      } catch {
        continue;
      }
      for (const session of sessions) {
        const dir = path.join(bucket, session);
        const metaPath = path.join(dir, "meta.json");
        if (!exists(metaPath)) continue;
        if (catalog.has(session)) continue;
        try {
          const meta = JSON.parse(fs.readFileSync(metaPath, "utf8")) as Record<string, unknown>;
          const cwd = String(meta.cwd ?? meta.workspacePath ?? "") || null;
          const ws = this.upsertWorkspace(workspaces, cwd);
          const updatedAt = Number(meta.updatedAt ?? Date.now());
          const summary: ThreadSummary = {
            id: session,
            name: String(meta.name ?? meta.title ?? session.slice(0, 8)),
            cwd,
            workspaceId: ws.id,
            workspaceName: ws.name,
            source: "sdk",
            status: "finished",
            unread: false,
            preview: String(meta.preview ?? ""),
            updatedAt,
            createdAt: Number(meta.createdAt ?? updatedAt),
            mode: asMode(meta.mode),
            model: String(meta.model ?? "") || undefined,
          };
          catalog.set(session, summary);
          details.set(session, {
            ...summary,
            bubbles: [],
            subagents: [],
            changes: [],
            pullRequests: [],
          });
        } catch {
          /* ignore */
        }
      }
    }
  }
}
