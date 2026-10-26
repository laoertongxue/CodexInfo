import { expect, test, type Page } from "@playwright/test";
import { mockSnapshot } from "../src/data/mockSnapshot";
import type { ClientUsageSnapshot } from "../src/data/types";

/** The client panels the native bridge of the test pushes. */
const mockClients: ClientUsageSnapshot[] = [
  {
    client: "qoder",
    name: "Qoder",
    quotaPercent: 50,
    quotaLabel: "额度",
    detail: "剩余 1274 / 2500 积分",
    resetsAt: "2026-11-23T02:52:22.646Z",
    resetLabel: "刷新",
    limits: [
      { id: "plan", label: "套餐内 Credits", usedPoints: 826, totalPoints: 2000, usedPercent: 42, resetAt: "2026-11-23T02:52:22.646Z", resetLabel: "刷新" },
      { id: "addOn", label: "资源包", usedPoints: 400, totalPoints: 500, usedPercent: 80 },
    ],
    source: "本地用量日志",
    updatedAt: "2026-10-25T03:38:00.000Z",
    tone: "normal",
    note: "Qoder 刷新账户用量时更新；数据来自本地日志。",
  },
  {
    client: "miniMaxCode",
    name: "MiniMax",
    quotaPercent: 93,
    quotaLabel: "额度",
    detail: "5 小时窗口 100%",
    resetsAt: "2026-10-26T00:00:00.000Z",
    resetLabel: "重置",
    model: "MiniMax M3.1 Flash",
    effort: "思考",
    source: "官方额度接口",
    updatedAt: "2026-10-25T03:38:00.000Z",
    tone: "normal",
    resetCardTotal: 3,
    limits: [
      { id: "fiveHour", label: "5 小时限额", usedPoints: 0, totalPoints: 100, resetAt: "2026-10-25T12:00:00.000Z" },
      { id: "weekly", label: "周限额", usedPoints: 10, totalPoints: 150, resetAt: "2026-10-26T00:00:00.000Z" },
    ],
    resetCards: [
      { id: "card-1", source: "mcode_signin", label: "完全重置", expiresAt: "2026-10-26T08:00:00.000Z", grantedAt: "2026-10-12T03:38:59.548Z" },
      { id: "card-2", source: "mcode_signin", label: "完全重置", expiresAt: "2026-10-27T08:00:00.000Z", grantedAt: "2026-10-12T18:33:21.814Z" },
      { id: "card-3", source: "mcode_signin", label: "完全重置", expiresAt: "2026-10-28T08:00:00.000Z", grantedAt: "2026-10-13T18:37:28.663Z" },
    ],
  },
  {
    client: "openCode",
    name: "OpenCode",
    quotaPercent: 97,
    quotaLabel: "Go 额度",
    source: "OpenCode Go / Zen",
    updatedAt: "2026-10-25T03:38:00.000Z",
    tone: "normal",
    openCode: {
      goState: "active",
      goWindows: [
        { id: "rolling", label: "5 小时", usedPercent: 3, resetAt: "2026-10-26T08:00:00.000Z" },
        { id: "weekly", label: "周", usedPercent: 2, resetAt: "2026-10-31T00:00:00.000Z" },
        { id: "monthly", label: "月", usedPercent: 1, resetAt: "2026-11-01T00:00:00.000Z" },
      ],
      zenBalance: "$8.29",
      zenState: "signedIn",
      freeModels: [
        "opencode/glm-5.3-flash-free",
        "opencode/deepseek-v4.1-flash-free",
        "opencode/mimo-v2.6-flash-free",
        "opencode/nemotron-3-ultra-free",
        "opencode/space-bunny-free",
      ],
    },
  },
  {
    client: "deepSeekHarness",
    name: "DeepSeek",
    quotaText: "¥41.60",
    quotaLabel: "余额",
    model: "DeepSeek V4 Flash",
    effort: "Max",
    source: "官方钱包",
    updatedAt: "2026-10-25T03:38:00.000Z",
    tone: "normal",
  },
];

/** A message the page posted over the native bridge. */
type BridgeMessage = { type: string; url?: string; height?: number };

/** A JSON-RPC message the MCP host received from the panel. */
type HostCall = { method?: string; params?: { name?: string; url?: string } };

/** The messages the fake native bridge collected. */
function bridgeMessages(page: Page): Promise<BridgeMessage[]> {
  return page.evaluate(() => (window as unknown as { __bridge: BridgeMessage[] }).__bridge);
}

/** The calls the fake MCP host collected. */
function hostCalls(page: Page): Promise<HostCall[]> {
  return page.evaluate(() => (window as unknown as { __calls: HostCall[] }).__calls);
}

