interface AssetFetcher {
  fetch(request: Request): Promise<Response>;
}

export interface WorkerEnv {
  ASSETS: AssetFetcher;
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
}

interface WorkerContext {
  waitUntil(promise: Promise<unknown>): void;
}

interface PublicGathering {
  slug?: string;
  title?: string;
  summary?: string;
  notes?: string;
  coverUrl?: string;
}

interface PublicSpaceResponse {
  organization?: { name?: string };
  gatherings?: PublicGathering[];
}

const escapeHtml = (value: unknown) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

const gatheringRoute = /^\/([^/]+)\/gatherings\/([^/]+)\/?$/;

function routeParts(pathname: string) {
  const match = pathname.match(gatheringRoute);
  if (!match) return null;
  try {
    return {
      organization: decodeURIComponent(match[1]),
      gathering: decodeURIComponent(match[2]),
    };
  } catch {
    return null;
  }
}

function injectMetadata(
  html: string,
  request: Request,
  space: PublicSpaceResponse,
  gathering: PublicGathering,
) {
  const canonical = new URL(request.url);
  canonical.search = "";
  canonical.hash = "";
  const fallbackImage = new URL("/assets/devotional-table.webp", canonical);
  const image = new URL(gathering.coverUrl || fallbackImage.href, canonical);
  const title = `${gathering.title || "Gathering"} | ${space.organization?.name || "Circles"}`;
  const description = String(
    gathering.summary ||
      gathering.notes ||
      `Join ${space.organization?.name || "this community"} for this gathering.`,
  ).slice(0, 220);
  const metadata = `
    <link rel="canonical" href="${escapeHtml(canonical.href)}" />
    <meta name="description" content="${escapeHtml(description)}" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Circles" />
    <meta property="og:title" content="${escapeHtml(title)}" />
    <meta property="og:description" content="${escapeHtml(description)}" />
    <meta property="og:image" content="${escapeHtml(image.href)}" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:url" content="${escapeHtml(canonical.href)}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${escapeHtml(title)}" />
    <meta name="twitter:description" content="${escapeHtml(description)}" />
    <meta name="twitter:image" content="${escapeHtml(image.href)}" />`;

  return html
    .replace(/<title>[\s\S]*?<\/title>/i, `<title>${escapeHtml(title)}</title>`)
    .replace(/\s*<meta\s+name=["']description["'][^>]*>/i, "")
    .replace("</head>", `${metadata}\n  </head>`);
}

async function gatheringHtml(request: Request, env: WorkerEnv) {
  const parts = routeParts(new URL(request.url).pathname);
  if (!parts || !env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;

  const endpoint = new URL("/rest/v1/rpc/get_circle_public_space", env.SUPABASE_URL);
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ p_org_slug: parts.organization }),
  });
  if (!response.ok) return null;

  const space = (await response.json()) as PublicSpaceResponse | null;
  const gathering = space?.gatherings?.find(
    (item) => item.slug === parts.gathering,
  );
  if (!space || !gathering) return null;

  const indexRequest = new Request(new URL("/index.html", request.url), {
    method: "GET",
    headers: request.headers,
  });
  const shell = await env.ASSETS.fetch(indexRequest);
  if (!shell.ok) return null;
  const html = injectMetadata(await shell.text(), request, space, gathering);
  const headers = new Headers(shell.headers);
  headers.set("content-type", "text/html; charset=UTF-8");
  headers.set("cache-control", "public, max-age=0, s-maxage=300");
  headers.delete("content-length");
  headers.delete("etag");
  return new Response(html, { status: 200, headers });
}

export async function handleRequest(
  request: Request,
  env: WorkerEnv,
  context?: WorkerContext,
) {
  if (request.method !== "GET" || !routeParts(new URL(request.url).pathname))
    return env.ASSETS.fetch(request);

  const edgeCache = (
    globalThis as typeof globalThis & {
      caches?: { default?: Cache };
    }
  ).caches?.default;
  const cached = await edgeCache?.match(request);
  if (cached) return cached;

  try {
    const response = await gatheringHtml(request, env);
    if (response) {
      if (edgeCache && context)
        context.waitUntil(edgeCache.put(request, response.clone()));
      return response;
    }
  } catch {
    // The SPA still provides its normal not-found and retry experience.
  }
  return env.ASSETS.fetch(request);
}

export default { fetch: handleRequest };
