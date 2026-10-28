import { describe, expect, it } from "vitest";
import {
  formatGatheringDateTime,
  gatheringLifecycle,
  gatheringRelativeStatus,
} from "./gatheringLifecycle";

const meeting = {
  status: "scheduled" as const,
  meetingDate: "2026-10-12T03:00:00.000Z",
  endsAt: "2026-10-12T05:00:00.000Z",
};

describe("gatheringLifecycle", () => {
  it("is upcoming immediately before the start", () => {
    expect(
      gatheringLifecycle(meeting, new Date("2026-10-12T02:59:59.999Z")),
    ).toBe("upcoming");
  });

  it("is live from the exact start through the exact end", () => {
    expect(
      gatheringLifecycle(meeting, new Date("2026-10-12T03:00:00.000Z")),
    ).toBe("live");
    expect(
      gatheringLifecycle(meeting, new Date("2026-10-12T05:00:00.000Z")),
    ).toBe("live");
  });

  it("needs attendance immediately after the end", () => {
    expect(
      gatheringLifecycle(meeting, new Date("2026-10-12T05:00:00.001Z")),
    ).toBe("attendance_pending");
  });

  it("gives persisted terminal states precedence over time", () => {
    expect(
      gatheringLifecycle(
        { ...meeting, status: "completed" },
        new Date("2026-10-12T02:00:00.000Z"),
      ),
    ).toBe("completed");
    expect(
      gatheringLifecycle(
        { ...meeting, status: "cancelled" },
        new Date("2026-10-12T04:00:00.000Z"),
      ),
    ).toBe("cancelled");
  });
});

describe("gathering lifecycle copy", () => {
  it("formats a same-day start and end as one date with a time range", () => {
    const value = formatGatheringDateTime(
      new Date(2026, 9, 12, 11, 0).toISOString(),
      new Date(2026, 9, 12, 13, 0).toISOString(),
    );
    expect(value).toContain("2026");
    expect(value).toMatch(/11:00 AM/);
    expect(value).toMatch(/1:00 PM/);
  });

  it("describes an event that ended sixteen days ago", () => {
    expect(
      gatheringRelativeStatus(
        meeting.endsAt,
        new Date("2026-10-28T05:00:00.000Z"),
      ),
    ).toBe("Ended 16 days ago");
  });
});