test("the native host announces itself and takes the messages of the panel", async ({ page }) => {
  await page.addInitScript(() => {
    const sent: BridgeMessage[] = [];
    (window as unknown as { __bridge: BridgeMessage[] }).__bridge = sent;
    (window as unknown as { webkit: unknown }).webkit = {
      messageHandlers: {
        codexInfo: { postMessage: (message: BridgeMessage) => sent.push(message) },
      },
    };
  });
  await page.goto("/");

  // The app waits for the announcement before it pushes the first snapshot.
  // The height poll may follow it; the first message is still `ready`.
  await page.waitForFunction(() => Boolean(window.CodexInfoHost));
  expect((await bridgeMessages(page))[0]).toEqual({ type: "ready" });

  await page.evaluate((snapshot) => window.CodexInfoHost?.render(snapshot), mockSnapshot);
  await expect(page.getByTestId("weekly-quota")).toContainText("84%");

  await page.getByRole("button", { name: "刷新" }).click();
  await page.getByRole("button", { name: "立即扫描" }).click();
  await page.getByRole("button", { name: "设置" }).click();
  await page.getByRole("button", { name: "关闭" }).click();
  await page.getByRole("button", { name: /查看原始出处/ }).click();

  const messages = await bridgeMessages(page);
  expect(messages).toContainEqual({ type: "refresh" });
  expect(messages).toContainEqual({ type: "scan" });
  expect(messages).toContainEqual({ type: "openSettings" });
  expect(messages).toContainEqual({ type: "close" });
  expect(messages).toContainEqual({ type: "openURL", url: "https://codex-reset.com/zh/radar" });

  await page.evaluate(() => window.CodexInfoHost?.error("快照不可用"));
  await expect(page.getByTestId("panel")).toContainText("快照不可用");
});

test("the native host switches between the client panels", async ({ page }) => {  await page.addInitScript(() => {
    (window as unknown as { webkit: unknown }).webkit = {
      messageHandlers: {
        codexInfo: { postMessage: () => undefined },
      },
    };
  });
  await page.goto("/");
  await page.waitForFunction(() => Boolean(window.CodexInfoHost));
  await page.evaluate((snapshot) => window.CodexInfoHost?.render(snapshot), mockSnapshot);
  await page.evaluate((clients) => window.CodexInfoHost?.renderClients?.(clients), mockClients);
  await expect(page.getByTestId("weekly-quota")).toContainText("84%");

  await page.getByRole("tab", { name: "Qoder" }).click();
  await expect(page.getByTestId("client-limit-plan-value")).toContainText("826 / 2,000");
  await expect(page.getByTestId("client-limit-addOn-value")).toContainText("400 / 500");
  await expect(page.getByTestId("panel")).toContainText("套餐内 Credits");
  await expect(page.getByTestId("panel")).toContainText("资源包");
  await expect(page.getByTestId("panel")).toContainText("已使用 42%");
  await expect(page.getByTestId("panel")).toContainText("剩余 1,174");
  await expect(page.getByTestId("panel")).toContainText("刷新");
  await expect(page.getByTestId("panel")).toContainText("本地用量日志");

  await page.getByRole("tab", { name: "MiniMax" }).click();
  await expect(page.getByTestId("client-limit-fiveHour-value")).toContainText("0 / 100");
  await expect(page.getByTestId("client-limit-weekly-value")).toContainText("10 / 150");
  await expect(page.getByTestId("panel")).toContainText("5 小时限额");
  await expect(page.getByTestId("panel")).toContainText("周限额");
  await expect(page.getByTestId("client-model")).toContainText("MiniMax M3.1 Flash · 思考");
  await expect(page.getByTestId("client-reset-card-count")).toContainText("3 张");
  await expect(page.getByTestId("panel")).toContainText("完全重置");

  await page.getByRole("tab", { name: "OpenCode" }).click();
  await expect(page.getByTestId("opencode-go-state")).toHaveText("可用");
  await expect(page.getByTestId("opencode-window-rolling")).toContainText("已用 3%");
  await expect(page.getByTestId("opencode-window-weekly")).toContainText("已用 2%");
  await expect(page.getByTestId("opencode-window-monthly")).toContainText("已用 1%");
  await expect(page.getByTestId("opencode-zen-balance")).toHaveText("$8.29");
  await expect(page.getByTestId("opencode-free-count")).toHaveText("5 个");
  await expect(page.getByTestId("panel")).toContainText("glm-5.3-flash-free");

  await page.getByRole("tab", { name: "DeepSeek" }).click();
  await expect(page.getByTestId("client-quota")).toContainText("¥41.60");
  await expect(page.getByTestId("client-model")).toContainText("DeepSeek V4 Flash · Max");

  await page.getByRole("tab", { name: "Codex" }).click();
  await expect(page.getByTestId("weekly-quota")).toContainText("84%");
});

