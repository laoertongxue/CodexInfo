import type { ClientUsageSnapshot, UsageSnapshot } from "../data/types";
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
  private heightTimer?: number;
  private lastHeight = 0;

  async start(handlers: HostHandlers) {
    // The native panel is opaque and fills the popover. The host attribute
    // switches the styles that would otherwise repaint a transparent layer
    // on every scroll.
    document.documentElement.dataset.host = "native";
    window.CodexInfoHost = {
      render: (snapshot: UsageSnapshot) => handlers.onSnapshot(snapshot),
      renderClients: (clients: ClientUsageSnapshot[]) => handlers.onClients(clients),
      selectClient: (client: string) => handlers.onSelectClient?.(client),
      error: (message: string) => handlers.onError(message),
    };
    // The app waits for this announcement before it pushes the first snapshot.
    post("ready");
    this.timer = window.setInterval(() => post("refresh"), 30_000);
    this.observeHeight();
  }

  stop() {
    if (this.timer !== undefined) window.clearInterval(this.timer);
    this.timer = undefined;
    if (this.heightTimer !== undefined) window.clearInterval(this.heightTimer);
    this.heightTimer = undefined;
    delete document.documentElement.dataset.host;
  }

  /**
   * Keeps the popover as tall as the current panel.
   *
   * The panel element is replaced when React switches between the loading
   * shell, the Codex panel and a client panel, so a ResizeObserver on the
   * first node goes stale. A cheap poll of the current node also catches the
   * height change of a tab click, which does not pass through the native
   * render calls.
   */
  private observeHeight() {
    const measure = () => {
      const panel = document.querySelector<HTMLElement>(".panel");
      const height = panel ? Math.ceil(panel.getBoundingClientRect().height) : 0;
      if (height > 0 && Math.abs(height - this.lastHeight) >= 1) {
        this.lastHeight = height;
        post("height", { height });
      }
    };
    measure();
    this.heightTimer = window.setInterval(measure, 250);
  }

  refresh() {
    post("refresh");
  }

  async scan(): Promise<void> {
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
