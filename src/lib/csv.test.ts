import { createCsv } from "./csv";

describe("createCsv", () => {
  it("escapes spreadsheet values without losing delimiters or quotes", () => {
    expect(createCsv(["Name", "Note"], [["Mara, Santos", 'Said "hello"']]))
      .toBe('"Name","Note"\r\n"Mara, Santos","Said ""hello"""');
  });

  it("neutralizes formulas in exported user-controlled values", () => {
    expect(createCsv(["Value"], [["=HYPERLINK(\"https://example.com\")"], ["+1-555-0100"]]))
      .toBe('"Value"\r\n"\'=HYPERLINK(""https://example.com"")"\r\n"\'+1-555-0100"');
  });
});
