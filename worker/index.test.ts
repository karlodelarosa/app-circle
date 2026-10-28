import { afterEach, describe, expect, it, vi } from "vitest";
import { handleRequest, type WorkerEnv } from "./index";

const shell = `<!doctype html><html><head><meta name="description" content="Default"><title>Circles</title></head><body><div id="root"></div></body></html>`;

const assets = {
  fetch: vi.fn(async (_request: Request) =>
    new Response(shell, {
      headers: { "content-type": "text/html; charset=UTF-8" },
    }),
  ),
};

const env: WorkerEnv = {
  ASSETS: assets,
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_ANON_KEY: "public-key",
};

afterEach(() => {
  vi.unstubAllGlobals();
  assets.fetch.mockClear();
});

describe("Circles Cloudflare Worker", () => {
  it("injects safe gathering preview metadata into the SPA shell", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        Response.json({
          organization: { name: "ELGC & Friends" },
          gathering: {
            slug: "lunch",
            title: "Lunch <Together>",
            summary: 'Bring friends & say "hello".',
            coverUrl: "https://images.example/cover.webp",
          },
        }),
      ),
    );

    const response = await handleRequest(
      new Request("https://circles.example/elgc/gatherings/lunch?share=2"),
      env,
    );
    const html = await response.text();

    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("cache-control")).toContain("s-maxage=300");
    expect(html).toContain("Lunch &lt;Together&gt; | ELGC &amp; Friends");
    expect(html).toContain(
      'property="og:image" content="https://circles.example/__share/gathering-image?organization=elgc&amp;gathering=lunch&amp;v=3"',
    );
    expect(html).toContain('property="og:image:type" content="image/jpeg"');
    expect(html).toContain(
      'property="og:url" content="https://circles.example/elgc/gatherings/lunch?share=3"',
    );
    expect(html).not.toContain('content="Default"');
  });

  it("falls back to static assets for ordinary routes", async () => {
    const request = new Request("https://circles.example/gatherings");
    const response = await handleRequest(request, env);
    expect(await response.text()).toBe(shell);
    expect(assets.fetch).toHaveBeenCalledWith(request);
  });

  it("adds organization metadata beyond gathering pages", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({
      organization: { name: "ELGC" },
      heroTitle: "There is room for you",
      introduction: "Find a place to gather and grow.",
      heroImageUrl: "/assets/welcome-table.webp",
    })));
    const response = await handleRequest(new Request("https://circles.example/elgc/circles"), env);
    const html = await response.text();
    expect(html).toContain("There is room for you | Circles");
    expect(html).toContain('rel="canonical" href="https://circles.example/elgc/circles"');
    expect(html).toContain("Find a place to gather and grow.");
  });

  it("serves crawler discovery files", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json(["/elgc", "/elgc/gatherings/lunch"])));
    const robots = await handleRequest(new Request("https://circles.example/robots.txt"), env);
    expect(await robots.text()).toContain("Sitemap: https://circles.example/sitemap.xml");
    const map = await handleRequest(new Request("https://circles.example/sitemap.xml"), env);
    expect(await map.text()).toContain("<loc>https://circles.example/elgc/gatherings/lunch</loc>");
  });

  it("adds production security and correlation headers to every response", async () => {
    const response = await handleRequest(
      new Request("https://circles.example/sign-in"),
      env,
    );

    expect(response.headers.get("content-security-policy")).toContain(
      "frame-ancestors 'none'",
    );
    expect(response.headers.get("strict-transport-security")).toBe(
      "max-age=31536000; includeSubDomains; preload",
    );
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("x-frame-options")).toBe("DENY");
    expect(response.headers.get("referrer-policy")).toBe(
      "strict-origin-when-cross-origin",
    );
    expect(response.headers.get("permissions-policy")).toContain("camera=()");
    expect(response.headers.get("x-request-id")).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("accepts bounded, classified client error reports", async () => {
    const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await handleRequest(
      new Request("https://circles.example/__telemetry/client-error", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ event: "react_error_boundary", errorType: "TypeError", path: "/prayer" }),
      }),
      env,
    );

    expect(response.status).toBe(204);
    expect(response.headers.get("x-request-id")).toBeTruthy();
    expect(log).toHaveBeenCalledWith(expect.stringContaining('"event":"client_error"'));
  });

  it("exposes a dependency-aware uptime endpoint", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Response.json({ version: "healthy" })));
    const response = await handleRequest(new Request("https://circles.example/healthz"), env);
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual(expect.objectContaining({ ok: true, database: "ok" }));
    expect(response.headers.get("cache-control")).toBe("no-store");
  });

  it("proxies the cover with crawler-friendly cache headers", async () => {
    const fetchMock = vi.fn(async (input: string | URL | Request) => {
      const url = String(input instanceof Request ? input.url : input);
      if (url.includes("get_circle_public_gathering"))
        return Response.json({
          organization: { name: "ELGC" },
          gathering: {
            slug: "lunch",
            title: "Lunch",
            coverUrl: "https://images.example/cover.webp",
          },
        });
      return new Response(new Uint8Array([1, 2, 3]), {
        headers: {
          "content-type": "image/webp",
          "cache-control": "private, no-cache",
          "x-robots-tag": "none",
        },
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    const response = await handleRequest(
      new Request(
        "https://circles.example/__share/gathering-image?organization=elgc&gathering=lunch",
      ),
      env,
    );

    expect(response.headers.get("content-type")).toBe("image/jpeg");
    expect(response.headers.get("cache-control")).toContain("max-age=86400");
    expect(response.headers.get("x-robots-tag")).toBeNull();
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("uses a supplied gathering banner when the gathering has no cover", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        Response.json({
          organization: { name: "ELGC" },
          gathering: { slug: "lunch", title: "Lunch" },
        }),
      ),
    );

    await handleRequest(
      new Request(
        "https://circles.example/__share/gathering-image?organization=elgc&gathering=lunch",
      ),
      env,
    );

    const assetRequest = assets.fetch.mock.calls.at(-1)?.[0] as Request;
    expect(assetRequest.url).toMatch(
      /\/assets\/gathering-placeholder-[12]\.webp$/,
    );
  });

  it("falls back to the SPA when preview data is unavailable", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("No", { status: 404 })));
    const response = await handleRequest(
      new Request("https://circles.example/elgc/gatherings/missing"),
      env,
    );
    expect(await response.text()).toBe(shell);
  });
});
