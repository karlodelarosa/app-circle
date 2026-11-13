import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { validatePublicSubmission, type ValidPublicSubmission } from "../_shared/public-submit-schema.ts";

const MAX_BODY_BYTES = 16_384;
const RATE_LIMIT = 10;
const RATE_WINDOW_SECONDS = 15 * 60;

const allowedOrigins = () => new Set(
  (Deno.env.get("CIRCLES_ALLOWED_ORIGINS") || "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
);

const corsHeaders = (origin: string) => ({
  "access-control-allow-origin": origin,
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-request-id",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-max-age": "86400",
  vary: "Origin",
});

const response = (
  origin: string,
  requestId: string,
  body: { ok: boolean; data?: unknown; error?: string },
  status = 200,
) => Response.json(body, {
  status,
  headers: {
    ...corsHeaders(origin),
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "x-request-id": requestId,
  },
});

const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
};

async function verifyBot(token: string, ip: string) {
  const secret = Deno.env.get("CLOUDFLARE_TURNSTILE_SECRET");
  if (!secret || !token) return false;
  const form = new FormData();
  form.set("secret", secret);
  form.set("response", token);
  if (ip) form.set("remoteip", ip);
  const verification = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body: form,
  });
  if (!verification.ok) return false;
  const result = await verification.json() as { success?: boolean };
  return result.success === true;
}

function rpcFor(submission: ValidPublicSubmission) {
  const payload = submission.payload;
  switch (submission.action) {
    case "guest_rsvp":
      return ["submit_circle_guest_rsvp", {
        p_gathering_id: payload.gatheringId,
        p_name: payload.name,
        p_email: payload.email,
        p_phone: payload.phone,
        p_status: payload.status,
      }] as const;
    case "circle_connection":
      return ["request_circle_connection", {
        p_cell_group_id: payload.groupId,
        p_guest_rsvp_id: payload.guestRsvpId,
        p_name: payload.name,
        p_email: payload.email,
        p_phone: payload.phone,
        p_preferred_contact: payload.preferredContact,
        p_message: payload.message,
        p_consent: payload.consent,
      }] as const;
    case "circle_interest":
      return ["submit_circle_interest", {
        p_listing_id: payload.listingId,
        p_name: payload.name,
        p_contact: payload.contact,
        p_message: payload.message,
      }] as const;
    case "group_signup":
      return ["submit_circle_group_signup", {
        p_org_slug: payload.organizationSlug,
        p_first_name: payload.firstName,
        p_last_name: payload.lastName,
        p_birthdate: payload.birthdate,
        p_phone: payload.phone,
        p_facebook_contact: payload.facebookContact,
        p_consent: payload.consent,
        p_guest_rsvp_id: payload.guestRsvpId,
      }] as const;
  }
}

Deno.serve(async (request) => {
  const requestIdHeader = request.headers.get("x-request-id") || "";
  const requestId = /^[A-Za-z0-9._-]{1,128}$/.test(requestIdHeader)
    ? requestIdHeader
    : crypto.randomUUID();
  const origin = request.headers.get("origin") || "";
  const origins = allowedOrigins();
  if (!origin || !origins.has(origin))
    return response(origin, requestId, { ok: false, error: "Request not allowed" }, 403);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (request.method !== "POST") return response(origin, requestId, { ok: false, error: "Method not allowed" }, 405);
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))
    return response(origin, requestId, { ok: false, error: "Invalid submission" }, 415);
  const declaredSize = Number(request.headers.get("content-length") || "0");
  if (declaredSize > MAX_BODY_BYTES)
    return response(origin, requestId, { ok: false, error: "Invalid submission" }, 413);

  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES)
      return response(origin, requestId, { ok: false, error: "Invalid submission" }, 413);
    const validated = validatePublicSubmission(JSON.parse(raw));
    if (!validated.ok) return response(origin, requestId, validated, 400);

    const ip = (request.headers.get("cf-connecting-ip") || request.headers.get("x-forwarded-for") || "")
      .split(",")[0].trim();
    const salt = Deno.env.get("PUBLIC_RATE_LIMIT_SALT");
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!salt || !url || !serviceKey) throw new Error("Missing protected submission configuration");
    const service = createClient(url, serviceKey, { auth: { persistSession: false } });
    const rateKey = await sha256(`${salt}:${ip || "unknown"}:${validated.value.action}`);
    const limited = await service.rpc("circle_consume_public_submission_limit", {
      p_key: rateKey,
      p_limit: RATE_LIMIT,
      p_window_seconds: RATE_WINDOW_SECONDS,
    });
    if (limited.error) throw limited.error;
    if (limited.data !== true) {
      console.warn(JSON.stringify({ event: "public_submission_rate_limited", requestId, action: validated.value.action }));
      return response(origin, requestId, { ok: false, error: "Too many attempts. Please try again later." }, 429);
    }
    if (!await verifyBot(validated.value.botToken, ip)) {
      console.warn(JSON.stringify({ event: "public_submission_bot_rejected", requestId, action: validated.value.action }));
      return response(origin, requestId, { ok: false, error: "Verification failed. Please try again." }, 400);
    }

    const [rpc, parameters] = rpcFor(validated.value);
    const result = await service.rpc(rpc, parameters);
    if (result.error) throw result.error;
    console.log(JSON.stringify({ event: "public_submission_accepted", requestId, action: validated.value.action }));
    return response(origin, requestId, { ok: true, data: result.data });
  } catch (error) {
    console.error(JSON.stringify({
      event: "public_submission_failed",
      requestId,
      errorType: error instanceof Error ? error.name : "UnknownError",
    }));
    return response(origin, requestId, { ok: false, error: "Submission could not be completed." }, 500);
  }
});
