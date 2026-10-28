import { gatheringIcs } from "./calendar";

describe("gatheringIcs", () => {
  it("creates a standards-compatible UTC calendar event and escapes text", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-28T10:00:00Z"));
    const result = gatheringIcs({
      id: "gathering-1", groupId: "group-1",
      title: "Dinner, prayer; and stories", meetingDate: "2026-11-01T10:00:00Z",
      endsAt: "2026-11-01T12:00:00Z", location: "Main Hall", studyTopic: "",
      notes: "Bring a friend", status: "scheduled", createdBy: "user-1", rsvps: {},
    }, "https://circles.example/church/gatherings/dinner");
    expect(result).toContain("DTSTART:20261101T100000Z");
    expect(result).toContain("SUMMARY:Dinner\\, prayer\\; and stories");
    expect(result).toContain("URL:https://circles.example/church/gatherings/dinner");
    vi.useRealTimers();
  });
});
