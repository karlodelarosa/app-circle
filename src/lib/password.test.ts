import { describe, expect, it } from "vitest";
import { validatePassword } from "./password";

describe("validatePassword", () => {
  it("explains each missing password requirement", () => {
    expect(validatePassword("Short1A")).toMatch(/10 characters/);
    expect(validatePassword("lowercase12")).toMatch(/uppercase/);
    expect(validatePassword("UPPERCASE12")).toMatch(/lowercase/);
    expect(validatePassword("NoNumbersHere")).toMatch(/number/);
    expect(validatePassword("ValidPass12")).toBeNull();
  });
});
