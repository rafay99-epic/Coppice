import { defineConfig, devices } from "@playwright/test";

const port = 4390;
const external = process.env.E2E_BASE_URL;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  reporter: "list",
  use: {
    baseURL: external ?? `http://127.0.0.1:${port}`,
    channel: "chrome",
    headless: true,
  },
  projects: [
    { name: "desktop", use: { ...devices["Desktop Chrome"], channel: "chrome" } },
    { name: "mobile", use: { ...devices["Pixel 7"], channel: "chrome" } },
  ],
  webServer: external
    ? undefined
    : {
        command: `bun run build && bunx serve@14 out -l ${port} --no-clipboard`,
        url: `http://127.0.0.1:${port}`,
        reuseExistingServer: false,
        timeout: 180_000,
      },
});
