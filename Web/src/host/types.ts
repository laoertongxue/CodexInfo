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

export interface Host {
  mode: "native" | "mcp" | "mock";
  start(handlers: HostHandlers): Promise<void>;
  stop(): void;
  refresh(): void;
  scan(): void;
  openURL(url: string): void;
  openSettings(): void;
  close(): void;
}
