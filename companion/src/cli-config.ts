import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { cliConfigPath, cursorDotDir, exists } from "./paths";
import type { ApprovalMode } from "./types";

export function readApprovalMode(): ApprovalMode {
  try {
    const raw = JSON.parse(fs.readFileSync(cliConfigPath(), "utf8")) as {
      approvalMode?: string;
    };
    if (raw.approvalMode === "allowlist" || raw.approvalMode === "unrestricted") {
      return raw.approvalMode;
    }
  } catch {
    /* default */
  }
  return "auto-review";
}

export function writeApprovalMode(mode: ApprovalMode, sandbox?: boolean): void {
  fs.mkdirSync(cursorDotDir(), { recursive: true });
  let current: Record<string, unknown> = {};
  if (exists(cliConfigPath())) {
    try {
      current = JSON.parse(fs.readFileSync(cliConfigPath(), "utf8")) as Record<string, unknown>;
    } catch {
      current = {};
    }
  }
  current.approvalMode = mode;
  if (typeof sandbox === "boolean") {
    const sandboxObj =
      typeof current.sandbox === "object" && current.sandbox
        ? (current.sandbox as Record<string, unknown>)
        : {};
    sandboxObj.mode = sandbox ? "enabled" : "disabled";
    current.sandbox = sandboxObj;
  }
  fs.writeFileSync(cliConfigPath(), JSON.stringify(current, null, 2) + os.EOL);
}
