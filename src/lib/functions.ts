import type { SupabaseClient } from "@supabase/supabase-js";

export async function invokeAuthenticatedFunction(
  client: SupabaseClient,
  name: string,
  body: Record<string, unknown>,
) {
  const { data, error } = await client.auth.getSession();
  if (error || !data.session?.access_token) {
    throw new Error("Your sign-in session has expired. Sign in again and retry.");
  }

  return client.functions.invoke(name, {
    body,
    headers: {
      Authorization: `Bearer ${data.session.access_token}`,
    },
  });
}

export async function getFunctionErrorMessage(
  result: { data?: { error?: string } | null; error?: unknown },
  fallback: string,
) {
  if (result.data?.error) return result.data.error;
  const functionError = result.error as {
    message?: string;
    context?: {
      clone?: () => { json?: () => Promise<unknown> };
      json?: () => Promise<unknown>;
    };
  } | null;
  if (functionError?.context) {
    try {
      const readableContext = functionError.context.clone?.() ?? functionError.context;
      const payload = await readableContext.json?.() as { error?: string } | undefined;
      if (payload?.error) return payload.error;
    } catch {
      // Fall through to a safe user-facing message when the response is not JSON.
    }
  }
  const message = functionError?.message;
  if (message && !message.toLowerCase().includes("non-2xx status code")) return message;
  return fallback;
}
