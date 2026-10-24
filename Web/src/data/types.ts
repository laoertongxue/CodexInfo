/**
 * The shape of the snapshot the Swift data layer emits.
 *
 * The snapshot is the single source of truth: the panel, the menu bar and the
 * MCP server all read the same document, so every area carries its own
 * freshness state next to the values themselves.
 */

export type DataState = "fresh" | "stale" | "loading" | "error";
export type HealthStatus = "normal" | "suspected" | "degraded" | "insufficient";
export type SourceState = "ok" | "degraded" | "down";

/** The areas that carry their own freshness state. */
export interface Freshness {
  quota: DataState;
  session: DataState;
  account: DataState;
  sources: DataState;
  /** The reset cards; older payloads may omit it. */
  resetCredits?: DataState;
}

export interface HealthSignal {
  id: string;
  label: string;
  current: number;
  baseline: number;
  flagged: boolean;
  detail: string;
}

export interface ResetSignal {
  id: string;
  sourceId: string;
  sourceName: string;
  kind: string;
  severity?: string | null;
  title: string;
  summary: string;
  publishedAt?: string | null;
  url?: string | null;
  verified: boolean;
  scope?: string | null;
  confirmingSources: string[];
}

export interface UsageSnapshot {
  generatedAt: string;
  freshness: Freshness;
  quota: {
    /** The official read failed because the login expired. */
    authExpired?: boolean;
    planType?: string | null;
    weeklyRemainingPercent?: number | null;
    weeklyResetsAt?: string | null;
    source: string;
    fetchedAt: string;
  };
  resetCredits: {
    availableCount: number;
    reportedAvailableCount?: number | null;
    items: Array<{ idSuffix: string; status: string; grantedAt?: string | null; expiresAt?: string | null; title?: string | null }>;
    fetchedAt: string;
  };
  session: {
    isActive: boolean;
    label: string;
    model?: string | null;
    effort?: string | null;
    serviceTier?: string | null;
    contextTokens?: number | null;
    contextWindow?: number | null;
    totalTokens?: number | null;
    inputTokens?: number | null;
    outputTokens?: number | null;
    cachedInputTokens?: number | null;
    reasoningOutputTokens?: number | null;
    outputTokensPerSecond?: number | null;
    medianOutputTokensPerSecond?: number | null;
    ttftMs?: number | null;
    turnCount: number;
    routeMismatch: boolean;
  };
  account: {
    todayTokens?: number | null;
    totalTokens?: number | null;
    source: string;
    updatedAt: string;
  };
  health: {
    status: HealthStatus;
    baselineWindowDays: number;
    sampleTurns: number;
    model?: string | null;
    effort?: string | null;
    signals: HealthSignal[];
    disclaimer: string;
  };
  resetRadar: {
    sources: Array<{ sourceId: string; sourceName: string; state: SourceState; lastSuccessAt?: string | null; lastError?: string | null; nextScanAt?: string | null }>;
    latestConfirmed?: ResetSignal | null;
    recent: ResetSignal[];
    lastScanAt?: string | null;
    nextScanAt?: string | null;
  };
}
