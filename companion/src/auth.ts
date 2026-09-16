import { Cursor } from "@cursor/sdk";

const YEAR_MS = 365 * 24 * 60 * 60 * 1000;

export async function loginWithCursor(): Promise<{ email?: string }> {
  const result = await Cursor.auth.login({
    apiKeyName: "Cursor Mobile Companion",
    apiKeyTtlMs: YEAR_MS,
  });
  return { email: result.email };
}

export async function authStatus(): Promise<{
  status: string;
  email?: string;
}> {
  try {
    const status = await Cursor.auth.status();
    return status as { status: string; email?: string };
  } catch {
    return { status: "logged-out" };
  }
}

export async function logout(): Promise<void> {
  await Cursor.auth.logout();
}

export async function fetchMe(): Promise<{
  email?: string;
  name?: string;
  apiKeyName?: string;
}> {
  try {
    const me = await Cursor.me();
    return {
      email: me.userEmail,
      name: [me.userFirstName, me.userLastName].filter(Boolean).join(" ") || undefined,
      apiKeyName: me.apiKeyName,
    };
  } catch {
    return {};
  }
}
