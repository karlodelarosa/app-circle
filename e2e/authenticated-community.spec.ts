import { expect, test } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("members can react, follow prayers, save, search, and open deep links", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Community feed" })).toBeVisible();
  await page.getByLabel("Share an update").click();
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
  await page.getByRole("button", { name: "Open community search" }).click();
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

test("action menus keep icons, labels, and links in compact aligned rows", async ({ page }) => {
  await page.goto("/");
  const update = page.getByRole("article", { name: /Update: I was reminded/ });
  await update.getByRole("button", { name: "Post actions" }).click();

  const feedMenu = update.getByRole("menu");
  await expect(feedMenu).toBeVisible();
  await expect(feedMenu.getByRole("menuitem", { name: "Hide from feed" })).toBeVisible();
  expect(await feedMenu.evaluate((menu) => {
    const rect = menu.getBoundingClientRect();
    return rect.left >= 0 && rect.right <= window.innerWidth;
  })).toBe(true);
  const saveItem = feedMenu.getByRole("menuitem", { name: "Save post" });
  await expect(saveItem).toHaveCSS("display", "flex");
  await expect(saveItem).toHaveCSS("align-items", "center");
  expect(await saveItem.evaluate((item) => {
    const icon = item.querySelector("svg");
    if (!icon) return false;
    const itemRect = item.getBoundingClientRect();
    const iconRect = icon.getBoundingClientRect();
    return Math.abs(
      iconRect.top + iconRect.height / 2 - (itemRect.top + itemRect.height / 2),
    ) < 1;
  })).toBe(true);

  await page.goto("/circles/demo-group");
  await page.getByRole("button", { name: "Circle actions" }).click();
  const circleMenu = page.getByRole("menu");
  await expect(circleMenu.getByRole("menuitem", { name: "View all Circles" })).toHaveCSS(
    "display",
    "flex",
  );
});

test("compact feed keeps posts in view and expands tools on demand", async ({ page }) => {
  await page.goto("/");
  const composer = page.getByRole("form", { name: "Create a community post" });
  const input = page.getByLabel("Share an update");
  for (const width of [320, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(input).toBeVisible();
    expect((await composer.boundingBox())!.height).toBeLessThan(90);
    expect((await page.getByRole("article").first().boundingBox())!.y).toBeLessThan(400);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: "/tmp/circles-feed-mobile.png" });
  await input.fill("A thought to finish later");
  await page.getByLabel("Post audience").selectOption("demo-group");
  await composer.getByRole("button", { name: "Collapse" }).click();
  await expect(page.getByLabel("Post audience")).toHaveCount(0);
  await input.click();
  await expect(input).toHaveValue("A thought to finish later");
  await expect(page.getByLabel("Post audience")).toHaveValue("demo-group");
  await expect(composer.getByRole("button", { name: "Add photos" })).toBeVisible();
  await composer.getByRole("button", { name: "Post update" }).click();
  await expect(page.getByRole("article", { name: /A thought to finish later/ })).toBeVisible();
  await expect(page.getByLabel("Post audience")).toHaveCount(0);
  await page.getByRole("button", { name: "Open community search" }).click();
  await expect(page.getByRole("searchbox", { name: "Search community" })).toBeVisible();
  await page.getByText("More search filters").click();
  await expect(page.getByLabel("Activity type")).toBeVisible();
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations.filter((violation) => ["serious", "critical"].includes(violation.impact || ""))).toEqual([]);
  await page.getByRole("button", { name: "Close community search" }).click();
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.screenshot({ path: "/tmp/circles-feed-desktop.png" });
});