test("the native host reports the panel height after a tab switch", async ({ page }) => {
  await page.addInitScript(() => {
    const sent: BridgeMessage[] = [];
    (window as unknown as { __bridge: BridgeMessage[] }).__bridge = sent;
    (window as unknown as { webkit: unknown }).webkit = {
      messageHandlers: {
        codexInfo: { postMessage: (message: BridgeMessage) => sent.push(message) },
      },
    };
  });
  await page.goto("/");
  await page.waitForFunction(() => Boolean(window.CodexInfoHost));
  await page.evaluate((snapshot) => window.CodexInfoHost?.render(snapshot), mockSnapshot);
  await page.evaluate((clients) => window.CodexInfoHost?.renderClients?.(clients), mockClients);
  await expect
    .poll(async () => (await bridgeMessages(page)).filter((message) => message.type === "height").length)
    .toBeGreaterThan(0);
  const before = (await bridgeMessages(page))
    .filter((message) => message.type === "height")
    .at(-1)?.height;
  await page.getByRole("tab", { name: "Qoder" }).click();
  await expect
    .poll(
      async () =>
        (await bridgeMessages(page))
          .filter((message) => message.type === "height")
          .at(-1)?.height,
      { timeout: 3000 }
    )
    .not.toBe(before);
});

test("the MCP host takes the snapshot from the server tools", async ({ page }) => {
  await page.goto("/");
  const panelURL = page.url();

  // The host page is served from the same origin as the panel, so the iframe
  // is allowed to load it and the two can talk over `postMessage`.
  await page.route(
    (url) => url.pathname === "/mcp-host.html",
    (route) =>
      route.fulfill({
        status: 200,
        contentType: "text/html; charset=utf-8",
        body: mcpHostPage(panelURL),
      })
  );
  await page.goto(panelURL + "mcp-host.html");

  const panel = page.frameLocator("#app");
  await expect(panel.getByTestId("panel")).toBeVisible();
  await expect(panel.getByTestId("weekly-quota")).toContainText("84%");

  const toolCall = (await hostCalls(page)).find((call) => call.method === "tools/call");
  expect(toolCall?.params?.name).toBe("get_usage_snapshot");

  await panel.getByRole("button", { name: "立即扫描" }).click();
  await expect
    .poll(async () =>
      (await hostCalls(page))
        .filter((call) => call.method === "tools/call")
        .map((call) => call.params?.name)
    )
    .toContain("scan_reset_sources");

  await panel.getByRole("button", { name: /查看原始出处/ }).click();
  await expect
    .poll(async () => (await hostCalls(page)).find((call) => call.method === "ui/open-link")?.params?.url)
    .toBe("https://codex-reset.com/zh/radar");
});

/**
 * A host page that runs the panel in an iframe and answers the MCP calls.
 *
 * The host speaks the part of the protocol the panel needs: the handshake,
 * the `tools/call` of the snapshot and the `ui/open-link` of a link.
 */
function mcpHostPage(panelURL: string): string {
  return `<!doctype html>
<html lang="en">
  <head><meta charset="utf-8" /></head>
  <body>
    <iframe id="app" src="${panelURL}" width="400" height="800"></iframe>
    <script>
      const snapshot = ${JSON.stringify(mockSnapshot)};
      const iframe = document.getElementById("app");
      window.__calls = [];
      window.addEventListener("message", (event) => {
        if (event.source !== iframe.contentWindow) return;
        const message = event.data;
        window.__calls.push(message);
        const reply = (result) =>
          iframe.contentWindow.postMessage({ jsonrpc: "2.0", id: message.id, result }, "*");
        if (message.method === "initialize") {
          reply({
            protocolVersion: message.params.protocolVersion,
            capabilities: {},
            serverInfo: { name: "test-host", version: "0.0.1" },
          });
        } else if (message.method === "ui/initialize") {
          reply({
            protocolVersion: message.params.protocolVersion,
            hostInfo: { name: "test-host", version: "0.0.1" },
            hostCapabilities: {},
            hostContext: { theme: "light" },
          });
        } else if (message.method === "tools/call") {
          reply({
            content: [{ type: "text", text: JSON.stringify(snapshot) }],
            structuredContent: snapshot,
          });
        } else if (message.method === "ui/open-link") {
          reply({});
        }
      });
    </script>
  </body>
</html>`;
}
