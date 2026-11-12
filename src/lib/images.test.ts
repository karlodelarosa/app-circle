import {
  GATHERING_PLACEHOLDERS,
  MAX_COVER_BYTES,
  gatheringCoverImage,
  validateGatheringCover,
  validateFeedPhotos,
} from "./images";

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

describe("gathering cover fallback", () => {
  it("keeps an uploaded cover and otherwise assigns a stable placeholder", () => {
    expect(gatheringCoverImage("gathering-1", "/uploaded.webp")).toBe(
      "/uploaded.webp",
    );
    expect(gatheringCoverImage("gathering-1")).toBe(
      gatheringCoverImage("gathering-1"),
    );
    expect(GATHERING_PLACEHOLDERS).toContain(gatheringCoverImage("gathering-1"));
    expect(gatheringCoverImage("gathering-1")).not.toBe(
      gatheringCoverImage("gathering-2"),
    );
  });
});

describe("feed photo validation", () => {
  it("accepts up to four supported photos", () => {
    const photos = Array.from({ length: 4 }, (_, index) =>
      new File(["image"], `photo-${index}.jpg`, { type: "image/jpeg" }),
    );
    expect(() => validateFeedPhotos(photos)).not.toThrow();
  });

  it("rejects a fifth photo and unsupported media", () => {
    const photos = Array.from({ length: 5 }, (_, index) =>
      new File(["image"], `photo-${index}.jpg`, { type: "image/jpeg" }),
    );
    expect(() => validateFeedPhotos(photos)).toThrow("up to four photos");
    expect(() => validateFeedPhotos([
      new File(["video"], "clip.mp4", { type: "video/mp4" }),
    ])).toThrow("JPG, PNG, or WebP");
  });
});
