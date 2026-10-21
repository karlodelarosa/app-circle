import { MAX_COVER_BYTES, validateGatheringCover } from "./images";

describe("gathering cover validation", () => {
  it("accepts supported image files", () => {
    expect(() =>
      validateGatheringCover(
        new File(["image"], "cover.webp", { type: "image/webp" }),
      ),
    ).not.toThrow();
  });

  it("rejects unsupported and oversized files", () => {
    expect(() =>
      validateGatheringCover(
        new File(["image"], "cover.gif", { type: "image/gif" }),
      ),
    ).toThrow("Choose a JPG, PNG, or WebP image.");
    const oversized = new File(
      [new Uint8Array(MAX_COVER_BYTES + 1)],
      "cover.jpg",
      {
        type: "image/jpeg",
      },
    );
    expect(() => validateGatheringCover(oversized)).toThrow(
      "The cover image must be 10 MB or smaller.",
    );
  });
});
