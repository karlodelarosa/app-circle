import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { allowedOrigin, corsHeaders, jsonResponse, readJsonBody, requestId } from "../_shared/http.ts";
Deno.serve(async (request) => {
  const id = requestId(request);
  const origin = allowedOrigin(request);
  if (!origin) return Response.json({ error: "Request not allowed" }, { status: 403 });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  const json = (body: unknown, status = 200) => jsonResponse(origin, id, body, status);
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const authorization = request.headers.get("authorization") || "";
  const accessToken = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) return json({ error: "Authentication required" }, 401);
  const { data: auth, error } = await service.auth.getUser(accessToken);
  if (error || !auth.user) return json({ error: "Authentication required" }, 401);
  let body: unknown;
  try { body = await readJsonBody(request, 4096); }
  catch { return json({ error: "Invalid request" }, 400); }
  const password = typeof body === "object" && body && "password" in body
    ? (body as { password?: unknown }).password : undefined;
  if (typeof password !== "string" || password.length < 10 || !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/\d/.test(password))
    return json({ error: "Use at least 10 characters with uppercase, lowercase, and a number." }, 400);
  const currentLink = await service.from("circle_user_links").select("organization_id")
    .eq("user_id", auth.user.id).eq("status", "active").maybeSingle();
  const audit = async (result: "success" | "failed") => {
    await service.from("circle_security_audit_events").insert({
      organization_id: currentLink.data?.organization_id || null,
      actor_user_id: auth.user.id,
      action: "credential.password_changed",
      target_type: "auth_user",
      target_id: auth.user.id,
      result,
      request_id: id,
    });
  };
  const changed = await service.auth.admin.updateUserById(auth.user.id, { password });
  if (changed.error) {
    await audit("failed");
    console.error(JSON.stringify({ event: "password_change_failed", requestId: id, errorType: changed.error.name || "AuthError" }));
    return json({ error: "Password could not be changed." }, 400);
  }
  const link = await service.from("circle_user_links").update({ must_change_password: false, updated_at: new Date().toISOString() })
    .eq("user_id", auth.user.id).eq("status", "active");
  if (link.error) {
    await audit("failed");
    console.error(JSON.stringify({ event: "password_link_update_failed", requestId: id, errorType: link.error.name || "DatabaseError" }));
    return json({ error: "Password could not be changed." }, 400);
  }
  await audit("success");
  return json({ ok: true });
});
