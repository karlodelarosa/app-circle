import { prayerShareUrl } from "./prayerLinks";

describe("prayerShareUrl", () => {
  it("builds a Circle board link that preserves the active tab", () => {
    expect(prayerShareUrl("circle-1", "answered")).toBe(
      `${window.location.origin}/prayer?circle=circle-1&tab=answered`,
    );
  });

  it("adds a prayer id for a focused private deep link", () => {
    expect(prayerShareUrl("circle-1", "in-prayer", "prayer-1")).toBe(
      `${window.location.origin}/prayer?circle=circle-1&tab=in-prayer&prayer=prayer-1`,
    );
  });
});
