export const requestId = (request: Request) => {
  const supplied = request.headers.get("x-request-id") || "";
  return /^[A-Za-z0-9._-]{1,128}$/.test(supplied) ? supplied : crypto.randomUUID();
};

export const allowedOrigin = (request: Request) => {
  const origin = request.headers.get("origin") || "";
  const allowed = new Set(
    (Deno.env.get("CIRCLES_ALLOWED_ORIGINS") || "")
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
  );
  return origin && allowed.has(origin) ? origin : null;
};

export const corsHeaders = (origin: string) => ({
  "access-control-allow-origin": origin,
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-request-id",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
  vary: "Origin",
});

export const jsonResponse = (origin: string, id: string, body: unknown, status = 200) =>
  Response.json(body, {
    status,
    headers: {
      ...corsHeaders(origin),
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "x-request-id": id,
    },
  });

export async function readJsonBody(request: Request, maximumBytes = 16_384) {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))
    throw new Error("invalid_content_type");
  const declared = Number(request.headers.get("content-length") || "0");
  if (declared > maximumBytes) throw new Error("body_too_large");
  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > maximumBytes) throw new Error("body_too_large");
  return JSON.parse(raw) as unknown;
}
