import { expect, test } from "@playwright/test";

test("panel follows the B layout", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("panel")).toBeVisible();
  await expect(page.getByTestId("weekly-quota")).toContainText("84%");
  await expect(page.getByTestId("reset-credit")).toContainText("1 张");
  await expect(page.getByTestId("reset-radar")).toContainText("3/4");
  await expect(page.getByTestId("model-health")).toContainText("正常");
  await expect(page.getByTestId("model-health")).toContainText("42.3 tok/s");
  await expect(page.getByTestId("current-session")).toContainText("输出速率");
  await expect(page.getByTestId("account-stats")).toContainText("3.3B");
  const order = await page.locator("[data-section]").evaluateAll((nodes) =>
    nodes.map((node) => node.getAttribute("data-section"))
  );
  expect(order).toEqual([
    "quota", "reset-credit", "reset-radar", "model-health",
    "current-session", "account-stats",
  ]);
});

test("the header carries the plan badge, the refresh and the close button", async ({ page }) => {
  await page.goto("/");
  const panel = page.getByTestId("panel");
  await expect(panel.getByText("用量")).toBeVisible();
  await expect(page.getByTestId("plan-badge")).toHaveText("pro");
  await expect(panel.getByRole("button", { name: "刷新" })).toBeVisible();
  await expect(panel.getByRole("button", { name: "关闭" })).toBeVisible();
});

test("the panel keeps the size of the B layout", async ({ page }) => {
  await page.goto("/");
  const box = await page.getByTestId("panel").boundingBox();
  expect(box?.width).toBe(340);
  expect(box?.height).toBeLessThanOrEqual(780);
});

test("the panel follows the colour scheme of the system", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "light" });
  await page.goto("/");
  const light = await page.getByTestId("panel").evaluate((node) => getComputedStyle(node).backgroundColor);
  await page.emulateMedia({ colorScheme: "dark" });
  const dark = await page.getByTestId("panel").evaluate((node) => getComputedStyle(node).backgroundColor);
  expect(light).not.toBe(dark);
});

test("the current session shows the output rate row", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("output-rate")).toContainText("42.3 tok/s");
  await expect(page.getByTestId("current-session")).toContainText("中位 45.1 tok/s");
  await expect(page.getByTestId("current-session")).toContainText("1.24M");
});

test("the account section shows the today and the total tokens", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("account-today")).toHaveText("1.80M");
  await expect(page.getByTestId("account-total")).toHaveText("3.3B");
});

test("the radar counts the sources that are not down", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("source-availability")).toHaveText("3/4 来源可用");
});

test("a normal verdict keeps the evidence collapsed but shows the disclaimer", async ({ page }) => {
  await page.goto("/");
  const health = page.getByTestId("model-health");
  await expect(page.getByTestId("health-verdict")).toHaveText("正常");
  await expect(page.getByTestId("health-disclaimer")).toHaveText("基于本机近 7 天基线，不代表官方结论");
  await expect(page.getByTestId("health-evidence")).toBeHidden();
});

test("an abnormal verdict expands the evidence", async ({ page }) => {
  await page.goto("/?fixture=suspected");
  const health = page.getByTestId("model-health");
  await expect(page.getByTestId("health-verdict")).toHaveText("疑似降智");
  await expect(page.getByTestId("health-disclaimer")).toHaveText("基于本机近 7 天基线，不代表官方结论");
  await expect(page.getByTestId("health-evidence")).toBeVisible();
  await expect(health).toContainText("当前 33.1 / 基线 45.1 tok/s");
});

test("an area in error shows a dash instead of the placeholder number", async ({ page }) => {
  await page.goto("/?fixture=quota-error");
  await expect(page.getByTestId("weekly-quota")).toHaveText("—");
  await expect(page.getByTestId("weekly-quota")).not.toContainText("84%");
  await expect(page.getByTestId("quota")).toContainText("数据不可用");
});

test("an errored session hides its numbers in the session and in the model summary", async ({ page }) => {
  await page.goto("/?fixture=session-error");
  await expect(page.getByTestId("output-rate")).toHaveText("—");
  await expect(page.getByTestId("current-session")).not.toContainText("42.3 tok/s");
  await expect(page.getByTestId("model-health")).not.toContainText("42.3 tok/s");
});

test("a confirmed reset names its confirming sources", async ({ page }) => {
  await page.goto("/");
  const radar = page.getByTestId("reset-radar");
  await expect(radar).toContainText("强信号");
  await expect(radar).toContainText("来源已确认");
  await expect(radar).toContainText("AI 哨兵记录、AI 哨兵信号、Codex Resets");
});

test("a single source is never shown as a confirmation", async ({ page }) => {
  await page.goto("/?fixture=single-source");
  const radar = page.getByTestId("reset-radar");
  await expect(radar).toContainText("单一来源");
  await expect(radar).not.toContainText("来源已确认");
});

test("a service incident is never shown as a reset confirmation", async ({ page }) => {
  await page.goto("/?fixture=incident");
  const radar = page.getByTestId("reset-radar");
  await expect(radar).toContainText("服务故障");
  await expect(radar).not.toContainText("来源已确认");
  await expect(radar).not.toContainText("适用范围");
});

test("an unreachable source is never shown as a reset confirmation", async ({ page }) => {
  await page.goto("/?fixture=degraded-source");
  const radar = page.getByTestId("reset-radar");
  await expect(radar).toContainText("源不可用");
  await expect(radar).not.toContainText("来源已确认");
});
