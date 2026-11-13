import {
  announcementShareUrl,
  galleryImageUrl,
  gatheringShareUrl,
} from "./publicLinks";

describe("public links", () => {
  it("builds a canonical announcement fragment link", () => {
    expect(announcementShareUrl("ministry lens", "update/one")).toBe(
      `${window.location.origin}/ministry%20lens/updates#announcement-update%2Fone`,
    );
  });

  it("uses the shared preview version for gathering links", () => {
    expect(gatheringShareUrl("ministry-lens", "lunch-together")).toBe(
      `${window.location.origin}/ministry-lens/gatherings/lunch-together?share=4`,
    );
  });

  it("builds constrained gallery cover and photo image links", () => {
    expect(galleryImageUrl("ministry lens", "life/together")).toBe(
      `${window.location.origin}/__media/gallery-image?organization=ministry+lens&gallery=life%2Ftogether&v=1`,
    );
    expect(
      galleryImageUrl("ministry lens", "life/together", "photo one"),
    ).toBe(
      `${window.location.origin}/__media/gallery-image?organization=ministry+lens&gallery=life%2Ftogether&photo=photo+one&v=1`,
    );
  });
});
