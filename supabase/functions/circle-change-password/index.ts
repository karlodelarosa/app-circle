import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, x-client-info, apikey, content-type" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const caller = createClient(url, anon, { global: { headers: { authorization: request.headers.get("authorization") || "" } } });
  const { data: auth, error } = await caller.auth.getUser();
  if (error || !auth.user) return json({ error: "Authentication required" }, 401);
  const { password } = await request.json();
  if (typeof password !== "string" || password.length < 10 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/\d/.test(password))
    return json({ error: "Use at least 10 characters with uppercase, lowercase, and a number." }, 400);
  const changed = await service.auth.admin.updateUserById(auth.user.id, { password });
  if (changed.error) return json({ error: changed.error.message }, 400);
  const link = await service.from("circle_user_links").update({ must_change_password: false, updated_at: new Date().toISOString() })
    .eq("user_id", auth.user.id).eq("status", "active");
  if (link.error) return json({ error: link.error.message }, 400);
  return json({ ok: true });
});
