import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export function home(): string {
  return os.homedir();
}

export function cursorUserDir(): string {
  switch (process.platform) {
    case "darwin":
      return path.join(home(), "Library", "Application Support", "Cursor", "User");
    case "win32":
      return path.join(process.env.APPDATA || path.join(home(), "AppData", "Roaming"), "Cursor", "User");
    default:
      return path.join(home(), ".config", "Cursor", "User");
  }
}

export function cursorDotDir(): string {
  return path.join(home(), ".cursor");
}

export function globalStateDb(): string {
  return path.join(cursorUserDir(), "globalStorage", "state.vscdb");
}

export function workspaceStorageDir(): string {
  return path.join(cursorUserDir(), "workspaceStorage");
}

export function projectsDir(): string {
  return path.join(cursorDotDir(), "projects");
}

export function chatsDir(): string {
  return path.join(cursorDotDir(), "chats");
}

export function cliConfigPath(): string {
  return path.join(cursorDotDir(), "cli-config.json");
}

export function sdkAuthPath(): string {
  return path.join(cursorDotDir(), "sdk", "auth.json");
}

export function exists(p: string): boolean {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

/** Cursor project folder names are the absolute path with `/` replaced by `-`. */
export function unsanitizeProjectDir(name: string): string {
  if (name.startsWith("Users-") || name.startsWith("home-")) {
    return `/${name.replace(/-/g, "/")}`;
  }
  if (/^[A-Za-z]-/.test(name) && process.platform === "win32") {
    const drive = name[0];
    return `${drive}:\\${name.slice(2).replace(/-/g, "\\")}`;
  }
  return name.replace(/-/g, path.sep);
}

export function workspaceDisplayName(cwd: string | null): string {
  if (!cwd) return "No Repo";
  return path.basename(cwd) || cwd;
}
