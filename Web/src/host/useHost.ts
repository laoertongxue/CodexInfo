import { useEffect, useRef, useState } from "react";
import type { ClientUsageSnapshot, UsageSnapshot } from "../data/types";
import { detectHost } from "./detect";
import type { Host } from "./types";

/** Connects the panel to the host that pushes the snapshot into the page. */
export function useHost() {
  const [snapshot, setSnapshot] = useState<UsageSnapshot | null>(null);
  const [clients, setClients] = useState<ClientUsageSnapshot[]>([]);
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
        onClients: setClients,
        onError: setError,
      })
      .catch((reason) => setError(String(reason)));
    return () => host.stop();
  }, []);

  return { snapshot, clients, error, mode, host: hostRef };
}
