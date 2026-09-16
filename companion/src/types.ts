export type ConversationMode = "agent" | "plan" | "ask" | "debug" | "multitask";
export type ApprovalMode = "allowlist" | "auto-review" | "unrestricted";
export type ThreadSource = "app" | "cli" | "sdk" | "cloud";
export type ThreadStatus =
  | "running"
  | "waiting"
  | "needsAttention"
  | "inReview"
  | "finished"
  | "error";
export type SubagentStatus = "waiting" | "working" | "completed" | "error";

export interface ModelSelection {
  id: string;
  params?: { id: string; value: string }[];
}

export interface Workspace {
  id: string;
  name: string;
  cwd: string | null;
  badge: number;
}

export interface Subagent {
  id: string;
  parentId: string;
  name: string;
  kind: string;
  status: SubagentStatus;
  summary: string;
  elapsedMs?: number;
  children?: Subagent[];
}

export interface Bubble {
  id: string;
  role: "user" | "assistant" | "thinking" | "system";
  text: string;
  createdAt: number;
  toolName?: string;
  thinking?: string;
}

export interface FileChange {
  path: string;
  language?: string;
  added: number;
  removed: number;
}

export interface PullRequest {
  id: string;
  number: number;
  title: string;
  url?: string;
  status: string;
  added: number;
  removed: number;
  files?: FileChange[];
}

export interface ContextCategory {
  id: string;
  label: string;
  tokens: number;
  percent: number;
}

export interface ContextUsage {
  threadId: string;
  percent: number;
  tokens: number;
  windowSize: number;
  categories: ContextCategory[];
}

export interface ThreadSummary {
  id: string;
  name: string;
  cwd: string | null;
  workspaceId: string;
  workspaceName: string;
  source: ThreadSource;
  status: ThreadStatus;
  unread: boolean;
  preview: string;
  updatedAt: number;
  createdAt: number;
  mode: ConversationMode;
  model?: string;
  gitBranch?: string;
  prUrl?: string;
  added?: number;
  removed?: number;
  runningSubagentCount?: number;
  runningSubagentName?: string;
}

export interface ThreadDetail extends ThreadSummary {
  bubbles: Bubble[];
  subagents: Subagent[];
  changes: FileChange[];
  pullRequests: PullRequest[];
  contextUsage?: ContextUsage;
  planMarkdown?: string;
}

export interface Counts {
  all: number;
  needsAttention: number;
  working: number;
  inReview: number;
}

export interface PermissionRequest {
  requestId: string;
  threadId: string;
  subagentId?: string;
  subagentName?: string;
  title: string;
  detail: string;
  workspace?: string;
  sandboxed?: boolean;
}

export interface Envelope {
  type: string;
  id?: string;
  payload: unknown;
}
