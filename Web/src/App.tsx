import { useEffect, useState, type ReactNode, type RefObject } from "react";
import { DASH, formatBeijingDateTime, formatDateTime, formatRate, formatRemaining, formatTokens } from "./format";
import { useHost } from "./host/useHost";
import type { ClientUsageSnapshot, DataState, HealthStatus, OpenCodeUsage, ResetSignal, SourceState, UsageSnapshot } from "./data/types";
import type { Host } from "./host/types";

/** The local performance verdicts of the model health. */
const HEALTH_LABEL: Record<HealthStatus, string> = {
  normal: "正常",
  suspected: "性能异常",
  degraded: "性能异常（多项）",
  route: "路由降档",
  insufficient: "数据不足",
};

/** The health of a reset source. */
const SOURCE_LABEL: Record<SourceState, string> = {
  ok: "可用",
  degraded: "降级",
  down: "不可用",
};

/** Whether the area carries a value that may be shown. */
function usable(state: DataState): boolean {
  return state !== "error" && state !== "loading";
}

/** The hint of an area whose data is old or missing. */
function freshnessHint(state: DataState): string | null {
  switch (state) {
    case "stale":
      return "数据可能过期";
    case "loading":
      return "载入中";
    case "error":
      return "数据不可用";
    default:
      return null;
  }
}

function Section({ id, children }: { id: string; children: ReactNode }) {
  return (
    <section data-section={id} data-testid={id}>
      {children}
    </section>
  );
}

function FreshnessHint({ state }: { state: DataState }) {
  const hint = freshnessHint(state);
  if (!hint) return null;
  return <span className="tag">{hint}</span>;
}

/** The clients of the switcher, in the order of the tabs. */
const CLIENT_TABS = [
  { client: "codex", name: "Codex" },
  { client: "qoder", name: "Qoder" },
  { client: "miniMaxCode", name: "MiniMax" },
  { client: "openCode", name: "OpenCode" },
  { client: "deepSeekHarness", name: "DeepSeek" },
] as const;

/** The header of both the Codex panel and a client panel. */
function Header({
  title,
  plan,
  mode,
  host,
}: {
  title: string;
  plan?: string | null;
  mode: Host["mode"];
  host: RefObject<Host | null>;
}) {
  return (
    <header className="header">
      <strong className="title">{title}</strong>
      {plan != null && (
        <span className="badge" data-testid="plan-badge">
          {plan}
        </span>
      )}
      <button className="ghost" onClick={() => host.current?.refresh()}>
        刷新
      </button>
      <button className="ghost" onClick={() => host.current?.openSettings()} aria-label="设置">
        设置
      </button>
      {mode !== "mcp" && (
        <button className="close" onClick={() => host.current?.close()} aria-label="关闭">
          ×
        </button>
      )}
    </header>
  );
}

/** The client switcher; only the native app owns the other clients' data. */
function ClientTabs({
  mode,
  selected,
  onSelect,
}: {
  mode: Host["mode"];
  selected: string;
  onSelect: (client: string) => void;
}) {
  if (mode !== "native") return null;
  return (
    <div className="clients" role="tablist" aria-label="客户端">
      {CLIENT_TABS.map((tab) => (
        <button
          key={tab.client}
          role="tab"
          aria-selected={selected === tab.client}
          className={selected === tab.client ? "active" : ""}
          onClick={() => onSelect(tab.client)}
        >
          {tab.name}
        </button>
      ))}
    </div>
  );
}

