import { expect, test } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("members can react, follow prayers, save, search, and open deep links", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Community feed" })).toBeVisible();
  await expect(page.getByLabel("Post audience")).toHaveValue("organization");

  await page.getByRole("button", { name: /choose a reaction/i }).first().click();
  await page.getByRole("menuitemradio", { name: "Amen" }).click();
  await expect(page.getByRole("button", { name: /Amen · 2/ })).toBeVisible();

  const prayer = page.getByRole("article", { name: /Prayer request: Wisdom for a new season/ });
  await prayer.getByRole("button", { name: "Follow updates" }).click();
  await expect(prayer.getByRole("button", { name: "Following" })).toBeVisible();
  await expect(prayer.getByRole("button", { name: /Praying · 8/ })).toBeVisible();

  const update = page.getByRole("article", { name: /Update: I was reminded/ });
  await update.getByRole("button", { name: "Post actions" }).click();
  await update.getByRole("menuitem", { name: "Save post" }).click();
  await page.goto("/community-settings");
  await expect(page.getByRole("heading", { name: "Saved posts" })).toBeVisible();
  await expect(page.getByRole("link", { name: /small acts of kindness/ })).toBeVisible();

  await page.goto("/feed/feed-post-1");
  await expect(page.getByRole("heading", { name: "Community post" })).toBeVisible();
  await expect(page.getByText(/small acts of kindness can become/)).toBeVisible();

  await page.goto("/");
  await page.getByRole("searchbox", { name: "Search community" }).fill("answered prayer");
  await expect(page.getByRole("article", { name: /Update: I was reminded/ })).toBeVisible();
  await expect(page.getByRole("article", { name: /Prayer request: Wisdom/ })).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test("community profiles expose privacy controls without private contact details", async ({ page }) => {
  await page.goto("/members");
  await expect(page.getByRole("heading", { name: "Members" })).toBeVisible();
  await expect(page.getByText(/@/)).toHaveCount(0);

  await page.getByRole("link", { name: /Karlo de la Rosa/ }).click();
  await page.getByRole("button", { name: "Edit profile" }).click();
  await page.getByLabel("Who can see your bio").selectOption("hidden");
  await page.getByLabel("Who can see your join date").selectOption("shared_circle");
  await page.getByRole("button", { name: "Save profile" }).click();
  await expect(page.getByRole("button", { name: "Edit profile" })).toBeVisible();

  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations.filter((violation) => ["serious", "critical"].includes(violation.impact || "")))
    .toEqual([]);
});

test("the authenticated feed is responsive without horizontal overflow", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Community feed" })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
