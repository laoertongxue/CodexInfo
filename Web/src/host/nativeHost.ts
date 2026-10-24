import type { UsageSnapshot } from "../data/types";
import type { Host, HostHandlers } from "./types";

/**
 * Sends a message to the app over the native bridge.
 *
 * The Swift side registers a script message handler named `codexInfo`; every
 * message is a `{ type, ...payload }` object.
 */
function post(type: string, payload: Record<string, unknown> = {}) {
  window.webkit?.messageHandlers?.codexInfo?.postMessage({ type, ...payload });
}

/**
 * The host the menu bar app runs the panel in.
 *
 * The app pushes the snapshot into the page through `window.CodexInfoHost`
 * and the page asks for work with the same channel: `ready`, `refresh`,
 * `scan`, `openURL`, `openSettings` and `close`.
 */
export class NativeHost implements Host {
  mode = "native" as const;
  private timer?: number;

  async start(handlers: HostHandlers) {
    window.CodexInfoHost = {
      render: (snapshot: UsageSnapshot) => handlers.onSnapshot(snapshot),
      error: (message: string) => handlers.onError(message),
    };
    // The app waits for this announcement before it pushes the first snapshot.
    post("ready");
    this.timer = window.setInterval(() => post("refresh"), 30_000);
  }

  stop() {
    if (this.timer !== undefined) window.clearInterval(this.timer);
    this.timer = undefined;
  }

  refresh() {
    post("refresh");
  }

  scan() {
    post("scan");
  }

  openURL(url: string) {
    post("openURL", { url });
  }

  openSettings() {
    post("openSettings");
  }

  close() {
    post("close");
  }
}
