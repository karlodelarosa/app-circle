import { announcementShareUrl } from "./publicLinks";

describe("public links", () => {
  it("builds a canonical announcement fragment link", () => {
    expect(announcementShareUrl("ministry lens", "update/one")).toBe(
      `${window.location.origin}/ministry%20lens/updates#announcement-update%2Fone`,
    );
  });
});
