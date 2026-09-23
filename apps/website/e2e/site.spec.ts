import { expect, test, type Page } from "@playwright/test";

function collectProblems(page: Page) {
  const problems: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error" || message.type() === "warning") problems.push(message.text());
  });
  page.on("pageerror", (error) => problems.push(error.message));
  return problems;
}

test("loads without console errors or hydration warnings", async ({ page }) => {
  const problems = collectProblems(page);
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Cut it back.");
  await page.waitForLoadState("networkidle");
  expect(problems).toEqual([]);
});

test("sections reveal as they scroll into view", async ({ page }) => {
  await page.goto("/");
  const heading = page.getByRole("heading", { name: /Three things it/ });
  await expect(heading).toHaveCSS("opacity", "0");
  await heading.scrollIntoViewIfNeeded();
  await expect(heading).toHaveCSS("opacity", "1");
});

test("content stays visible with reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await expect(page.getByRole("heading", { name: /Three things it/ })).toHaveCSS("opacity", "1");
});

test("content is readable without JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto("/");
  await expect(page.getByRole("heading", { name: /Three things it/ })).toHaveCSS("opacity", "1");
  await context.close();
});

test("page never scrolls sideways", async ({ page }) => {
  await page.goto("/");
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});

test("copy button copies the install command", async ({ page, context, browserName }) => {
  test.skip(browserName !== "chromium", "clipboard permissions are Chromium only");
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.goto("/");
  const button = page.getByRole("button", { name: "Copy: brew install --cask rafay99-epic/apps/coppice" }).first();
  await button.click();
  await expect(button).toHaveText("Copied");
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe("brew install --cask rafay99-epic/apps/coppice");
});
