import type { UsageSnapshot } from "./types";

/**
 * The mock snapshot of the panel.
 *
 * The document is imported instead of fetched, so the page keeps its strict
 * CSP (`connect-src 'none'`): the panel never talks to the network itself.
 */
export const mockSnapshot: UsageSnapshot = {
  "generatedAt": "2026-10-24T14:20:39+08:00",
  "freshness": { "quota": "fresh", "session": "fresh", "account": "fresh", "sources": "fresh", "resetCredits": "fresh" },
  "quota": { "planType": "pro", "weeklyRemainingPercent": 84, "weeklyResetsAt": "2026-10-26T11:03:00+08:00", "source": "official", "fetchedAt": "2026-10-24T14:20:39+08:00" },
  "resetCredits": { "availableCount": 1, "reportedAvailableCount": 1, "items": [{ "idSuffix": "123456", "status": "available", "grantedAt": null, "expiresAt": "2026-11-07T07:55:00+08:00", "title": "Full reset" }], "fetchedAt": "2026-10-24T14:20:39+08:00" },
  "session": { "isActive": true, "label": "当前会话", "model": "gpt-6.1-sol", "effort": "xhigh", "serviceTier": "default", "contextTokens": 147000, "contextWindow": 475000, "totalTokens": 1240000, "inputTokens": 1180000, "outputTokens": 58300, "cachedInputTokens": 1020000, "reasoningOutputTokens": 7000, "outputTokensPerSecond": 42.3, "medianOutputTokensPerSecond": 45.1, "ttftMs": 3900, "turnCount": 12, "routeMismatch": false },
  "account": { "todayTokens": 1800000, "totalTokens": 3300000000, "source": "official+local", "updatedAt": "2026-10-24T14:20:39+08:00" },
  "health": { "status": "normal", "baselineWindowDays": 7, "sampleTurns": 12, "model": "gpt-6.1-sol", "effort": "xhigh", "signals": [{ "id": "outputRate", "label": "输出速率", "current": 42.3, "baseline": 45.1, "flagged": false, "detail": "当前 42.3 / 基线 45.1 tok/s" }], "disclaimer": "基于本机近 7 天基线，不代表官方结论" },
  "resetRadar": { "sources": [{ "sourceId": "ai-sentinel-records", "sourceName": "AI 哨兵记录", "state": "ok", "lastSuccessAt": "2026-10-24T14:20:51+08:00", "lastError": null, "nextScanAt": "2026-10-24T14:21:51+08:00" }, { "sourceId": "ai-sentinel-signals", "sourceName": "AI 哨兵信号", "state": "ok", "lastSuccessAt": "2026-10-24T14:20:51+08:00", "lastError": null, "nextScanAt": "2026-10-24T14:21:51+08:00" }, { "sourceId": "codex-resets", "sourceName": "Codex Resets", "state": "ok", "lastSuccessAt": "2026-10-24T14:20:51+08:00", "lastError": null, "nextScanAt": "2026-10-24T14:21:51+08:00" }, { "sourceId": "openai-status", "sourceName": "官方状态", "state": "down", "lastSuccessAt": null, "lastError": "timeout", "nextScanAt": "2026-10-24T14:21:51+08:00" }], "latestConfirmed": { "id": "reset:1", "sourceId": "ai-sentinel-records", "sourceName": "AI 哨兵记录", "kind": "reset", "severity": "strong", "title": "第 13 天额度重置完成", "summary": "覆盖所有付费用户", "publishedAt": "2026-10-18T05:12:00+08:00", "url": "https://codex-reset.com/zh/radar", "verified": true, "scope": "所有付费用户", "confirmingSources": ["AI 哨兵记录", "AI 哨兵信号", "Codex Resets"] }, "recent": [], "lastScanAt": "2026-10-24T14:20:51+08:00", "nextScanAt": "2026-10-24T14:21:51+08:00" }
};

/**
 * The quota area failed.
 *
 * The payload still carries the numbers of the last successful read, so the
 * panel has to show a dash instead of a value that looks real.
 */
export const mockQuotaErrorSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  freshness: { ...mockSnapshot.freshness, quota: "error" },
  quota: {
    planType: null,
    weeklyRemainingPercent: 84,
    weeklyResetsAt: "2026-10-26T11:03:00+08:00",
    source: "official",
    fetchedAt: "2026-10-24T14:20:39+08:00",
  },
};

/**
 * The session area failed.
 *
 * The payload still carries the numbers of the last session, so neither the
 * session section nor the model summary may show them.
 */
