import { expect, test, type Page } from "@playwright/test";
import { mockSnapshot } from "../src/data/mockSnapshot";

/** A message the page posted over the native bridge. */
type BridgeMessage = { type: string; url?: string };

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
  await page.waitForFunction(() => Boolean(window.CodexInfoHost));
  expect(await bridgeMessages(page)).toEqual([{ type: "ready" }]);

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
