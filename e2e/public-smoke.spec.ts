import { expect, test } from "@playwright/test";

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