export const mockSessionErrorSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  freshness: { ...mockSnapshot.freshness, session: "error" },
  session: {
    ...mockSnapshot.session,
    isActive: false,
    label: "最近会话",
    model: null,
    effort: null,
    turnCount: 0,
  },
};

/** The local verdict is "suspected", so the evidence is expanded. */
export const mockSuspectedSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  health: {
    ...mockSnapshot.health,
    status: "suspected",
    signals: [
      { id: "outputRate", label: "输出速率", current: 33.1, baseline: 45.1, flagged: true, detail: "当前 33.1 / 基线 45.1 tok/s" },
      { id: "ttft", label: "首 token", current: 8100, baseline: 3900, flagged: true, detail: "当前 8100 / 基线 3900 ms" },
    ],
  },
};

/** The newest signal is a service incident, never a reset confirmation. */
export const mockIncidentSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  resetRadar: {
    ...mockSnapshot.resetRadar,
    latestConfirmed: {
      id: "status:1",
      sourceId: "openai-status",
      sourceName: "官方状态",
      kind: "status",
      severity: "incident",
      title: "ChatGPT 服务部分中断",
      summary: "部分用户报告响应变慢",
      publishedAt: "2026-10-24T13:40:00+08:00",
      url: "https://status.openai.com/",
      verified: false,
      scope: null,
      confirmingSources: ["官方状态"],
    },
  },
};

/** The source that carries the newest signal was not reachable. */
export const mockDegradedSourceSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  resetRadar: {
    ...mockSnapshot.resetRadar,
    latestConfirmed: {
      id: "reset:2",
      sourceId: "codex-resets",
      sourceName: "Codex Resets",
      kind: "reset",
      severity: "degraded",
      title: "重置记录待确认",
      summary: "来源暂不可用",
      publishedAt: "2026-10-24T13:10:00+08:00",
      url: "https://codex-reset.com/",
      verified: false,
      scope: null,
      confirmingSources: ["Codex Resets"],
    },
  },
};

/** Only one reset source carries the newest record. */
export const mockSingleSourceSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  resetRadar: {
    ...mockSnapshot.resetRadar,
    latestConfirmed: {
      ...mockSnapshot.resetRadar.latestConfirmed!,
      confirmingSources: ["AI 哨兵记录"],
    },
  },
};

/**
 * The login of the official read expired.
 *
 * The session fallback still provides the weekly quota, so the panel shows
 * the quota and the re-login hint at the same time.
 */
export const mockLoginExpiredSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  quota: { ...mockSnapshot.quota, authExpired: true },
};

/**
 * The reset cards could not be read.
 *
 * The payload still carries the cards of the last successful read, so the
 * panel has to show a dash instead of a card list that looks real.
 */
export const mockCreditsErrorSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  freshness: { ...mockSnapshot.freshness, resetCredits: "error" },
};

/**
 * A strong severity without the source's own confirmation.
 *
 * The tone of a signal needs all three conditions, so this record must not
 * be shown as a strong signal.
 */
export const mockStrongUnverifiedSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  resetRadar: {
    ...mockSnapshot.resetRadar,
    latestConfirmed: {
      ...mockSnapshot.resetRadar.latestConfirmed!,
      verified: false,
    },
  },
};

/**
 * A group whose second confirming source is the official status.
 *
 * The official status never confirms a reset, so the group stays a single
 * source.
 */
export const mockStatusConfirmingSnapshot: UsageSnapshot = {
  ...mockSnapshot,
  resetRadar: {
    ...mockSnapshot.resetRadar,
    latestConfirmed: {
      ...mockSnapshot.resetRadar.latestConfirmed!,
      confirmingSources: ["AI 哨兵记录", "官方状态"],
    },
  },
};

/** Every fixture the mock host can serve, keyed by the `fixture` query. */
export const mockSnapshots: Record<string, UsageSnapshot> = {
  default: mockSnapshot,
  "quota-error": mockQuotaErrorSnapshot,
  "session-error": mockSessionErrorSnapshot,
  suspected: mockSuspectedSnapshot,
  incident: mockIncidentSnapshot,
  "degraded-source": mockDegradedSourceSnapshot,
  "single-source": mockSingleSourceSnapshot,
  "credits-error": mockCreditsErrorSnapshot,
  "login-expired": mockLoginExpiredSnapshot,
  "strong-unverified": mockStrongUnverifiedSnapshot,
  "status-confirming": mockStatusConfirmingSnapshot,
};