/** The OpenCode Go windows, Zen balance and free models. */
function OpenCodeSections({ usage, now }: { usage: OpenCodeUsage; now: number }) {
  const goWindows = usage.goWindows ?? [];
  const goLabel =
    usage.goState === "active" ? "可用" : usage.goState === "expired" ? "Key 过期" : "未登录";
  return (
    <>
      <Section id="opencode-go">
        <div className="row">
          <strong>OpenCode Go</strong>
          <span className={`tag ${usage.goState === "active" ? "green" : "orange"}`} data-testid="opencode-go-state">
            {goLabel}
          </span>
        </div>
        {goWindows.map((window) => {
          const tone =
            window.usedPercent >= 90
              ? "quota-critical"
              : window.usedPercent >= 70
                ? "quota-low"
                : "";
          return (
            <div key={window.id} data-testid={`opencode-window-${window.id}`}>
              <div className="row tiny">
                <span>{window.label}</span>
                <span className={tone}>已用 {window.usedPercent}%</span>
              </div>
              <div className="bar">
                <i style={{ width: `${Math.min(100, window.usedPercent)}%` }} />
              </div>
              <div className="row tiny muted">
                <span />
                <span>
                  {window.resetAt
                    ? `${formatDateTime(window.resetAt)} 重置 · ${formatRemaining(window.resetAt, now)}`
                    : DASH}
                </span>
              </div>
            </div>
          );
        })}
        {usage.goNote ? <div className="tiny muted">{usage.goNote}</div> : null}
      </Section>

      <Section id="opencode-zen">
        <div className="row">
          <strong>Zen 余额</strong>
          <strong data-testid="opencode-zen-balance">
            {usage.zenBalance ?? (usage.zenState === "signedOut" ? "未登录" : "不可用")}
          </strong>
        </div>
      </Section>

      {usage.freeModels && usage.freeModels.length > 0 ? (
        <Section id="opencode-free">
          <div className="row">
            <strong>免费模型</strong>
            <span data-testid="opencode-free-count">{usage.freeModels.length} 个</span>
          </div>
          <div className="tiny muted">
            {usage.freeModels
              .slice(0, 4)
              .map((model) => model.split("/").pop())
              .join("、")}
            {usage.freeModels.length > 4 ? ` 等 ${usage.freeModels.length} 个` : ""}
          </div>
        </Section>
      ) : null}
    </>
  );
}

