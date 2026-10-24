// spikes/mcp-app/server.mjs
import readline from "node:readline";

const HTML = `<!doctype html><html><body style="font:14px -apple-system;padding:24px">
<h2>CodexInfo MCP App OK</h2><p>If you can read this inside Codex, the host renders MCP Apps.</p>
</body></html>`;

function send(value) {
  process.stdout.write(JSON.stringify(value) + "\n");
}
function ok(id, result) { send({ jsonrpc: "2.0", id, result }); }
function fail(id, code, message) { send({ jsonrpc: "2.0", id, error: { code, message } }); }

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  let request;
  try { request = JSON.parse(line); } catch { return; }
  const { id, method, params } = request;
  if (method === "initialize") {
    return ok(id, {
      protocolVersion: "2025-06-18",
      capabilities: { tools: {}, resources: {} },
      serverInfo: { name: "codexinfo-spike", version: "0.0.1" },
    });
  }
  if (method === "notifications/initialized") return;
  if (method === "ping") return ok(id, {});
  if (method === "tools/list") {
    return ok(id, {
      tools: [{
        name: "show_spike_panel",
        description: "Render the CodexInfo MCP App spike panel.",
        inputSchema: { type: "object", properties: {}, additionalProperties: false },
        _meta: {
          ui: { resourceUri: "ui://codexinfo-spike/panel.html" },
          "ui/resourceUri": "ui://codexinfo-spike/panel.html",
          "openai/outputTemplate": "ui://codexinfo-spike/panel.html",
        },
      }],
    });
  }
  if (method === "tools/call") {
    if (params?.name !== "show_spike_panel") return fail(id, -32602, "unknown tool");
    return ok(id, { content: [{ type: "text", text: "CodexInfo spike panel" }], structuredContent: { ok: true } });
  }
  if (method === "resources/list") {
    return ok(id, {
      resources: [{
        uri: "ui://codexinfo-spike/panel.html",
        name: "CodexInfo spike panel",
        mimeType: "text/html;profile=mcp-app",
      }],
    });
  }
  if (method === "resources/read") {
    if (params?.uri !== "ui://codexinfo-spike/panel.html") return fail(id, -32602, "unknown resource");
    return ok(id, { contents: [{ uri: params.uri, mimeType: "text/html;profile=mcp-app", text: HTML }] });
  }
  return fail(id, -32601, `unknown method ${method}`);
});
