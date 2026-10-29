import { spawnSync } from "node:child_process";

const executable = process.env.SUPABASE_BIN || "npx";
const prefixArguments = process.env.SUPABASE_BIN ? [] : ["supabase"];
let output;
try {
  const result = spawnSync(executable, [...prefixArguments, "migration", "list", "--linked"], { encoding: "utf8" });
  output = `${result.stdout || ""}\n${result.stderr || ""}`;
  if (result.status !== 0) throw Object.assign(new Error("migration list failed"), { stdout: output });
} catch (error) {
  console.error("Could not read linked migration history. Authenticate and link the canonical SheepCount staging project first.");
  if (error?.stdout) console.error(String(error.stdout));
  process.exit(1);
}

let rows = [];
try {
  const parsed = JSON.parse(resultOutput(output));
  rows = Array.isArray(parsed.migrations) ? parsed.migrations : [];
} catch {
  rows = output.split("\n").map((line) => {
    const match = line.match(/^\s*`?\s*(\d*)\s*`?\s*\|\s*`?\s*(\d*)\s*`?\s*\|/);
    return match ? { local: match[1], remote: match[2] } : null;
  }).filter(Boolean);
}

function resultOutput(value) {
  const start = value.indexOf('{"migrations"');
  const end = value.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error("No JSON result");
  return value.slice(start, end + 1);
}
const missingLocally = rows.filter((row) => !row.local && row.remote).map((row) => row.remote);
const missingRemotely = rows.filter((row) => row.local && !row.remote).map((row) => row.local);
if (missingLocally.length || missingRemotely.length) {
  console.error("Canonical SheepCount migration history is not reconciled.");
  if (missingLocally.length) console.error(`Remote-only versions: ${missingLocally.join(", ")}`);
  if (missingRemotely.length) console.error(`Local-only versions: ${missingRemotely.join(", ")}`);
  process.exit(1);
}
if (!rows.length) {
  console.error("Supabase returned no comparable migration rows.");
  process.exit(1);
}
console.log(`Migration history reconciled: ${rows.length} versions match.`);
