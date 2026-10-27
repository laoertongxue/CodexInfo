import { readFileSync } from "node:fs";
import { expect, test } from "@playwright/test";

/** The relative luminance of a `rgb()` colour. */
function luminance(color: string): number {
  const values = color.match(/\d+(\.\d+)?/g)?.map(Number) ?? [0, 0, 0];
  const [r, g, b] = values.slice(0, 3).map((value) => {
    const channel = value / 255;
    return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** The contrast ratio of two `rgb()` colours. */
function contrast(first: string, second: string): number {
  const values = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

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

test("the reset panel states the verdict and this account's next reset in Beijing time", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("reset-empty")).toContainText("暂无重置信息/信号");
  const window = page.getByTestId("quota-reset-window");
  await expect(window).toContainText("本机周额度");
  await expect(window).toContainText("下次重置");
  await expect(window).toContainText("北京时间");
  await expect(page.getByTestId("next-reset-at")).toContainText("北京时间");
  await expect(page.getByTestId("quota")).toContainText("北京时间");
});

test("an old completed reset is not shown as a current signal", async ({ page }) => {
  await page.goto("/?fixture=single-source-reset");
  await expect(page.getByTestId("reset-empty")).toContainText("暂无重置信息/信号");
  await expect(page.getByTestId("reset-radar")).not.toContainText("Day 20 重置完成");
});

test("an active forecast states the Beijing time and its source", async ({ page }) => {
  await page.goto("/?fixture=active-forecast");
  const signal = page.getByTestId("reset-signal");
  await expect(signal).toContainText("有重置信号");
  await expect(signal).toContainText("预计北京时间");
  await expect(signal).toContainText("Day 21：新一轮重置预告");
  await expect(page.getByTestId("reset-signal-source")).toContainText("信源：AI 哨兵信号");
  await expect(page.getByTestId("reset-signal-source")).toContainText("北京时间");
  await expect(signal.getByRole("button", { name: /查看原帖/ })).toBeVisible();
});

test("an expired forecast is not shown as a current signal", async ({ page }) => {
  await page.goto("/?fixture=expired-forecast");
  await expect(page.getByTestId("reset-empty")).toContainText("暂无重置信息/信号");
  await expect(page.getByTestId("reset-radar")).not.toContainText("有重置信号");
});

test("a weekly reset five minutes ago is marked as just reset", async ({ page }) => {
  await page.goto("/?fixture=just-reset");
  await expect(page.getByTestId("just-reset")).toHaveText("刚刚重置");
});

test("a normal verdict keeps the evidence collapsed", async ({ page }) => {
  await page.goto("/");
  const health = page.getByTestId("model-health");
  await expect(page.getByTestId("health-verdict")).toHaveText("正常");
  await expect(page.getByTestId("health-evidence")).toBeHidden();
  await expect(health).not.toContainText("不判断模型能力");
});

test("an abnormal verdict expands the performance evidence", async ({ page }) => {
  await page.goto("/?fixture=suspected");
  const health = page.getByTestId("model-health");
  await expect(page.getByTestId("health-verdict")).toHaveText("性能异常");
  await expect(health).not.toContainText("降智");
  await expect(page.getByTestId("health-evidence")).toBeVisible();
  await expect(health).toContainText("近 5 轮中位 33.1 / 基线 45.1 tok/s");
  await expect(health).not.toContainText("能力未验证");
  await expect(health).not.toContainText("不判断模型能力");
});

test("a route downgrade is shown as route, not as a capability verdict", async ({ page }) => {
  await page.goto("/?fixture=route");
  const health = page.getByTestId("model-health");
  await expect(page.getByTestId("health-verdict")).toHaveText("路由降档");
  await expect(health).not.toContainText("降智");
  await expect(page.getByTestId("health-evidence")).toContainText("实际档位低于选择的档位");
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

test("a service incident is not shown as a reset signal", async ({ page }) => {
  await page.goto("/?fixture=incident");
  const radar = page.getByTestId("reset-radar");
  await expect(page.getByTestId("reset-empty")).toBeVisible();
  await expect(radar).not.toContainText("有重置信号");
  await expect(radar).not.toContainText("来源已确认");
});

test("an unreachable source is not shown as a reset signal", async ({ page }) => {
  await page.goto("/?fixture=degraded-source");
  const radar = page.getByTestId("reset-radar");
  await expect(page.getByTestId("reset-empty")).toBeVisible();
  await expect(radar).not.toContainText("有重置信号");
  await expect(radar).not.toContainText("来源已确认");
});

test("an old single-source reset is not shown as a current signal", async ({ page }) => {
  await page.goto("/?fixture=single-source");
  const radar = page.getByTestId("reset-radar");
  await expect(page.getByTestId("reset-empty")).toBeVisible();
  await expect(radar).not.toContainText("有重置信号");
  await expect(radar).not.toContainText("来源已确认");
});

test("a strong severity without confirmation is not a reset signal", async ({ page }) => {
  await page.goto("/?fixture=strong-unverified");
  await expect(page.getByTestId("reset-empty")).toBeVisible();
  await expect(page.getByText("强信号")).toHaveCount(0);
});

test("the official status source never confirms a reset", async ({ page }) => {
  await page.goto("/?fixture=status-confirming");
  const radar = page.getByTestId("reset-radar");
  await expect(page.getByTestId("reset-empty")).toBeVisible();
  await expect(radar).not.toContainText("来源已确认");
});

test("the reset cards show a dash when the area has no data", async ({ page }) => {
  await page.goto("/?fixture=credits-error");
  await expect(page.getByTestId("reset-credit-count")).toHaveText("—");
  await expect(page.getByTestId("reset-credit")).toContainText("重置卡数据不可用");
});

test("the muted text keeps a readable contrast in both schemes", async ({ page }) => {
  for (const scheme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: scheme });
    await page.goto("/");
    await page.getByTestId("panel").waitFor();
    const colors = await page.evaluate(() => {
      const panel = getComputedStyle(document.querySelector("[data-testid='panel']")!);
      const muted = getComputedStyle(document.querySelector(".muted")!);
      return { background: panel.backgroundColor, foreground: muted.color };
    });
    expect(contrast(colors.foreground, colors.background)).toBeGreaterThanOrEqual(4.5);
  }
});

test("the built artifact carries no external reference", () => {
  const html = readFileSync(new URL("../dist/index.html", import.meta.url), "utf8");
  expect(html).not.toMatch(/<script[^>]+src=/);
  expect(html).not.toMatch(/<link[^>]+rel="stylesheet"/);
  expect(html).toContain("Content-Security-Policy");
});

test("an expired login asks the user to sign in again", async ({ page }) => {
  await page.goto("/?fixture=login-expired");
  await expect(page.getByTestId("login-hint")).toContainText("登录已失效");
  await expect(page.getByTestId("weekly-quota")).toContainText("84%");
});

test("a scan shows a running state and then its result", async ({ page }) => {
  await page.goto("/");
  const button = page.getByTestId("scan-button");
  await expect(button).toHaveText("立即扫描");
  await button.click();
  await expect(button).toHaveText("扫描中…");
  await expect(page.getByTestId("scan-status")).toContainText("扫描完成");
});

test("the panel leaves no empty space below its content", async ({ page }) => {
  await page.goto("/");
  await page.getByTestId("panel").waitFor();
  const gap = await page.evaluate(() => {
    const root = document.getElementById("root")!.getBoundingClientRect().height;
    const panel = document.querySelector("[data-testid='panel']")!.getBoundingClientRect().height;
    return root - panel;
  });
  expect(gap).toBeLessThan(4);
});
