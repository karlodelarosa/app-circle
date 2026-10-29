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
  gathering?: PublicGathering;
  introduction?: string;
  heroTitle?: string;
  heroImageUrl?: string;
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
const clientTelemetryRoute = "/__telemetry/client-error";
const healthRoute = "/healthz";
const organizationRoute = /^\/([^/]+)(?:\/(?:gatherings|updates|testimonies|galleries|circles|cell-group-signup|privacy))?\/?$/;
const socialPreviewVersion = "3";

const contentSecurityPolicy = [
  "default-src 'self'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "object-src 'none'",
  "script-src 'self' https://challenges.cloudflare.com",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com",
  "img-src 'self' data: blob: https:",
  "connect-src 'self' https:",
  "frame-src https://challenges.cloudflare.com",
  "manifest-src 'self'",
  "worker-src 'self'",
].join("; ");

function requestId(request: Request) {
  const supplied = request.headers.get("x-request-id");
  return supplied && /^[A-Za-z0-9._-]{1,128}$/.test(supplied)
    ? supplied
    : crypto.randomUUID();
}

function secureResponse(response: Response, id: string) {
  const headers = new Headers(response.headers);
  headers.set("content-security-policy", contentSecurityPolicy);
  headers.set("strict-transport-security", "max-age=31536000; includeSubDomains; preload");
  headers.set("x-content-type-options", "nosniff");
  headers.set("x-frame-options", "DENY");
  headers.set("referrer-policy", "strict-origin-when-cross-origin");
  headers.set("permissions-policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=()");
  headers.set("cross-origin-opener-policy", "same-origin");
  headers.set("x-request-id", id);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function recordClientError(request: Request, id: string) {
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (contentLength > 8192 || !request.headers.get("content-type")?.includes("application/json"))
    return secureResponse(Response.json({ error: "Invalid report" }, { status: 400 }), id);
  const raw = await request.text();
  if (raw.length > 8192)
    return secureResponse(Response.json({ error: "Invalid report" }, { status: 400 }), id);
  try {
    const value = JSON.parse(raw) as Record<string, unknown>;
    const errorType = typeof value.errorType === "string" ? value.errorType.slice(0, 80) : "UnknownError";
    const path = typeof value.path === "string" && /^\/[A-Za-z0-9/_-]*$/.test(value.path)
      ? value.path.slice(0, 240)
      : "/";
    const event = value.event === "auth_failure"
      ? "auth_failure"
      : value.event === "authorized_data_export"
        ? "authorized_data_export"
        : "client_error";
    console.error(JSON.stringify({ event, requestId: id, errorType, path }));
    return secureResponse(new Response(null, { status: 204 }), id);
  } catch {
    return secureResponse(Response.json({ error: "Invalid report" }, { status: 400 }), id);
  }
}

async function healthResponse(env: WorkerEnv, id: string) {
  const started = Date.now();
  let database = "unconfigured";
  if (env.SUPABASE_URL && env.SUPABASE_ANON_KEY) {
    try {
      const result = await fetch(new URL("/auth/v1/health", env.SUPABASE_URL), {
        headers: { apikey: env.SUPABASE_ANON_KEY },
      });
      database = result.ok ? "ok" : "error";
    } catch {
      database = "error";
    }
  }
  const databaseLatencyMs = Date.now() - started;
  const ok = database === "ok";
  console.log(JSON.stringify({ event: "dependency_health", requestId: id, database, databaseLatencyMs }));
  return secureResponse(Response.json({ ok, database, databaseLatencyMs }, {
    status: ok ? 200 : 503,
    headers: { "cache-control": "no-store" },
  }), id);
}

function gatheringPlaceholder(seed: string) {
  const hash = [...seed].reduce(
    (value, character) => (value * 31 + character.charCodeAt(0)) >>> 0,
    0,
  );
  return `/assets/gathering-placeholder-${(hash % 2) + 1}.webp`;
}

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

function injectOrganizationMetadata(html: string, request: Request, space: PublicSpaceResponse) {
  const canonical = new URL(request.url);
  canonical.search = "";
  canonical.hash = "";
  const title = `${space.heroTitle || space.organization?.name || "Community"} | Circles`;
  const description = String(space.introduction || `Discover gatherings and community life from ${space.organization?.name || "this community"}.`).slice(0, 220);
  const image = space.heroImageUrl ? new URL(space.heroImageUrl, canonical).href : new URL("/assets/devotional-table.webp", canonical).href;
  const metadata = `
    <link rel="canonical" href="${escapeHtml(canonical.href)}" />
    <meta name="description" content="${escapeHtml(description)}" />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Circles" />
    <meta property="og:title" content="${escapeHtml(title)}" />
    <meta property="og:description" content="${escapeHtml(description)}" />
    <meta property="og:image" content="${escapeHtml(image)}" />
    <meta property="og:url" content="${escapeHtml(canonical.href)}" />
    <meta name="twitter:card" content="summary_large_image" />`;
  return html
    .replace(/<title>[\s\S]*?<\/title>/i, `<title>${escapeHtml(title)}</title>`)
    .replace(/\s*<meta\s+name=["']description["'][^>]*>/i, "")
    .replace("</head>", `${metadata}\n  </head>`);
}

async function loadPublicSpace(slug: string, env: WorkerEnv) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
  const endpoint = new URL("/rest/v1/rpc/get_circle_public_space", env.SUPABASE_URL);
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ p_org_slug: slug }),
  });
  return response.ok ? await response.json() as PublicSpaceResponse | null : null;
}

