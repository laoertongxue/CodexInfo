import type { Host } from "./types";
import { MockHost } from "./mockHost";

/**
 * Picks the host the page runs with.
 *
 * The native bridge and the MCP host join here; until they exist the panel
 * renders the mock snapshot.
 */
export function detectHost(): Host {
  return new MockHost();
}
