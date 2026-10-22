import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, "content-type": "application/json" },
});
const randomPassword = () => {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const digits = "23456789";
  const symbols = "!@#$%";
  const all = `${upper}${lower}${digits}${symbols}`;
  const pick = (characters: string) => {
    const [byte] = crypto.getRandomValues(new Uint8Array(1));
    return characters[byte % characters.length];
  };
  const characters = [pick(upper), pick(lower), pick(digits), pick(symbols)];
  while (characters.length < 16) characters.push(pick(all));
  for (let index = characters.length - 1; index > 0; index--) {
    const [byte] = crypto.getRandomValues(new Uint8Array(1));
    const swap = byte % (index + 1);
    [characters[index], characters[swap]] = [characters[swap], characters[index]];
  }
  return characters.join("");
};
const slug = (value: string) => value.toLowerCase().normalize("NFKD")
  .replace(/[^a-z0-9]+/g, ".").replace(/^\.|\.$/g, "").slice(0, 32) || "member";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authorization = request.headers.get("authorization") || "";
  const callerClient = createClient(url, anon, { global: { headers: { authorization } } });
  const service = createClient(url, serviceKey);
  const { data: auth, error: authError } = await callerClient.auth.getUser();
  if (authError || !auth.user) return json({ error: "Authentication required" }, 401);
  try {
    const { action, groupId, personId } = await request.json();
    if (!["provision", "reset"].includes(action) || !groupId || !personId)
      return json({ error: "Invalid request" }, 400);
    const access = await callerClient.rpc("get_circle_member_account_statuses", {
      p_cell_group_id: groupId,
    });
    if (access.error) return json({ error: "Leader access required" }, 403);
    const { data: membership } = await service.from("cell_group_members")
      .select("person_id,cell_groups!inner(organization_id),people!inner(first_name,last_name,email,status)")
      .eq("cell_group_id", groupId).eq("person_id", personId).maybeSingle();
    const person = Array.isArray(membership?.people) ? membership.people[0] : membership?.people;
    const group = Array.isArray(membership?.cell_groups) ? membership.cell_groups[0] : membership?.cell_groups;
    if (!membership || !person || person.status !== "Active")
      return json({ error: "Only active People assigned to this Circle can receive access." }, 400);
    const organizationId = group.organization_id;
    const { data: current } = await service.from("circle_user_links").select("*")
      .eq("organization_id", organizationId).eq("person_id", personId).maybeSingle();

    if (action === "reset") {
      if (!current || current.account_kind !== "generated")
        return json({ error: "Only generated member accounts can be reset here." }, 400);
      const password = randomPassword();
      const updated = await service.auth.admin.updateUserById(current.user_id, { password });
      if (updated.error) throw updated.error;
      const link = await service.from("circle_user_links").update({
        must_change_password: true, last_password_reset_at: new Date().toISOString(), status: "active",
      }).eq("id", current.id);
      if (link.error) throw link.error;
      return json({ kind: "generated", loginId: current.login_id, temporaryPassword: password });
    }

    if (current) {
      await service.from("circle_user_links").update({ status: "active", updated_at: new Date().toISOString() }).eq("id", current.id);
      return json({ kind: current.account_kind, loginId: current.login_id, alreadyExists: true });
    }

    let userId: string | undefined;
    const realEmail = String(person.email || "").trim().toLowerCase();
    if (realEmail) {
      for (let page = 1; page <= 20 && !userId; page++) {
        const listed = await service.auth.admin.listUsers({ page, perPage: 100 });
        if (listed.error) throw listed.error;
        userId = listed.data.users.find((user) => user.email?.toLowerCase() === realEmail)?.id;
        if (listed.data.users.length < 100) break;
      }
    }
    let kind: "existing" | "generated" = "existing";
    let loginId: string | null = null;
    let temporaryPassword: string | undefined;
    let createdUser = false;
    if (!userId) {
      kind = "generated";
      for (let attempt = 0; attempt < 8; attempt++) {
        const suffix = crypto.randomUUID().replace(/-/g, "").slice(0, 4);
        const candidate = `${slug(`${person.first_name}.${person.last_name}`)}-${suffix}`;
        const exists = await service.from("circle_user_links").select("id").eq("login_id", candidate).maybeSingle();
        if (!exists.data) { loginId = candidate; break; }
      }
      if (!loginId) throw new Error("A unique Member ID could not be generated.");
      temporaryPassword = randomPassword();
      const created = await service.auth.admin.createUser({
        email: `${loginId}@members.circles.invalid`, password: temporaryPassword,
        email_confirm: true,
        user_metadata: { first_name: person.first_name, last_name: person.last_name, circles_member_id: loginId },
      });
      if (created.error || !created.data.user) throw created.error || new Error("Account creation failed.");
      userId = created.data.user.id;
      createdUser = true;
    }
    try {
      const orgMember = await service.from("organization_members").upsert({
        user_id: userId, organization_id: organizationId, role: "member", status: "active",
      }, { onConflict: "user_id,organization_id" });
      if (orgMember.error) throw orgMember.error;
      const link = await service.from("circle_user_links").insert({
        user_id: userId, organization_id: organizationId, person_id: personId, status: "active",
        account_kind: kind, login_id: loginId, must_change_password: kind === "generated",
        provisioned_by: auth.user.id, last_password_reset_at: kind === "generated" ? new Date().toISOString() : null,
      });
      if (link.error) throw link.error;
    } catch (error) {
      if (createdUser && userId) await service.auth.admin.deleteUser(userId);
      throw error;
    }
    return json({ kind, loginId, temporaryPassword, existingAccount: kind === "existing" });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Account operation failed." }, 400);
  }
});
