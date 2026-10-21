import { afterEach, describe, expect, it, vi } from "vitest";
import { handleRequest, type WorkerEnv } from "./index";

const shell = `<!doctype html><html><head><meta name="description" content="Default"><title>Circles</title></head><body><div id="root"></div></body></html>`;

const assets = {
  fetch: vi.fn(async () =>
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
          gatherings: [
            {
              slug: "lunch",
              title: "Lunch <Together>",
              summary: 'Bring friends & say "hello".',
              coverUrl: "https://images.example/cover.webp",
            },
          ],
        }),
      ),
    );

    const response = await handleRequest(
      new Request("https://circles.example/elgc/gatherings/lunch?share=1"),
      env,
    );
    const html = await response.text();

    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("cache-control")).toContain("s-maxage=300");
    expect(html).toContain("Lunch &lt;Together&gt; | ELGC &amp; Friends");
    expect(html).toContain(
      'property="og:image" content="https://circles.example/__share/gathering-image?organization=elgc&amp;gathering=lunch"',
    );
    expect(html).toContain('property="og:image:type" content="image/jpeg"');
    expect(html).toContain(
      'property="og:url" content="https://circles.example/elgc/gatherings/lunch?share=1"',
    );
    expect(html).not.toContain('content="Default"');
  });

  it("falls back to static assets for ordinary routes", async () => {
    const request = new Request("https://circles.example/gatherings");
    const response = await handleRequest(request, env);
    expect(await response.text()).toBe(shell);
    expect(assets.fetch).toHaveBeenCalledWith(request);
  });

  it("proxies the cover with crawler-friendly cache headers", async () => {
    const fetchMock = vi.fn(async (input: string | URL | Request) => {
      const url = String(input instanceof Request ? input.url : input);
      if (url.includes("get_circle_public_space"))
        return Response.json({
          organization: { name: "ELGC" },
          gatherings: [
            {
              slug: "lunch",
              title: "Lunch",
              coverUrl: "https://images.example/cover.webp",
            },
          ],
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

  it("falls back to the SPA when preview data is unavailable", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("No", { status: 404 })));
    const response = await handleRequest(
      new Request("https://circles.example/elgc/gatherings/missing"),
      env,
    );
    expect(await response.text()).toBe(shell);
  });
});
