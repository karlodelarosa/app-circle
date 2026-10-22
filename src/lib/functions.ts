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
    context?: Response;
  } | null;
  if (functionError?.context instanceof Response) {
    try {
      const payload = await functionError.context.clone().json() as {
        error?: string;
      };
      if (payload.error) return payload.error;
    } catch {
      // Fall back to the SDK message when the response is not JSON.
    }
  }
  return functionError?.message || fallback;
}
