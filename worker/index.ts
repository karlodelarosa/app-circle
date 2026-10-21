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
const gatheringImageRoute = "/__share/gathering-image";
const socialPreviewVersion = "2";

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
  parts: { organization: string; gathering: string },
) {
  const canonical = new URL(request.url);
  canonical.search = "";
  canonical.hash = "";
  const socialUrl = new URL(canonical);
  if (new URL(request.url).searchParams.has("share"))
    socialUrl.searchParams.set("share", socialPreviewVersion);
  const image = new URL(gatheringImageRoute, canonical);
  image.searchParams.set("organization", parts.organization);
  image.searchParams.set("gathering", parts.gathering);
  image.searchParams.set("v", socialPreviewVersion);
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
    <meta property="og:image:secure_url" content="${escapeHtml(image.href)}" />
    <meta property="og:image:type" content="image/jpeg" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:image:alt" content="${escapeHtml(`${gathering.title || "Gathering"} invitation cover`)}" />
    <meta property="og:url" content="${escapeHtml(socialUrl.href)}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${escapeHtml(title)}" />
    <meta name="twitter:description" content="${escapeHtml(description)}" />
    <meta name="twitter:image" content="${escapeHtml(image.href)}" />`;

  return html
    .replace(/<title>[\s\S]*?<\/title>/i, `<title>${escapeHtml(title)}</title>`)
    .replace(/\s*<meta\s+name=["']description["'][^>]*>/i, "")
    .replace("</head>", `${metadata}\n  </head>`);
}

async function loadPublicGathering(
  parts: { organization: string; gathering: string },
  env: WorkerEnv,
) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
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
  return space && gathering ? { space, gathering } : null;
}

async function gatheringHtml(request: Request, env: WorkerEnv) {
  const parts = routeParts(new URL(request.url).pathname);
  if (!parts) return null;
  const result = await loadPublicGathering(parts, env);
  if (!result) return null;
  const { space, gathering } = result;

  const indexRequest = new Request(new URL("/index.html", request.url), {
    method: "GET",
    headers: request.headers,
  });
  const shell = await env.ASSETS.fetch(indexRequest);
  if (!shell.ok) return null;
  const html = injectMetadata(
    await shell.text(),
    request,
    space,
    gathering,
    parts,
  );
  const headers = new Headers(shell.headers);
  headers.set("content-type", "text/html; charset=UTF-8");
  headers.set("cache-control", "public, max-age=0, s-maxage=300");
  headers.delete("content-length");
  headers.delete("etag");
  return new Response(html, { status: 200, headers });
}

async function gatheringImage(request: Request, env: WorkerEnv) {
  const url = new URL(request.url);
  const organization = url.searchParams.get("organization")?.trim();
  const gathering = url.searchParams.get("gathering")?.trim();
  if (!organization || !gathering) return null;
  const result = await loadPublicGathering({ organization, gathering }, env);
  if (!result) return null;

  const hasCover = Boolean(result.gathering.coverUrl);
  const source = result.gathering.coverUrl
    ? await fetch(result.gathering.coverUrl, {
        cf: {
          image: {
            fit: "cover",
            width: 1200,
            height: 630,
            format: "jpeg",
            quality: 85,
          },
        },
      } as RequestInit & {
        cf: {
          image: {
            fit: string;
            width: number;
            height: number;
            format: string;
            quality: number;
          };
        };
      })
    : await env.ASSETS.fetch(
        new Request(new URL("/assets/devotional-table.webp", request.url)),
      );
  if (!source.ok || !source.body) return null;
  const headers = new Headers(source.headers);
  headers.set(
    "content-type",
    hasCover ? "image/jpeg" : source.headers.get("content-type") || "image/webp",
  );
  headers.set("cache-control", "public, max-age=86400, s-maxage=86400");
  headers.set("access-control-allow-origin", "*");
  headers.delete("content-length");
  headers.delete("x-robots-tag");
  headers.delete("set-cookie");
  return new Response(source.body, { status: 200, headers });
}

export async function handleRequest(
  request: Request,
  env: WorkerEnv,
  context?: WorkerContext,
) {
  const requestUrl = new URL(request.url);
  const isImage = requestUrl.pathname === gatheringImageRoute;
  if (
    request.method !== "GET" ||
    (!isImage && !routeParts(requestUrl.pathname))
  )
    return env.ASSETS.fetch(request);

  const edgeCache = (
    globalThis as typeof globalThis & {
      caches?: { default?: Cache };
    }
  ).caches?.default;
  const cached = await edgeCache?.match(request);
  if (cached) return cached;

  try {
    const response = isImage
      ? await gatheringImage(request, env)
      : await gatheringHtml(request, env);
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
