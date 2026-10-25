# SDD ledger — plan: docs/superpowers/plans/2026-10-24-codexinfo-implementation.md

- Worktree: `/Users/laoer/Documents/CodexInfo/.worktrees/codexinfo-implementation`
- Branch: `feature/codexinfo`
- Base commit: `e124e2c`
- Spec: `docs/superpowers/specs/2026-10-24-codexinfo-design.md`
- Baseline tests: none yet; repo contains docs only. The plan's Task 2 creates the `codexinfo-tests` runner, which becomes the baseline gate from that point.

## Preflight scan

| Task | Self-consistency | Shared file / interface |
| --- | --- | --- |
| 1 | Spike server, manifest, marketplace, README steps agree | Feeds Task 19's manifest/protocol shape; external install is manual |
| 2 | Package, runner, HTTP/credential tests agree | Creates `main.swift`/`Package.swift` that Tasks 18–20 extend |
| 3 | Window selector tests match model names | Produces `RateLimitSnapshot` used by Tasks 4/8/9 |
| 4 | Official client tests match endpoint mapping | Produces `QuotaSnapshot`/`QuotaSnapshotProviding` used by Task 15 |
| 5 | Reset-credit tests match sorting/expiry code | Produces `ResetCreditsSnapshot`/provider used by Task 15 |
| 6 | Parser tests match event structs | Produces session events consumed by Tasks 7/9 |
| 7 | Aggregator/rate tests match formulas | Produces `TurnMetrics`/`OutputRateCalculator` used by Tasks 9/11 |
| 8 | Fake transport test matches app-server client | Adds decoder helper; see R1; `SessionQuotaFallback` added Task 9 |
| 9 | Indexer/repository test matches cache and snapshot fields | Produces `SessionSnapshot`; `.empty` added Task 15; consumed Task 18 |
| 10 | Account tests match official/local fallback | Produces `AccountSnapshot` + provider used by Task 15 |
| 11 | Four verdict tests match analyzer thresholds | Produces `HealthSnapshot`; `.empty` consumed Task 15/18 |
| 12 | Source tests match current/status payloads | Produces `ResetSignal`/`ResetSource` consumed by Tasks 13/14 |
| 13 | RSS/CodexResets tests match adapter normalization | Extends `MockHTTPClient` with `responses:` while keeping earlier initializers |
| 14 | Radar tests match confirmation/health | Produces `ResetRadarSnapshot`; `.empty` consumed Task 15 |
| 15 | Snapshot test matches builder/store | `SessionSnapshot.empty`/`HealthSnapshot.empty`/`ResetRadarSnapshot.empty` exist by sequence |
| 16 | UI test matches B section order and test IDs | Produces `Host`/`useHost`; Task 17 extends `detectHost` |
| 17 | Native/MCP host code matches host interface | Generates `WebAssets.panelHTML` consumed by Tasks 19/20 |
| 18 | Router tests match tool/resource metadata | Consumes `MCPTestFixtures`; Task 20 consumes same fixture |
| 19 | Live/MCP/plugin files agree | Consumes Tasks 2–18; Task 20 consumes `LiveEnvironment` |
| 20 | Status-title tests match formatter; app target matches Live | Extends `SnapshotBuilder.build` signature; all callers updated |
| 21 | Scripts/CI/manual gate agree | Consumes Tasks 15–20; no new production interfaces |

Shared-file pairs checked: `Package.swift` (2→18→19→20), `CodexInfoTests/main.swift` (2→18), `CoreTests.swift` (2→20), `SessionModels.swift` (6→7→9), `CodexAppServerClient.swift` (8→9), `SnapshotBuilder.swift` (15→20), `Web/src/host/detect.ts` (16→17). All are sequential additive edits with matching producer/consumer names; no contradiction found.

## Rulings

