const notFound = () =>
  new Response("<!doctype html><title>Invitation unavailable</title>", {
    status: 404,
    headers: { "content-type": "text/html; charset=utf-8" },
  });

Deno.serve(async (request) => {
  if (request.method !== "GET")
    return new Response("Method not allowed", { status: 405 });
  const requestUrl = new URL(request.url);
  const organizationSlug = requestUrl.searchParams.get("organization")?.trim();
  const gatheringSlug = requestUrl.searchParams.get("gathering")?.trim();
  if (!organizationSlug || !gatheringSlug) return notFound();

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const requestedOrigin = requestUrl.searchParams.get("origin") || "";
  let publicOrigin = Deno.env.get("CIRCLES_PUBLIC_ORIGIN") || "";
  if (!publicOrigin) {
    try {
      const parsedOrigin = new URL(requestedOrigin);
      if (!["http:", "https:"].includes(parsedOrigin.protocol))
        return notFound();
      publicOrigin = parsedOrigin.origin;
    } catch {
      return notFound();
    }
  }
  publicOrigin = publicOrigin.replace(/\/$/, "");
  if (!supabaseUrl || !anonKey)
    return new Response("Share service unavailable", { status: 503 });

  const publicResponse = await fetch(
    `${supabaseUrl}/rest/v1/rpc/get_circle_public_space`,
    {
      method: "POST",
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${anonKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ p_org_slug: organizationSlug }),
    },
  );
  if (!publicResponse.ok) return notFound();
  const space = await publicResponse.json();
  const gathering = space?.gatherings?.find(
    (item: { slug?: string }) => item.slug === gatheringSlug,
  );
  if (!gathering) return notFound();

  const canonical = `${publicOrigin}/${encodeURIComponent(organizationSlug)}/gatherings/${encodeURIComponent(gatheringSlug)}`;
  return new Response(null, {
    status: 302,
    headers: {
      location: canonical,
      "cache-control": "public, max-age=300, s-maxage=300",
      "x-content-type-options": "nosniff",
    },
  });
});
