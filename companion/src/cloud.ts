import { Agent, Cursor } from "@cursor/sdk";
import type { ThreadSummary, Workspace } from "./types";

export async function listCloudThreads(): Promise<ThreadSummary[]> {
  try {
    const { items } = await Agent.list({ runtime: "cloud", limit: 50 });
    return items.map((a) => {
      const status =
        a.status === "running"
          ? "running"
          : a.status === "error"
            ? "error"
            : "finished";
      const repos = "repos" in a ? a.repos : undefined;
      const cwd = repos?.[0] ?? ("cwd" in a ? a.cwd : null) ?? null;
      return {
        id: a.agentId,
        name: a.name || a.summary || a.agentId,
        cwd,
        workspaceId: cwd || "cloud",
        workspaceName: cwd ? cwd.split("/").pop() || cwd : "Cloud",
        source: "cloud" as const,
        status: status as ThreadSummary["status"],
        unread: a.status === "running",
        preview: a.summary || "",
        updatedAt: a.lastModified || Date.now(),
        createdAt: a.createdAt || a.lastModified || Date.now(),
        mode: "agent" as const,
      };
    });
  } catch {
    return [];
  }
}

export async function listModels(): Promise<{ id: string; label: string }[]> {
  try {
    const items = await Cursor.models.list();
    return items.map((m) => {
      const id = m.id;
      return { id, label: m.displayName || id };
    });
  } catch {
    return [];
  }
}

export async function listRepositories(): Promise<string[]> {
  try {
    const items = await Cursor.repositories.list();
    return items.map((r) => r.url).filter(Boolean);
  } catch {
    return [];
  }
}

export function cloudWorkspaces(threads: ThreadSummary[]): Workspace[] {
  const map = new Map<string, Workspace>();
  for (const t of threads) {
    if (!map.has(t.workspaceId)) {
      map.set(t.workspaceId, {
        id: t.workspaceId,
        name: t.workspaceName,
        cwd: t.cwd,
        badge: 0,
      });
    }
    map.get(t.workspaceId)!.badge += 1;
  }
  return [...map.values()];
}