- R1 — Task 8: reuse `RateLimitPayloadDecoder` in `OfficialUsageClient` as well, replacing its private decode helpers. Why: the plan adds the helper but would otherwise leave duplicate decoding. Cost if wrong: a small, contained refactor.
- R2 — Task 1: the implementer may create the spike files and run the local protocol check, but MUST NOT modify `~/.codex/config.toml` or install the plugin into Codex without explicit user confirmation. This is an external side effect and the M0 gate is user-observed. Cost if wrong: M0 waits for the user; no repository risk.
- R3 — Task 20 modifies `SnapshotBuilder.build` to accept `windowDays`/`minimumTurns`; update every caller in the same task, including `AppEnvironment`. Cost if wrong: compile failure caught by the task gate.
- R4 — Deferred items listed in the plan (source URL editors, scan-interval UI, notification status panel, notarization, history charts) are out of the MVP execution scope and must be reported by the final review, not silently treated as missing core behavior.

## Task log
- Task 1: implementation complete (commit 807cd0d), review approved — M0 render is ⚠️ pending user gate; do not mark Task 1 complete until the user verifies. The gate must run before this worktree is removed.
- Task 1: minor (deferred): spike paths are bound to this worktree; expected for a throwaway spike.
- Task 1: minor (deferred): unknown notification-style messages without an id get an error without id; spike-only, no effect on the gate.
- Task 2: complete (commits 807cd0d..fcddcd2, review approved).
- Task 2: minor (deferred): zero-match filter exits 0 (`ran=0` with a mistyped filter); add a guard in a later test-runner polish.
- Task 2: minor (deferred): RED evidence was scaffold-level, not assertion-level.
- Task 2: minor (deferred): expectEqual echoes values; HTTP headers keep original casing; load() mixes CocoaError with CredentialError.
- Task 2: environment note: CLT linker search-path warnings are not code-related; reviewer reproduced them on an unrelated package.
- Task 3: complete (commits fcddcd2..359a09a, review approved).
- Task 3: minor (deferred): bucket fallback test short-circuits; rounding/tolerance/fiveHour edges untested; non-finite usedPercent could trap.
- Task 4: complete (commits 359a09a..c9a8b7f, review approved).
- Task 4: minor (deferred): success-path source/reset assertions absent; cache expiry only negative; 401/invalid-payload paths untested; fallback bucket not filtered; unusable weekly cached; report test-count inaccuracy.
- R5 — Task 5 test filter: the plan's `--filter ResetCredit` matches only one test because the first test name is "Reset credits sort..."; use `--filter Reset` to run both. Why: runner does case-insensitive substring matching; the test names are correct. Cost if wrong: none, both tests pass under the broader filter.
- Task 5: complete (commits c9a8b7f..d4b3bac, review approved; R5 filter ruling used).
- Task 5: minor (deferred): fixture does not actually exercise sorting; auth/request-count/cache/error paths untested; reuses OfficialUsageError.
- Task 6: fix round 1/5 opened (2 Important open: event structs lack public initializers; missing optional values collapse to 0/non-nil. Minor: structural payload gaps; missing-field tests; formatter allocation). Base 66e28b0. Fresh implementer dispatched because the harness cannot resume the live implementer.
- Task 6: fix round 1/5 (2 addressed, 0 open; commits 66e28b0..f2185ca).
- Task 6: complete (commits d4b3bac..f2185ca, review clean).
- Task 6: minor (deferred): token_usage_record now fails closed if any of three usage objects is missing; token_count with empty info can nil out Task 9 context; per-line ISO8601 formatter allocation.
- Task 7: controller verification found a spec violation the reviewer missed: `OutputRateCalculator` used `modelItemMs` directly instead of `min(modelItemMs, max(duration_ms - ttft, 1))` (OutputRateCalculator.swift:16-18). The plan's median fixture (`durationMs: 1`, `modelItemMs: 1_000`) is the cause; fix the formula and the fixture, add a clamp test. Fix round 1 opened at base c3abce9.
- Task 7: fix round 1/5 (1 addressed, 0 open; commits c3abce9..4a9808e).
- Task 7: complete (commits f2185ca..4a9808e, review clean after controller-caught formula fix).
- Task 7: minor (deferred): empty responseId records are UUID-keyed; TurnRate/SessionAggregate lack public inits; medianRate no negative-count guard.
- Task 8: fix round 1/5 opened (Critical: no request timeout and child can hang; stderr pipe never drained. Important: official camelCase aliases regressed; initialize not concurrency-safe; process transport untested. Base 4d8b248).
- Task 8: fix round 1/5 (5 addressed, 0 open; commits 4d8b248..4f8b5bf).
- Task 8: complete (commits 4a9808e..4f8b5bf, review clean after fixes).
- Task 8: minor (deferred): timed-out transport is terminal; deadline starts at dequeue; stderr diagnostics discarded; test runner has no per-test timeout.
- Task 9: fix round 1/5 opened (Important: SessionSnapshot/SessionIndex need public inits for the separate test target; same-size rewrite not re-detected; offset uses pre-read size so a growth race duplicates events. Also addressed: contextTokens/totalTokens spec fallbacks, median serviceTier filter, prune deleted cache entries. Deferred with ruling: `turn_aborted` parsing stays out of scope per spec 5.3; `now:` timestamps unused; repository rescans per call. Base e9a2e65).
- Task 9: fix round 1/5 (4 addressed, 0 open; commits e9a2e65..fa8c2a2).
- Task 9: complete (commits 4f8b5bf..fa8c2a2, review clean after fixes).
- Task 9: minor (deferred): thread total vs per-response input/output can differ only in synthetic fixtures (real logs make them equal); in-place rewrite with a different size still re-reads from the stale offset; `latestRateLimits`/SessionQuotaFallback are compile-verified only; read failure can poison the on-disk cache.
- R6 — public initializers: any model the separate `CodexInfoTests` target constructs must have a public init. Apply to Task 10 (`AccountSnapshot`), Task 12 (`ResetSignal`), Task 15 (`UsageSnapshot`, `Freshness`).
- Task 10: fix round 1/5 opened (Critical: unrecognized official payload decodes to a false zero labeled official+local instead of degrading; Important: official rows summed without honoring their date; Important: request-shape/decoding/timezone tests were deleted instead of kept. Also fix: reuse the shared authorized request builder, invalidate the cache on calendar-day rollover, allow a forced refresh. Base de15acc).
- R7 — account cumulative total: the daily-breakdown endpoint is range-scoped and cannot return an account-lifetime total, so the cumulative stays local and the snapshot labels its source honestly; Task 15 will present it that way.
- Task 10: fix round 1/5 (4 addressed, 0 open; commits de15acc..b06828e).
- Task 10: complete (commits fa8c2a2..b06828e, review clean after fixes).
- Task 10: minor (deferred): recognized-but-empty breakdown still publishes a zero; undated rows dropped when a sibling row has a date; `source` stays a free-form String; cumulative stays local (R7).
- Task 11: fix round 1/5 opened (Important: provider missing from baseline key; baseline exclusions (duration<=0, no token record) missing; 24h freshness rule absent; current value uses median-of-3 instead of the latest completed turn; nil model/effort/tier keys make the baseline filter a no-op; turns are not ordered chronologically. Minor: empty-snapshot disclaimer wording, sampleTurns on the insufficient path, IQR double conversion, excess public API, thin test coverage). Base 7eaca03.
- Task 11: fix round 1/5 (7 addressed, 0 open after the sampleTurns follow-up; commits 7eaca03..618b8c3).
- Task 11: complete (commits b06828e..618b8c3, review clean after fixes).
- Task 11: minor (deferred): route-downgrade vs route-anomaly conflated (single boolean); comp_hash not surfaced as evidence; sessions without a recorded reasoning effort always report 数据不足; no dedicated chronological-order test.
- R8 — implementer commits may lag their working tree: after every implementer report, check `git status` in the worktree before reviewing. Task 11's corrected analyzer was uncommitted, so the first review judged an older revision; the controller committed the working-tree version and re-reviewed.
- Task 12: fix round 1/5 (3 addressed, 0 open; commits 07dc632..b4532a3).
- Task 12: complete (commits 618b8c3..b4532a3, review clean after fixes).
- Task 12: minor (deferred): `raw_hash` still missing from the normalized fields; no host allowlist/redirect validation in adapters; a date-only instant is midnight so cross-source matching needs day-granularity handling in Task 14.
- R9 — Task 14 dedupe window: a date-only record lands at midnight of its day, so the ±6 h rule must also match records whose calendar day is equal (or ±1 day); carry this into Task 14.
- Task 13: fix round 1/5 (2 addressed, 0 open after the RSS title-scoped correction; commits 09e35a7..767efa8).
- Task 13: complete (commits b4532a3..767efa8, review clean after fixes).
- Task 13: minor (deferred): Codex Resets status severity falls back to `indicator` when `codex` is absent (could read as degraded); body-only completion wordings are no longer honoured; the source does not age-filter old feed items (Task 14 must trim).
- R10 — Task 14 event identity: the live sources title the same event differently ("第 13 天额度重置完成" vs "速蹬窗口关闭：…"), so a group must be identified by the occurrence day (local day, ±1 day for time-zone edges), not by the title alone. The spec's "来源 ID + 规范化标题 + ±6 小时" cannot confirm across sources on live data; the title stays a secondary hint.
- R11 — Task 14 confirmation rule: a group counts as "来源已确认" when at least two of the three reset sources (AI 哨兵记录 / AI 哨兵信号 / Codex Resets) contribute a `kind == .reset` signal; the official status source never counts; `kind == .reset` alone is not a confirmation.
- R12 — strong notifications may only fire for a signal with `kind == .reset`, `verified == true` and `severity == "strong"`.
- Task 14: fix round 1/5 (2 addressed, 0 open; commits 538f991..2883598).
- Task 14: complete (commits 767efa8..2883598, review clean after fixes).
- Task 14: minor (deferred): severity vocabulary is now the string contract strong/degraded/incident that the panel must render; a status row keeps the adapter's single confirming source; the neighbouring-day test only pins the inside-window half.
- Task 15: complete (commits 2883598..47c7d08, review approved).
- Task 15: minor (deferred): the session area can only be fresh/error; the five providers are awaited sequentially; two session scans per build; the no-data placeholders keep placeholder timestamps, so the panel must trust `freshness` and show "—" for an errored area; `DataState.loading` is never produced yet (the app must synthesise it during a refresh).
- R13 — panel rule: an area whose `freshness` is `error` must render "—" even when the payload carries placeholder timestamps; the panel may show `loading` while a refresh is in flight.
- R14 — live factory rule: build the snapshot with `async let` so one slow source cannot stall the panel, and avoid the double session scan per build (fix in `SessionRepository`).
- Task 16: fix round 1/5 (3 addressed, 0 open; commits d637006..2d46f42).
- Task 16: complete (commits 47c7d08..2d46f42, review clean after fixes).
- Task 16: minor (deferred): the tinted pill background is marginally under 4.5:1; the reset-card freshness key has no Swift test yet; `aria-controls` points at a collapsed element.
- Task 17: complete (commits 2d46f42..49b734e, review per implementer report; 102 Swift tests, 22 Playwright tests, tsc clean).
- Task 17: minor (deferred): the native bridge must be registered before the page loads (Task 20 must add the handler before `loadHTMLString`); the MCP client SDK grows the single file to ~476 KB; both bridges are verified against simulated hosts only.
- R15 — MCP Apps handshake: the view talks `ui/initialize` and `ui/open-link` to the *host* (Codex), not to our server; our server only serves `tools/*` and `resources/*`, and the UI binding is the tool's `_meta.ui.resourceUri` (modern) plus `ui/resourceUri` (legacy) and `openai/outputTemplate` (Codex), with MIME `text/html;profile=mcp-app`.
- Task 18: complete (commits 49b734e..6608f7c, review approved; 125 Swift tests).
- Task 18: minor (deferred): the skybridge MIME is not advertised (the Codex host accepts `text/html;profile=mcp-app`, which we serve); a JSON object without `method` answers -32700 instead of -32600; no JSON-RPC batch support.
- R16 — the Codex host's accepted UI MIME list contains `text/html;profile=mcp-app`, which the server already serves, so the `text/html+skybridge` variant of the design spec is a host-side alternative and needs no server change.
- Task 19: fix round 1/5 (2 addressed, 0 open; commits 4963aa0..4e77caa) + a follow-up test (cache window) that fails without the window check.
- Task 19: complete (commits 6608f7c..5b1e2c3, review clean after fixes).
- Task 19: minor (deferred): the install script has no `--write-config` (the config file is the user's, so it stays a printed instruction); the stdio loop is sequential; the snapshot store holds one file, so alternating baseline windows invalidates the cache.
- Task 20: fix round 1/5 (2 addressed, 0 open; commits c4d3f19..62265c2).
- Task 20: complete (commits e831c9c..62265c2, review approved after fixes; 148 Swift tests).
- Task 20: minor (deferred): the refresh loop is not serial, so an older snapshot can land after a newer one; a confirmed reset that is also a strong signal raises two notifications; the card key uses only the 6-character id suffix; the settings decode all-or-nothing; the login-item toggle is not synced back from System Settings.
- Task 21: complete (commit 70fb883): build-app.sh produces a signed dist/CodexInfo.app, test.sh is the one-command gate (Swift 148 PASS, web build, Playwright 22, MCP smoke), CI workflow added, docs/acceptance.md lists the seven manual checks.
- Task 21: minor (deferred): the status item label could not be read programmatically (no Accessibility permission), so that visual check stays manual; the CI workflow was never executed; install-plugin.sh still assumes the .build/release symlink.
- Task 21: fix round 1/5 (3 addressed, 0 open; commits 70fb883..HEAD): CI runner macos-15 + Swift 6 assertion, the gate installs the Playwright browser, the panel shows the re-login hint when the official read fails with 401/403.
- FINAL REVIEW (8b03cb0): 1 Critical (the committed WebAssets.swift is one commit stale, so the shipped panel lacks the re-login hint) + 10 Important (used_percent crash, turn_aborted not parsed, route mismatch counted as a downgrade, MCP ignores the app snapshot, index cache rewritten every scan, no network allow-list, open_dashboard always succeeds, settings gaps, CI never ran). One fix wave dispatched with the full list, then exactly one scoped re-review.
- Fix wave (final review): items 1-8 were fixed by the sub-agent (commits 0f9919a..e96df18), items 9-10 by the controller (settings clear data + threshold tier + CI bundle step). Gate: Swift 169 PASS, Playwright 23 PASS, MCP smoke OK, bundle built and signed.
- Fix wave re-review: findings 1-9 ADDRESSED with discriminating tests; finding 10 (CI never builds the bundle) was closed by the controller in commit 688b711 and verified locally (build-app.sh + `codesign --verify --deep --strict` pass). Final state: Swift 169 PASS, Playwright 23 PASS, MCP smoke OK, bundle signed, asset in sync with the build.
- M0 gate (2026-10-25): the plugin was installed into ~/.codex/config.toml (backup config.toml.bak.20261025-083746) and Codex was restarted. Codex's own log shows `mcp_server_startup_status_updated server=codexinfo status=ready`, i.e. the local marketplace, the plugin and the MCP server all load. The panel rendering itself still needs the user's eyes: the Codex web content is not exposed to Accessibility, so the controller cannot drive or read the chat UI.
- M0 gate PASSED (2026-10-25): the user confirmed the MCP App renders the panel inside a Codex thread (用量 / 周额度 / 重置卡 / 重置追踪 / 模型状态 / 最近会话 with 输出速率 / 账号统计 / 底栏 all present).
- Defect found during the M0 check: the panel's quota area was empty. Root cause: the official /wham/usage returns `rate_limit.primary_window` (used_percent, limit_window_seconds, reset_at), while the client only decoded the session-log shape `rate_limits.primary` (window_minutes, resets_at); and an official response without a weekly window never fell back to the session numbers. Fixed in commit f14b67a (both payload shapes + fallback), three new tests, Swift suite 172 PASS. Verified live: snapshot.json now shows weeklyRemainingPercent 71, reset 2026-10-30, authExpired false; the app and the plugin were rebuilt and both restarted (Codex log: server=codexinfo status=ready).
