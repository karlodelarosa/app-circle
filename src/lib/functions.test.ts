import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";
import { getFunctionErrorMessage, invokeAuthenticatedFunction } from "./functions";

describe("invokeAuthenticatedFunction", () => {
  it("sends the current session access token explicitly", async () => {
    const invoke = vi.fn().mockResolvedValue({ data: { ok: true }, error: null });
    const client = {
      auth: {
        getSession: vi.fn().mockResolvedValue({
          data: { session: { access_token: "current-token" } },
          error: null,
        }),
      },
      functions: { invoke },
    } as unknown as SupabaseClient;

    await invokeAuthenticatedFunction(client, "circle-member-access", {
      action: "provision",
    });

    expect(invoke).toHaveBeenCalledWith("circle-member-access", {
      body: { action: "provision" },
      headers: { Authorization: "Bearer current-token" },
    });
  });

  it("stops before invoking when the sign-in session is missing", async () => {
    const invoke = vi.fn();
    const client = {
      auth: {
        getSession: vi.fn().mockResolvedValue({
          data: { session: null },
          error: null,
        }),
      },
      functions: { invoke },
    } as unknown as SupabaseClient;

    await expect(
      invokeAuthenticatedFunction(client, "circle-member-access", {}),
    ).rejects.toThrow("sign-in session has expired");
    expect(invoke).not.toHaveBeenCalled();
  });

  it("reads the useful error returned by an Edge Function", async () => {
    const message = await getFunctionErrorMessage(
      {
        data: null,
        error: {
          message: "Edge Function returned a non-2xx status code",
          context: new Response(JSON.stringify({
            error: "Use at least 10 characters with uppercase, lowercase, and a number.",
          }), { status: 400, headers: { "content-type": "application/json" } }),
        },
      },
      "Password could not be changed.",
    );

    expect(message).toBe(
      "Use at least 10 characters with uppercase, lowercase, and a number.",
    );
  });
});
