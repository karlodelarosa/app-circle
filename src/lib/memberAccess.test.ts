import { describe, expect, it } from "vitest";
import { memberIdToEmail } from "./memberAccess";

describe("memberIdToEmail", () => {
  it("maps a friendly Member ID to the internal production login domain", () => {
    expect(memberIdToEmail(" Maria.Santos-K7P4 ")).toBe(
      "maria.santos-k7p4@members.circles.elgchurch.com",
    );
  });
});
