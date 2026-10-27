import { App, PostMessageTransport } from "@modelcontextprotocol/ext-apps";
import type { UsageSnapshot } from "../data/types";
import type { Host, HostHandlers } from "./types";

/** The shape of the tool result the panel reads. */
type ToolResult = {
  structuredContent?: unknown;
  content?: Array<{ type: string; text?: string }>;
};

/**
 * Whether the payload carries the sections the panel shows.
 *
 * A payload of another shape would break the panel, so it is refused here
 * and reported as an error instead.
 */
function isSnapshot(value: unknown): value is UsageSnapshot {
  if (!value || typeof value !== "object") return false;
  const sections = ["freshness", "quota", "session", "account", "health", "resetRadar"];
  return sections.every((section) => section in value);
}

/**
 * The snapshot out of a tool result.
 *
 * The server answers with `structuredContent`; a host that drops it still
 * carries the JSON in the text of the first text content.
 */
function parseSnapshot(result: unknown): UsageSnapshot | null {
  if (!result || typeof result !== "object") return null;
  const candidate = result as ToolResult;
  if (candidate.structuredContent && typeof candidate.structuredContent === "object") {
    return isSnapshot(candidate.structuredContent) ? candidate.structuredContent : null;
  }
  const text = candidate.content?.find((item) => item.type === "text")?.text;
  if (!text) return null;
  try {
    const parsed: unknown = JSON.parse(text);
    return isSnapshot(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * The host the MCP App runs in.
 *
 * The page lives in an iframe of the host, so the snapshot comes from the
 * server tools `get_usage_snapshot` and `scan_reset_sources` instead of a
 * bridge. The host knows no settings window and no close button, so those
 * two actions do nothing here.
 */
export class McpHost implements Host {
  mode = "mcp" as const;
  private app = new App({ name: "AI-UseInfo", version: "0.1.7" }, {});
  private handlers?: HostHandlers;
  private timer?: number;

  async start(handlers: HostHandlers) {
    this.handlers = handlers;
    try {
      await this.app.connect(new PostMessageTransport(window.parent, window.parent));
    } catch (reason) {
      // A panel that mounts again finds the transport of the first mount;
      // that one still talks to the host.
      if (!String(reason).includes("already connected")) throw reason;
    }
    await this.refresh();
    this.timer = window.setInterval(() => void this.refresh(), 30_000);
  }

  stop() {
    if (this.timer !== undefined) window.clearInterval(this.timer);
    this.timer = undefined;
    this.handlers = undefined;
  }

  async refresh() {
    try {
      const result = await this.app.callServerTool({
        name: "get_usage_snapshot",
        arguments: { refresh: false },
      });
      const snapshot = parseSnapshot(result);
      if (snapshot) this.handlers?.onSnapshot(snapshot);
      else this.handlers?.onError("快照格式无效");
    } catch (reason) {
      this.handlers?.onError(String(reason));
    }
  }

  async scan(): Promise<void> {
    try {
      await this.app.callServerTool({ name: "scan_reset_sources", arguments: {} });
    } catch {
      // A failed scan still leaves the previous snapshot on the screen.
    }
    await this.refresh();
  }

  openURL(url: string) {
    void this.app.openLink({ url }).catch(() => undefined);
  }

  openSettings() {}

  close() {}
}
