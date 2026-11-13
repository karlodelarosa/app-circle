import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

function jpegDimensions(bytes: Buffer) {
  expect(bytes.subarray(0, 2)).toEqual(Buffer.from([0xff, 0xd8]));
  for (let offset = 2; offset < bytes.length - 9;) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    const marker = bytes[offset + 1];
    const segmentLength = bytes.readUInt16BE(offset + 2);
    if (marker >= 0xc0 && marker <= 0xc3)
      return {
        height: bytes.readUInt16BE(offset + 5),
        width: bytes.readUInt16BE(offset + 7),
      };
    offset += 2 + segmentLength;
  }
  throw new Error("JPEG dimensions were not found");
}

describe("gathering share assets", () => {
  it.each([1, 2])("keeps fallback %s as a 1200 by 630 JPEG", (variant) => {
    const bytes = readFileSync(
      resolve(
        process.cwd(),
        `public/assets/gathering-share-placeholder-${variant}.jpg`,
      ),
    );

    expect(jpegDimensions(bytes)).toEqual({ width: 1200, height: 630 });
  });
});
