const escapeHtml = (value: unknown) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

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
  const image =
    gathering.coverUrl || `${publicOrigin}/assets/devotional-table.webp`;
  const title = `${gathering.title} | ${space.organization.name}`;
  const description = String(
    gathering.summary ||
      gathering.notes ||
      `Join ${space.organization.name} for this gathering.`,
  ).slice(0, 220);
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)}</title>
<link rel="canonical" href="${escapeHtml(canonical)}">
<meta name="description" content="${escapeHtml(description)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Circles">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:image" content="${escapeHtml(image)}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:url" content="${escapeHtml(canonical)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${escapeHtml(title)}">
<meta name="twitter:description" content="${escapeHtml(description)}">
<meta name="twitter:image" content="${escapeHtml(image)}">
<meta http-equiv="refresh" content="0;url=${escapeHtml(canonical)}">
</head><body><p>Opening <a href="${escapeHtml(canonical)}">${escapeHtml(gathering.title)}</a>…</p>
<script>window.location.replace(${JSON.stringify(canonical)})</script></body></html>`;
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300, s-maxage=300",
      "x-content-type-options": "nosniff",
    },
  });
});