async function organizationHtml(request: Request, env: WorkerEnv) {
  const match = new URL(request.url).pathname.match(organizationRoute);
  if (!match || [
    "sign-in", "forgot-password", "reset-password", "app", "gatherings", "circles",
    "prayer", "content", "connections", "signups", "more", "change-password",
  ].includes(match[1])) return null;
  const space = await loadPublicSpace(match[1], env);
  if (!space?.organization) return null;
  const shell = await env.ASSETS.fetch(new Request(new URL("/index.html", request.url), { headers: request.headers }));
  if (!shell.ok) return null;
  const headers = new Headers(shell.headers);
  headers.set("content-type", "text/html; charset=UTF-8");
  headers.set("cache-control", "public, max-age=0, s-maxage=300");
  headers.delete("content-length");
  headers.delete("etag");
  return new Response(injectOrganizationMetadata(await shell.text(), request, space), { headers });
}

async function sitemap(request: Request, env: WorkerEnv) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
  const endpoint = new URL("/rest/v1/rpc/get_circle_public_sitemap", env.SUPABASE_URL);
  const result = await fetch(endpoint, {
    method: "POST",
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, "content-type": "application/json" },
    body: "{}",
  });
  if (!result.ok) return null;
  const paths = await result.json() as string[];
  const urls = paths.map((path) => `<url><loc>${escapeHtml(new URL(path, request.url).href)}</loc></url>`).join("");
  return new Response(`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>`, {
    headers: { "content-type": "application/xml; charset=UTF-8", "cache-control": "public, max-age=300, s-maxage=3600" },
  });
}

async function loadPublicGathering(
  parts: { organization: string; gathering: string },
  env: WorkerEnv,
) {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
  const endpoint = new URL("/rest/v1/rpc/get_circle_public_gathering", env.SUPABASE_URL);
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_ANON_KEY,
      authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      p_org_slug: parts.organization,
      p_gathering_slug: parts.gathering,
    }),
  });
  if (!response.ok) return null;
  const space = (await response.json()) as PublicSpaceResponse | null;
  const gathering = space?.gathering;
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
        new Request(
          new URL(gatheringPlaceholder(gathering), request.url),
        ),
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
  const id = requestId(request);
  if (requestUrl.pathname === healthRoute && request.method === "GET")
    return healthResponse(env, id);
  if (requestUrl.pathname === clientTelemetryRoute && request.method === "POST")
    return recordClientError(request, id);
  if (requestUrl.pathname === "/robots.txt" && request.method === "GET")
    return secureResponse(new Response(`User-agent: *\nAllow: /\nSitemap: ${requestUrl.origin}/sitemap.xml\n`, { headers: { "content-type": "text/plain; charset=UTF-8" } }), id);
  if (requestUrl.pathname === "/sitemap.xml" && request.method === "GET") {
    const response = await sitemap(request, env);
    return secureResponse(response || new Response("Sitemap unavailable", { status: 503 }), id);
  }
  const isImage = requestUrl.pathname === gatheringImageRoute;
  const isGathering = Boolean(routeParts(requestUrl.pathname));
  const isOrganization = organizationRoute.test(requestUrl.pathname);
  if (
    request.method !== "GET" ||
    (!isImage && !isGathering && !isOrganization)
  )
    return secureResponse(await env.ASSETS.fetch(request), id);

  const edgeCache = (
    globalThis as typeof globalThis & {
      caches?: { default?: Cache };
    }
  ).caches?.default;
  const cached = await edgeCache?.match(request);
  if (cached) return secureResponse(cached, id);

  try {
    const response = isImage
      ? await gatheringImage(request, env)
      : isGathering
        ? await gatheringHtml(request, env)
        : await organizationHtml(request, env);
    if (response) {
      if (edgeCache && context)
        context.waitUntil(edgeCache.put(request, response.clone()));
      return secureResponse(response, id);
    }
  } catch (error) {
    console.error(JSON.stringify({
      event: "worker_request_failed",
      requestId: id,
      route: isImage ? gatheringImageRoute : isGathering ? gatheringRoute.source : organizationRoute.source,
      errorType: error instanceof Error ? error.name : "UnknownError",
    }));
    // The SPA still provides its normal not-found and retry experience.
  }
  return secureResponse(await env.ASSETS.fetch(request), id);
}

export default { fetch: handleRequest };
