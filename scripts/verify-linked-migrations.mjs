import { execFileSync } from "node:child_process";

const executable = process.env.SUPABASE_BIN || "supabase";
let output;
try {
  output = execFileSync(executable, ["migration", "list", "--linked"], { encoding: "utf8" });
} catch (error) {
  console.error("Could not read linked migration history. Authenticate and link the canonical SheepCount staging project first.");
  if (error?.stdout) console.error(String(error.stdout));
  process.exit(1);
}

const rows = output.split("\n").map((line) => {
  const match = line.match(/^\s*(\d*)\s*\|\s*(\d*)\s*\|/);
  return match ? { local: match[1], remote: match[2] } : null;
}).filter(Boolean);
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
