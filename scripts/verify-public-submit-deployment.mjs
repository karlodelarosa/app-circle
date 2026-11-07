import { loadEnv } from "vite";

const environment = {
  ...loadEnv("production", process.cwd(), ""),
  ...process.env,
};
const supabaseUrl = environment.VITE_SUPABASE_URL?.trim();
const publicOrigin = environment.CIRCLES_PUBLIC_ORIGIN?.trim()
  || "https://circles.elgchurch.com";

if (!supabaseUrl) {
  throw new Error("VITE_SUPABASE_URL is required to verify circle-public-submit.");
}

const endpoint = new URL("/functions/v1/circle-public-submit", supabaseUrl);
const response = await fetch(endpoint, {
  method: "OPTIONS",
  headers: {
    Origin: publicOrigin,
    "Access-Control-Request-Method": "POST",
    "Access-Control-Request-Headers": "apikey,authorization,content-type,x-client-info",
  },
  signal: AbortSignal.timeout(10_000),
});

const allowedOrigin = response.headers.get("access-control-allow-origin");
if (response.status !== 204 || allowedOrigin !== publicOrigin) {
  throw new Error(
    `circle-public-submit smoke check failed: HTTP ${response.status}, allowed origin ${allowedOrigin || "missing"}.`,
  );
}

console.log(`circle-public-submit is active and allows ${publicOrigin}.`);
