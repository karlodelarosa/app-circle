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
