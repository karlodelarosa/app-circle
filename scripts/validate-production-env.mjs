import { pathToFileURL } from "node:url";

const requiredVariables = [
  "VITE_SUPABASE_URL",
  "VITE_SUPABASE_PUBLISHABLE_OR_ANON_KEY",
  "VITE_TURNSTILE_SITE_KEY",
];

const isPlaceholder = (value) =>
  /^(your-|replace-|change-me|placeholder)/i.test(value.trim());

export function validateProductionEnv(environment) {
  const invalid = requiredVariables.filter((name) => {
    const value = environment[name]?.trim() ?? "";
    return !value || isPlaceholder(value);
  });

  const supabaseUrl = environment.VITE_SUPABASE_URL?.trim() ?? "";
  if (supabaseUrl) {
    try {
      if (new URL(supabaseUrl).protocol !== "https:") invalid.push("VITE_SUPABASE_URL");
    } catch {
      invalid.push("VITE_SUPABASE_URL");
    }
  }

  if (invalid.length) {
    throw new Error(
      `Production build configuration is missing or invalid: ${[...new Set(invalid)].join(", ")}`,
    );
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    const { loadEnv } = await import("vite");
    validateProductionEnv({
      ...loadEnv("production", process.cwd(), ""),
      ...process.env,
    });
    console.log("Production build configuration is present.");
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