/** The compact panel of a client that is not Codex. */
function ClientPanel({
  client,
  clientId,
  now,
  host,
  mode,
  selected,
  onSelect,
}: {
  client: ClientUsageSnapshot | null;
  clientId: string;
  now: number;
  host: RefObject<Host | null>;
  mode: Host["mode"];
  selected: string;
  onSelect: (client: string) => void;
}) {
  const tab = CLIENT_TABS.find((item) => item.client === clientId);
  const name = client?.name ?? tab?.name ?? "客户端";
  const quotaValue = client?.quotaPercent != null ? `${client.quotaPercent}%` : client?.quotaText ?? DASH;
  const quotaDisplay = client?.quotaPercent != null ? `剩余 ${client.quotaPercent}%` : client?.quotaText ?? DASH;
  const toneClass =
    client?.tone === "warn" ? "quota-low" : client?.tone === "danger" ? "quota-critical" : "";
  const limits = client?.limits ?? [];
  return (
    <main data-testid="panel" className="panel">
      <Header title={name} mode={mode} host={host} />
      <ClientTabs mode={mode} selected={selected} onSelect={onSelect} />
      <div className="body">
        {client ? (
          <>
            {client.openCode ? (
              <OpenCodeSections usage={client.openCode} now={now} />
            ) : limits.length > 0 ? (
              limits.map((limit) => {
                const usedRatio =
                  limit.usedPercent != null
                    ? limit.usedPercent / 100
                    : limit.totalPoints > 0
                      ? limit.usedPoints / limit.totalPoints
                      : 0;
                const usedPercent = limit.usedPercent ?? Math.round(usedRatio * 100);
                const remaining = Math.max(0, limit.totalPoints - limit.usedPoints);
                const limitTone =
                  usedRatio >= 0.9 ? "quota-critical" : usedRatio >= 0.7 ? "quota-low" : "";
                return (
                  <Section id={`client-limit-${limit.id}`} key={limit.id}>
                    <div className="row">
                      <strong>{limit.label}</strong>
                      <strong data-testid={`client-limit-${limit.id}-value`} className={limitTone}>
                        {limit.usedPoints.toLocaleString("zh-CN")} /{" "}
                        {limit.totalPoints.toLocaleString("zh-CN")}
                      </strong>
                    </div>
                    <div className="bar">
                      <i style={{ width: `${Math.min(100, usedPercent)}%` }} />
                    </div>
                    <div className="row tiny muted">
                      <span>已使用 {usedPercent}%</span>
                      <span>剩余 {remaining.toLocaleString("zh-CN")}</span>
                    </div>
                    {limit.resetAt && (
                      <div className="row tiny muted">
                        <span />
                        <span>
                          {formatDateTime(limit.resetAt)} {limit.resetLabel ?? "重置"} ·{" "}
                          {formatRemaining(limit.resetAt, now)}
                        </span>
                      </div>
                    )}
                  </Section>
                );
              })
            ) : (
              <Section id="client-quota-section">
                <div className="row">
                  <strong>{client.quotaLabel}</strong>
                  <strong data-testid="client-quota" className={toneClass}>
                    {quotaDisplay}
                  </strong>
                </div>
                {client.quotaPercent != null && (
                  <div className="bar">
                    <i style={{ width: `${client.quotaPercent}%` }} />
                  </div>
                )}
                {client.detail && (
                  <div className="row tiny muted">
                    <span />
                    <span>{client.detail}</span>
                  </div>
                )}
                {client.resetsAt && (
                  <div className="row tiny muted">
                    <span />
                    <span>
                      {formatDateTime(client.resetsAt)} {client.resetLabel ?? "重置"} ·{" "}
                      {formatRemaining(client.resetsAt, now)}
                    </span>
                  </div>
                )}
              </Section>
            )}

            {client.client === "miniMaxCode" && (
              <Section id="client-reset-cards">
                <div className="row">
                  <strong>重置卡</strong>
                  <strong data-testid="client-reset-card-count">
                    {client.resetCards
                      ? `${client.resetCardTotal ?? client.resetCards.length} 张`
                      : DASH}
                  </strong>
                </div>
                {client.resetCards == null ? (
                  <div className="tiny muted">重置卡数据暂不可用</div>
                ) : client.resetCards.length === 0 ? (
                  <div className="tiny muted">暂无可用重置卡</div>
                ) : (
                  client.resetCards.map((card, index) => (
                    <div className="row tiny" key={card.id} data-testid="client-reset-card">
                      <span className="muted">
                        第 {index + 1} 张 · {card.label ?? "重置卡"}
                      </span>
                      <span className="right">
                        {card.expiresAt ? `${formatDateTime(card.expiresAt)} 到期` : DASH}
                        {card.expiresAt ? (
                          <>
                            <br />
                            余 {formatRemaining(card.expiresAt, now)}
                          </>
                        ) : null}
                      </span>
                    </div>
                  ))
                )}
                <div className="tiny muted">签到奖励，只读。</div>
              </Section>
            )}

            <Section id="client-output-rate">
              <div className="row">
                <strong>输出速率</strong>
                <span className="tiny muted">
                  近期中位{" "}
                  <strong data-testid="client-output-rate-recent">
                    {client.outputRate && client.outputRate.samples > 0
                      ? formatRate(client.outputRate.median)
                      : DASH}
                  </strong>
                </span>
              </div>
              {client.outputRate && client.outputRate.samples > 0 ? (
                <div className="row tiny muted">
                  <span>最近一次</span>
                  <span data-testid="client-output-rate-latest">
                    {formatRate(client.outputRate.latest)} · {client.outputRate.samples} 个样本
                  </span>
                </div>
              ) : null}
              <div className="tiny muted" data-testid="client-output-rate-note">
                {client.outputRate && client.outputRate.samples > 0
                  ? [
                      client.outputRate.basis,
                      client.outputRate.window,
                      client.outputRate.updatedAt
                        ? `更新于 ${formatDateTime(client.outputRate.updatedAt)}`
                        : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")
                  : client.outputRate?.basis ?? "本地未记录输出耗时"}
              </div>
            </Section>

            {(client.model || client.effort) && (
              <Section id="client-model-section">
                <div className="row">
                  <strong>当前模型</strong>
                  <span data-testid="client-model">
                    {client.model ?? DASH}
                    {client.effort ? ` · ${client.effort}` : ""}
                  </span>
                </div>
              </Section>
            )}

            <Section id="client-source">
              <div className="row tiny muted">
                <span>数据来源</span>
                <span>{client.source}</span>
              </div>
              <div className="row tiny muted">
                <span>更新于</span>
                <span>{formatDateTime(client.updatedAt)}</span>
              </div>
              {client.note && <div className="tiny muted">{client.note}</div>}
            </Section>
          </>
        ) : (
          <Section id="client-loading">
            <div className="tiny muted">正在读取 {name} 的额度…</div>
            <div className="tiny muted">首次读取需要一两秒；数据来自客户端自己的账号与本地日志。</div>
          </Section>
        )}
      </div>
      <footer className="footer">
        {client
          ? `${name} · ${client.quotaLabel} ${quotaValue} · 更新 ${formatDateTime(client.updatedAt)}`
          : `${name} · 数据读取中`}
      </footer>
    </main>
  );
}

export default function App() {
  const { snapshot, clients, error, mode, host } = useHost();
  const [now, setNow] = useState(Date.now());
  const [selected, setSelected] = useState<string>("codex");

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  if (error) return <main data-testid="panel" className="panel error">加载失败：{error}</main>;
  if (!snapshot) return <main data-testid="panel" className="panel loading">加载中…</main>;
  const known = CLIENT_TABS.some((tab) => tab.client === selected);
  const active = mode === "native" && known ? selected : "codex";
  if (active !== "codex") {
    return (
      <ClientPanel
        client={clients.find((item) => item.client === active) ?? null}
        clientId={active}
        now={now}
        host={host}
        mode={mode}
        selected={active}
        onSelect={setSelected}
      />
    );
  }
  return (
    <CodexPanel
      snapshot={snapshot}
      now={now}
      host={host}
      mode={mode}
      selected={active}
      onSelect={setSelected}
    />
  );
}

function CodexPanel({
  snapshot,
  now,
  host,
  mode,
  selected,
  onSelect,
}: {
  snapshot: UsageSnapshot;
  now: number;
  host: RefObject<Host | null>;
  mode: Host["mode"];
  selected: string;
  onSelect: (client: string) => void;
}) {
  const quota = snapshot.quota;
  const credits = snapshot.resetCredits;
  const session = snapshot.session;
  const account = snapshot.account;
  const health = snapshot.health;
  const radar = snapshot.resetRadar;

  const [healthOpen, setHealthOpen] = useState(health.status !== "normal");
  const [sourcesOpen, setSourcesOpen] = useState(false);
  const [scanState, setScanState] = useState<"idle" | "scanning" | "done" | "error">("idle");
  const [scanMessage, setScanMessage] = useState<string | null>(null);

  useEffect(() => {
    if (health.status !== "normal") setHealthOpen(true);
  }, [health.status]);

  // A scan is finished when the next snapshot arrives: the app and the MCP
  // server both publish one after the sources were read.
  useEffect(() => {
    if (scanState !== "scanning") return;
    setScanState("done");
    setScanMessage(`扫描完成 · ${radar.sources.filter((source) => source.state !== "down").length}/${radar.sources.length} 来源可用`);
    const timer = window.setTimeout(() => {
      setScanState("idle");
      setScanMessage(null);
    }, 4000);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [snapshot]);

  const onScan = async () => {
    setScanState("scanning");
    setScanMessage(null);
    try {
      await host.current?.scan();
    } catch {
      setScanState("error");
      setScanMessage("扫描失败，请稍后重试");
      const timer = window.setTimeout(() => {
        setScanState("idle");
        setScanMessage(null);
      }, 4000);
      return () => window.clearTimeout(timer);
    }
  };

  const quotaUsable = usable(snapshot.freshness.quota);
  const sessionUsable = usable(snapshot.freshness.session);
  const accountUsable = usable(snapshot.freshness.account);
  const sourcesUsable = usable(snapshot.freshness.sources);
  // The reset cards carry their own state, so a failed read shows a dash
  // instead of an empty list that looks like a real zero.
  const creditsUsable = usable(snapshot.freshness.resetCredits ?? "fresh");
  const quotaTone =
    !quotaUsable || quota.weeklyRemainingPercent == null
      ? ""
      : quota.weeklyRemainingPercent < 10
        ? "quota-critical"
        : quota.weeklyRemainingPercent < 30
          ? "quota-low"
          : "";

  const contextPercent =
    sessionUsable && session.contextWindow && session.contextTokens
      ? Math.round((session.contextTokens / session.contextWindow) * 100)
      : null;

  // A reset signal is only current when its expected time is still ahead (or
  // just passed) or, without an expected time, it was published recently.
  // Completed records and retired forecasts never occupy the verdict.
  const forecastCandidates = Array.from(
    new Map(
      [radar.latestForecast, ...radar.recent]
        .filter((signal): signal is ResetSignal => signal != null && signal.kind === "verifying")
        .map((signal) => [signal.id, signal])
    ).values()
  ).filter((signal) => {
    if (signal.expectedAt) {
      const expected = new Date(signal.expectedAt).getTime();
      if (!Number.isNaN(expected)) return expected >= now - 30 * 60_000;
    }
    if (!signal.publishedAt) return false;
    const published = new Date(signal.publishedAt).getTime();
    return !Number.isNaN(published) && published >= now - 24 * 3600_000;
  });
  const activeForecast =
    forecastCandidates.sort((lhs, rhs) => {
      const left = new Date(lhs.expectedAt ?? lhs.publishedAt ?? 0).getTime();
      const right = new Date(rhs.expectedAt ?? rhs.publishedAt ?? 0).getTime();
      return right - left;
    })[0] ?? null;
  const weeklyWindowMinutes =
    quota.weeklyWindowMinutes != null && quota.weeklyWindowMinutes > 0
      ? quota.weeklyWindowMinutes
      : 10_080;
  const nextResetValue =
    quotaUsable && quota.weeklyResetsAt ? new Date(quota.weeklyResetsAt).getTime() : Number.NaN;
  const nextResetMs = Number.isNaN(nextResetValue) ? null : nextResetValue;
  const windowStartValue =
    quotaUsable && quota.weeklyWindowStartedAt
      ? new Date(quota.weeklyWindowStartedAt).getTime()
      : Number.NaN;
  // New snapshots carry the window start from the domain. Older payloads
  // fall back to the seven-day window for one release cycle.
  const lastResetMs = !Number.isNaN(windowStartValue)
    ? windowStartValue
    : nextResetMs != null
      ? nextResetMs - weeklyWindowMinutes * 60_000
      : null;
  const sinceLastResetMs = lastResetMs != null ? now - lastResetMs : null;
  const justReset =
    sinceLastResetMs != null && sinceLastResetMs >= 0 && sinceLastResetMs <= 3_600_000;
  const sourcesAvailable = radar.sources.filter((source) => source.state !== "down").length;

  return (
    <main data-testid="panel" className="panel">
      <Header
        title="用量"
        plan={quotaUsable ? (quota.planType ?? DASH) : DASH}
        mode={mode}
        host={host}
      />
      <ClientTabs mode={mode} selected={selected} onSelect={onSelect} />

      <div className="body">
        <Section id="quota">
          <div className="row">
            <span>
              周额度 <FreshnessHint state={snapshot.freshness.quota} />
            </span>
            <strong data-testid="weekly-quota" className={quotaTone}>
              {quotaUsable && quota.weeklyRemainingPercent != null ? `剩余 ${quota.weeklyRemainingPercent}%` : DASH}
            </strong>
          </div>
          <div className="bar">
            <i style={{ width: `${quotaUsable ? (quota.weeklyRemainingPercent ?? 0) : 0}%` }} />
          </div>
          <div className="row tiny muted">
            <span />
            <span>
              {quotaUsable ? `${formatBeijingDateTime(quota.weeklyResetsAt)}（北京时间）重置 · ${formatRemaining(quota.weeklyResetsAt, now)}` : DASH}
            </span>
          </div>
          {quota.authExpired ? (
            <div className="tiny muted" data-testid="login-hint">
              登录已失效，请在 Codex 中重新登录
            </div>
          ) : null}
        </Section>

        <Section id="reset-credit">
          <div className="row">
            <strong>
              重置卡 <FreshnessHint state={snapshot.freshness.resetCredits ?? "fresh"} />
            </strong>
            <strong data-testid="reset-credit-count">{creditsUsable ? `${credits.availableCount} 张` : DASH}</strong>
          </div>
          {!creditsUsable ? (
            <div className="tiny muted">重置卡数据不可用</div>
          ) : credits.items.length === 0 ? (
            <div className="tiny muted">暂无可用重置卡</div>
          ) : (
            credits.items.map((item, index) => {
              const hours = item.expiresAt
                ? (new Date(item.expiresAt).getTime() - now) / 3_600_000
                : null;
              const urgency = hours == null ? "" : hours < 24 ? "card-critical" : hours < 72 ? "card-urgent" : "";
              return (
                <div className="row tiny" key={item.idSuffix}>
                  <span className="muted">
                    第 {index + 1} 张 · {item.status === "available" ? "可用" : item.status}
                  </span>
                  <span className={`right ${urgency}`}>
                    {formatDateTime(item.expiresAt)} 到期
                    <br />
                    余 {formatRemaining(item.expiresAt, now)}
                  </span>
                </div>
              );
            })
          )}
        </Section>

        <Section id="reset-radar">
          <div className="row">
            <strong>
              重置追踪 <FreshnessHint state={snapshot.freshness.sources} />
            </strong>
            <button
              className="ghost"
              data-testid="scan-button"
              disabled={scanState === "scanning"}
              onClick={onScan}
            >
              {scanState === "scanning" ? "扫描中…" : "立即扫描"}
            </button>
          </div>

          {activeForecast ? (
            <div className="quote" data-testid="reset-signal">
              <div className="row tiny">
                <span>
                  <strong>有重置信号</strong>
                  {activeForecast.expectedAt
                    ? ` · 预计北京时间 ${formatBeijingDateTime(activeForecast.expectedAt)}`
                    : " · 信源未给出具体时间"}
                </span>
                <span className="tag">预告</span>
              </div>
              <div className="tiny muted" data-testid="reset-signal-title">
                {activeForecast.title}
              </div>
              <div className="tiny muted" data-testid="reset-signal-source">
                信源：{activeForecast.sourceName} · 发布于{" "}
                {formatBeijingDateTime(activeForecast.publishedAt)}（北京时间）
              </div>
              {activeForecast.url && (
                <button className="link" onClick={() => host.current?.openURL(activeForecast.url!)}>
                  查看原帖 ↗
                </button>
              )}
            </div>
          ) : (
            <div className="quote" data-testid="reset-empty">
              <div className="row tiny">
                <strong>暂无重置信息/信号</strong>
              </div>
            </div>
          )}

          <div className="quote" data-testid="quota-reset-window">
            <div className="row tiny">
              <span className="muted">本机周额度</span>
              {justReset ? (
                <span className="tag tone-strong" data-testid="just-reset">
                  刚刚重置
                </span>
              ) : null}
            </div>
            {nextResetMs != null ? (
              <div className="row tiny">
                <span className="muted">下次重置</span>
                <span data-testid="next-reset-at">
                  {formatBeijingDateTime(nextResetMs)}（北京时间） · 余{" "}
                  {formatRemaining(quota.weeklyResetsAt, now)}
                </span>
              </div>
            ) : (
              <div className="tiny muted">周额度重置时间未提供</div>
            )}
            {justReset && lastResetMs != null ? (
              <div className="row tiny">
                <span className="muted">上次重置</span>
                <span data-testid="last-reset-at">
                  {formatBeijingDateTime(lastResetMs)}（北京时间）
                </span>
              </div>
            ) : null}
          </div>

          <div className="row tiny">
            <span className="muted">60 秒刷新</span>
            <span data-testid="source-availability">
              {sourcesUsable ? `${sourcesAvailable}/${radar.sources.length} 来源可用` : DASH}
            </span>
          </div>
          {scanState === "scanning" || scanMessage ? (
            <div className="tiny muted" data-testid="scan-status">
              {scanState === "scanning" ? "扫描中…" : scanMessage}
            </div>
          ) : null}

          <div className="row tiny muted">
            <span>上次扫描 {sourcesUsable ? formatDateTime(radar.lastScanAt) : DASH}</span>
            <span>下次 {sourcesUsable ? formatDateTime(radar.nextScanAt) : DASH}</span>
          </div>
          <button
            className="link"
            aria-expanded={sourcesOpen}
            aria-controls="radar-sources"
            onClick={() => setSourcesOpen((value) => !value)}
          >
            {sourcesOpen ? "收起" : "来源健康"}
          </button>
          {sourcesOpen && (
            <div className="sources" id="radar-sources" data-testid="radar-sources">
              {radar.sources.map((source) => (
                <div className="row tiny" key={source.sourceId}>
                  <span>{source.sourceName}</span>
                  <span className={source.state === "ok" ? "green" : "orange"}>
                    {SOURCE_LABEL[source.state]}
                    {source.lastError ? ` · ${source.lastError}` : ""}
                  </span>
                </div>
              ))}
              {radar.recent.slice(0, 5).map((signal) => (
                <div className="row tiny" key={signal.id}>
                  <span className="muted">{formatBeijingDateTime(signal.publishedAt)}</span>
                  <span>{signal.title}</span>
                </div>
              ))}
            </div>
          )}
        </Section>

        <Section id="model-health">
          <div className="row">
            <strong>模型状态</strong>
            <button
              className={`pill ${health.status}`}
              data-testid="health-verdict"
              aria-expanded={healthOpen}
              aria-controls="health-evidence"
              onClick={() => setHealthOpen((value) => !value)}
            >
              {HEALTH_LABEL[health.status]}
            </button>
          </div>
          <div className="tiny muted">
            {sessionUsable && session.outputTokensPerSecond != null
              ? `${formatRate(session.outputTokensPerSecond)} · `
              : ""}
            {sessionUsable && session.ttftMs
              ? `首 token ${(session.ttftMs / 1000).toFixed(1)}s · `
              : ""}
            {health.recentTurns ?? 5} 轮近期 / {health.sampleTurns} 轮基线
          </div>
          {healthOpen && health.signals.length > 0 && (
            <div className="evidence" id="health-evidence" data-testid="health-evidence">
              <div className="tiny muted">
                基线：近 {health.baselineWindowDays} 天 · {health.model ?? DASH} · {health.effort ?? DASH}
              </div>
              {health.signals.map((signal) => (
                <div className="row tiny" key={signal.id}>
                  <span className={signal.flagged ? "orange" : "muted"}>{signal.label}</span>
                  <span>{signal.detail}</span>
                </div>
              ))}
            </div>
          )}
        </Section>

        <Section id="current-session">
          <div className="row">
            <strong>{session.label}</strong>
            <span className="tiny muted">
              {sessionUsable ? (session.isActive ? "生成中" : "空闲") : "无数据"}
            </span>
          </div>
          <div className="row tiny">
            <span className="muted">上下文</span>
            <span>
              {contextPercent == null
                ? DASH
                : `${contextPercent}% · ${formatTokens(session.contextTokens)} / ${formatTokens(session.contextWindow)}`}
            </span>
          </div>
          <div className="row tiny">
            <span className="muted">Token 总数</span>
            <span>{sessionUsable ? formatTokens(session.totalTokens) : DASH}</span>
          </div>
          <div className="row tiny">
            <span className="muted">输入 / 输出</span>
            <span>
              {sessionUsable ? `${formatTokens(session.inputTokens)} / ${formatTokens(session.outputTokens)}` : DASH}
            </span>
          </div>
          <div className="row tiny">
            <span className="muted">缓存读取</span>
            <span>{sessionUsable ? formatTokens(session.cachedInputTokens) : DASH}</span>
          </div>
          <div className="row tiny new">
            <span className="muted">输出速率</span>
            <span>
              <strong data-testid="output-rate">{sessionUsable ? formatRate(session.outputTokensPerSecond) : DASH}</strong>{" "}
              <span className="muted">/ 中位 {sessionUsable ? formatRate(session.medianOutputTokensPerSecond) : DASH}</span>
            </span>
          </div>
        </Section>

        <Section id="account-stats">
          <div className="subhead">
            账号统计 <FreshnessHint state={snapshot.freshness.account} />
          </div>
          <div className="row tiny">
            <span className="muted">账号今日 Token</span>
            <span data-testid="account-today">{accountUsable ? formatTokens(account.todayTokens) : DASH}</span>
          </div>
          <div className="row tiny">
            <span className="muted">账号累计 Token</span>
            <span data-testid="account-total">{accountUsable ? formatTokens(account.totalTokens) : DASH}</span>
          </div>
          <div className="tiny muted">
            更新于 {accountUsable ? formatDateTime(account.updatedAt) : DASH} · {accountUsable ? account.source : DASH}
          </div>
        </Section>
      </div>

      <footer className="footer">
        {sessionUsable ? (session.model ?? DASH) : DASH} {sessionUsable ? (session.effort ?? "") : ""} · 额度{" "}
        {quotaUsable && quota.weeklyRemainingPercent != null ? `${quota.weeklyRemainingPercent}%` : DASH} · 更新{" "}
        {formatDateTime(snapshot.generatedAt)}
      </footer>
    </main>
  );
}
