import { useEffect, useRef, useState } from "react";
import type { UsageSnapshot } from "../data/types";
import { detectHost } from "./detect";
import type { Host } from "./types";

/** Connects the panel to the host that pushes the snapshot into the page. */
export function useHost() {
  const [snapshot, setSnapshot] = useState<UsageSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [mode, setMode] = useState<Host["mode"]>("mock");
  const hostRef = useRef<Host | null>(null);

  useEffect(() => {
    const host = detectHost();
    hostRef.current = host;
    setMode(host.mode);
    host
      .start({
        onSnapshot: setSnapshot,
        onError: setError,
      })
      .catch((reason) => setError(String(reason)));
    return () => host.stop();
  }, []);

  return { snapshot, error, mode, host: hostRef };
}
