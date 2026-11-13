import { expect, test } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("public community discovery works", async ({ page }) => {
  await page.goto("/ministry-lens-church?demo=1");

  await expect(page.getByRole("heading", { name: "There is room for you here." })).toBeVisible();
  await expect(page.getByRole("link", { name: "Find a gathering" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Sign up for a Cell Group" })).toBeVisible();
});

test("sign-in remains accessible", async ({ page }) => {
  await page.goto("/sign-in");

  await expect(page.getByRole("heading", { name: "Return to your circle." })).toBeVisible();
  await expect(page.getByLabel("Email or Member ID")).toBeVisible();
  await expect(page.getByLabel("Password", { exact: true })).toBeVisible();
});

for (const [name, path] of [
  ["public community", "/ministry-lens-church?demo=1"],
  ["sign-in", "/sign-in"],
] as const) {
  test(`${name} has no serious accessibility violations`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(path);
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations.filter((violation) => ["serious", "critical"].includes(violation.impact || "")))
      .toEqual([]);
  });
}

test("announcement links focus cleanly without responsive overflow", async ({ page }) => {
  for (const width of [320, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(
      "/ministry-lens-church/updates?demo=1#announcement-announcement-1",
    );
    const announcement = page.locator("#announcement-announcement-1");
    await expect(announcement).toBeVisible();
    await expect(announcement).toBeFocused();
    await expect(announcement.getByRole("button", { name: "Share" })).toBeVisible();
    await expect(
      announcement.getByRole("button", { name: "Copy link" }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
  }
});

test("app browse mode stays read-only and responsive", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));

  for (const width of [320, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/ministry-lens-church?demo=1&browse=1");

    await expect(page.getByText("Public preview")).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Sign up for a Cell Group" }),
    ).toHaveCount(0);
    await expect(page.getByRole("link", { name: "Sign in" })).toHaveCount(0);
    await expect(
      page.getByRole("link", { name: "Find a gathering" }),
    ).toHaveAttribute(
      "href",
      "/ministry-lens-church/gatherings?browse=1",
    );
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
  }

  expect(pageErrors).toEqual([]);
});
