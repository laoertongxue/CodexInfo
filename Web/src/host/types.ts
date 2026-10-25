import type { UsageSnapshot } from "../data/types";

/**
 * The bridge between the panel and the world around it.
 *
 * The panel never talks to the network itself: the native bridge and the MCP
 * host both push a snapshot into the page.
 */
export interface HostHandlers {
  onSnapshot: (snapshot: UsageSnapshot) => void;
  onError: (message: string) => void;
}

/**
 * What every host offers the panel.
 *
 * - `native` — the menu bar app; the page posts `ready`, `refresh`, `scan`,
 *   `openURL`, `openSettings` and `close` over the `codexInfo` bridge.
 * - `mcp` — the MCP App; the snapshot comes from the `get_usage_snapshot`
 *   tool, a scan from `scan_reset_sources`, and a link opens through
 *   `openLink`. The host knows no settings window and no close button.
 * - `mock` — the fixtures, for the browser and for the tests.
 */
export interface Host {
  mode: "native" | "mcp" | "mock";
  start(handlers: HostHandlers): Promise<void>;
  stop(): void;
  refresh(): void;
  scan(): Promise<void>;
  openURL(url: string): void;
  openSettings(): void;
  close(): void;
}
