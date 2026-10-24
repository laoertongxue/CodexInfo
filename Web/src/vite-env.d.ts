/// <reference types="vite/client" />

/**
 * The shapes the hosts add to the window.
 *
 * The native bridge lives on `window.webkit.messageHandlers.codexInfo` and
 * pushes the snapshot into the page through `window.CodexInfoHost`.
 */
interface Window {
  webkit?: { messageHandlers?: { codexInfo?: { postMessage: (message: unknown) => void } } };
  CodexInfoHost?: {
    render: (snapshot: import("./data/types").UsageSnapshot) => void;
    error: (message: string) => void;
  };
}
