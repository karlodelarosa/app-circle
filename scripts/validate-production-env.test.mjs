import { describe, expect, it } from "vitest";
import { validateProductionEnv } from "./validate-production-env.mjs";

const validEnvironment = {
  VITE_SUPABASE_URL: "https://project.supabase.co",
  VITE_SUPABASE_PUBLISHABLE_OR_ANON_KEY: "publishable-key",
  VITE_TURNSTILE_SITE_KEY: "turnstile-site-key",
};

describe("validateProductionEnv", () => {
  it("accepts a complete production environment", () => {
    expect(() => validateProductionEnv(validEnvironment)).not.toThrow();
  });

  it.each([
    "VITE_SUPABASE_URL",
    "VITE_SUPABASE_PUBLISHABLE_OR_ANON_KEY",
    "VITE_TURNSTILE_SITE_KEY",
  ])("rejects a missing %s", (name) => {
    expect(() =>
      validateProductionEnv({ ...validEnvironment, [name]: "" }),
    ).toThrow(name);
  });

  it("rejects placeholder values", () => {
    expect(() =>
      validateProductionEnv({
        ...validEnvironment,
        VITE_TURNSTILE_SITE_KEY: "your-cloudflare-turnstile-site-key",
      }),
    ).toThrow("VITE_TURNSTILE_SITE_KEY");
  });
});
