import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? "html" : "list",
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "desktop-chromium", testIgnore: /authenticated-community\.spec\.ts/, use: { ...devices["Desktop Chrome"] } },
    { name: "mobile-chromium", testIgnore: /authenticated-community\.spec\.ts/, use: { ...devices["Pixel 5"] } },
    { name: "community-desktop", testMatch: /authenticated-community\.spec\.ts/, use: { ...devices["Desktop Chrome"], baseURL: "http://127.0.0.1:4174" } },
    { name: "community-mobile", testMatch: /authenticated-community\.spec\.ts/, use: { ...devices["Pixel 5"], baseURL: "http://127.0.0.1:4174" } },
  ],
  webServer: [
    {
      command: "npm run preview:vite -- --host 127.0.0.1",
      port: 4173,
      reuseExistingServer: !process.env.CI,
    },
    {
      command: "VITE_DEMO_MODE=true npx vite --mode e2e --host 127.0.0.1 --port 4174",
      port: 4174,
      reuseExistingServer: !process.env.CI,
    },
  ],
});
