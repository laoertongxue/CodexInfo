import type { Host } from "./types";
import { McpHost } from "./mcpHost";
import { MockHost } from "./mockHost";
import { NativeHost } from "./nativeHost";

/**
 * Picks the host the page runs with.
 *
 * The native bridge wins: the app runs the panel in its own web view. The
 * MCP host comes next, because it embeds the page in an iframe. Without
 * either of them the page falls back to the mock snapshot.
 */
export function detectHost(): Host {
  if (window.webkit?.messageHandlers?.codexInfo) return new NativeHost();
  if (window.parent !== window) return new McpHost();
  return new MockHost();
}
