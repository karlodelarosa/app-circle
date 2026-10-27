import {
  findAvailableMemberId,
  memberIdBase,
} from "./member-id";

describe("memberIdBase", () => {
  it("uses only the first word of a compound first name", () => {
    expect(memberIdBase("John Karlo")).toBe("john");
  });

  it("normalizes capitalization, accents, and punctuation", () => {
    expect(memberIdBase("  José-Luis  ")).toBe("joseluis");
  });

  it("falls back when the first word has no Latin letters or numbers", () => {
    expect(memberIdBase("王 小明")).toBe("member");
  });
});

describe("findAvailableMemberId", () => {
  it("returns a short first-name and four-digit identifier", async () => {
    const result = await findAvailableMemberId(
      "John Karlo",
      async () => true,
      () => 4827,
    );

    expect(result).toBe("john-4827");
  });

  it("retries when a candidate is already in use", async () => {
    const suffixes = [4827, 7314];
    const checked: string[] = [];

    const result = await findAvailableMemberId(
      "John",
      async (candidate) => {
        checked.push(candidate);
        return candidate !== "john-4827";
      },
      () => suffixes.shift()!,
    );

    expect(checked).toEqual(["john-4827", "john-7314"]);
    expect(result).toBe("john-7314");
  });
});
