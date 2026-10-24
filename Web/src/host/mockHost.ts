import { mockSnapshots } from "../data/mockSnapshot";
import type { Host, HostHandlers } from "./types";

/**
 * The fixture the URL asks for.
 *
 * The query only selects an imported document, so the page still never
 * performs a request.
 */
function selectedSnapshot() {
  const name = new URLSearchParams(window.location.search).get("fixture") ?? "default";
  return mockSnapshots[name] ?? mockSnapshots.default;
}

/** The host that serves the mock snapshot while the app has no bridge. */
export class MockHost implements Host {
  mode = "mock" as const;
  private handlers?: HostHandlers;

  async start(handlers: HostHandlers) {
    this.handlers = handlers;
    handlers.onSnapshot(selectedSnapshot());
  }

  stop() {
    this.handlers = undefined;
  }

  refresh() {
    this.handlers?.onSnapshot(selectedSnapshot());
  }

  scan() {}

  openURL(url: string) {
    window.open(url, "_blank", "noopener,noreferrer");
  }

  openSettings() {}

  close() {}
}
