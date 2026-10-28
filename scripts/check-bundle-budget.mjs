import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";

const directory = new URL("../dist/assets/", import.meta.url);
const maximumBytes = 300 * 1024;
const files = (await readdir(directory)).filter((file) => file.endsWith(".js"));
const results = await Promise.all(files.map(async (file) => ({
  file,
  bytes: (await stat(join(directory.pathname, file))).size,
})));
const oversized = results.filter(({ bytes }) => bytes > maximumBytes);
if (oversized.length) {
  console.error(`Bundle budget exceeded (${maximumBytes} bytes per JavaScript chunk):`);
  oversized.forEach(({ file, bytes }) => console.error(`- ${file}: ${bytes} bytes`));
  process.exit(1);
}
console.log(`Bundle budget passed: ${results.length} chunks, each <= ${maximumBytes} bytes.`);
