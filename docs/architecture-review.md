# CodexInfo 架构评审与修复目标（2026-10-25）

## 方法

两路独立只读审计：一路从软件工程与 DDD 边界，一路从并发、缓存、安全、持久化与发布工程。结论按“会导致用户看到错误数据或错过重置”排序，而不是按代码风格排序。

## 总体判断

优点：
- 端口/适配器边界在数据源侧是真实的：`HTTPClient`、`ResetSource`、`QuotaFallbackProviding`、`SnapshotBuilding` 都可替换，且有测试。
- 凭证隔离可信：按来源拆分 host 白名单与 client，重定向有 allow-list delegate，Qoder 不读凭证。
- 解析防御性好：百分比防 NaN/溢出、缺失值不伪造 0、确认短语拒绝否定词。
- 读模型有 provenance：`DataState`、`QuotaSource`、`source/updatedAt/note` 让 UI 不把旧值当新值。

核心问题：
1. **重置追踪没有领域历史。** 每次成功抓取会用新结果整体替换该来源缓存（`ResetRadarService.swift:125`），雷达状态只在内存；应用重启、来源返回裁剪后的空列表、或某源失败后，最近一次重置会消失。这正是“刚刚重置却没有任何信息”的剩余根因。
2. **`scan()` 可重入。** 两次扫描重叠时，旧扫描可能后完成并覆盖新健康状态/退避时间，同时重复抓取四个源。
3. **刷新会被丢弃而不是合并。** `AppEnvironment.refresh` 的 in-flight 守卫让手动扫描后的重建直接变成 no-op。
4. **领域规则泄漏到 React。** 上次重置、just-reset、确认规则和时区格式在 TypeScript 重新实现；Core 没有统一的窗口值对象，菜单栏与插件可能得出不同结论。
5. **通知键不稳定。** 以 epoch 秒作键，`reset_after_seconds` 的 ±1 秒漂移会在 15 分钟窗口内重复提醒；已发送键集合无上限。
6. **失败状态被掩盖。** 官方额度读取 401 后若回退也失败，返回旧缓存时丢掉 `authExpired`。
7. **雷达来源仍以显示名做确认身份。** 来源改名会破坏交叉确认；这是后续的身份模型重构项。同日分组已收紧：两条精确时间记录必须落在 6 小时窗口内，只有午夜的时间戳（date-only 记录）可以代表整天并入同日的定时记录。

## 本轮修复目标（必须完成）

1. **雷达历史持久且合并**
   - `ResetRadarService` 支持从上一份快照 seed 最近记录与来源健康。
   - 成功抓取改为“按 id 合并 + 30 天裁剪 + 每源上限”，空列表不再清空历史。
   - `LiveEnvironment` 启动时从 app 快照（MCP 再回退自己的快照）seed。
2. **扫描单飞与时钟回拨安全**
   - 同一时刻只允许一个 scan；并发调用共享同一个 Task。
   - `nextScanAt` 领先当前时间超过 2 个间隔时视为时钟回拨，立即重扫。
3. **刷新合并**
   - 新增 `RefreshGate`：运行中再来请求只排队一次重跑，不再直接丢弃。
   - `AppEnvironment` 使用它；慢构建期间的手动扫描最终会产出新快照。
4. **额度窗口领域化**
   - `QuotaSnapshot` 持久化 `weeklyWindowStartedAt`（由 `weeklyResetsAt - weeklyWindowMinutes` 推导）。
   - 前端优先使用该字段；仅旧快照缺字段时才回退到 7 天算术。
5. **通知稳定**
   - `resetSoon` 键改为重置整点桶，不受 ±1 秒漂移影响；同周第二次重置使用不同键。低额度事件在没有重置时间时回退到 ISO 周，避免每小时重复。
   - 已发送键限制在最近 200 个；剩余百分比缺失时正文显示 `—` 而不是 `0%`。
6. **登录过期不被缓存吞掉**
   - 官方读取 401 且回退不可用时，返回旧缓存但把 `authExpired` 置为 true。
7. **架构护栏**
   - 增加测试：`CodexInfoCore` 不得 import AppKit/SwiftUI/WebKit/UserNotifications/Live/App/MCPKit。
   - 移除 `URLSessionHTTPClient.init(session:hosts:)` 这个可绕过 redirect delegate 的公开入口。

## 本轮不做（明确记录）

- 雷达来源身份从显示名迁移到稳定 `sourceId`（含持久化确认字段）。
- date-only 精度进入领域模型：当前用“服务日历的午夜”作为 date-only 的近似；来源时区与用户时区不同时可能少合并一次同日记录。
- 面板中 `confirmed` / justReset 的展示判断与 Core 完全去重；当前已共用窗口起点与后端 latest 字段，但 TS 仍保留防御性判断。
- 客户端 provider 的 last-good/stale 语义与 UI 状态扩展。
- 快照/设置的 schemaVersion 与迁移诊断。
- os_log 全链路观测、请求体积上限、主线程 AX/快照写入优化。
- Developer ID 公证、arm64/Intel 双架构、版本文案单一来源。
- 通知键在整点前 30 分钟边界（±1 秒漂移）的极端情况；旧版 sorted 键历史的迁移顺序；同一小时内两次重置共用低额度键。
- 时钟回拨后 `health.lastSuccessAt` 可能暂时显示为未来时间。
- seed 记录的代表 `sourceId` 不在当前四源配置中时会被忽略；旧快照中 `confirmingSources` 为空的 seed 组无法恢复双源确认。
- 除 current source 外的适配器若未来出现 id 复用，仍可能把不同事件并入同一确认组；当前 current source 已使用稳定 `event_id`，其余使用 guid/tweet id。

这些是下一轮架构债，不得被误认为已经修复。

## 验收

- 新增/更新的 Swift 测试覆盖：seed 恢复（含跨来源确认与代表源重发）、空列表合并、并发 scan 单飞、时钟回拨（含 blocked 源重试）、RefreshGate 合并、窗口起点、401 缓存保留、通知键稳定性（含整点边界与同周两次重置）、键历史按插入顺序裁剪、同日远隔重置不合并、forecast 挤占时保留 reset 与 latestStrong。

## 对抗审查记录

### Round 1 — FAIL

- High：seed 恢复后 `latestConfirmed` 丢失，`merge()` 只按代表源名重算确认来源，`apply(seed:)` 未恢复 `latestConfirmed`。
- Medium：已发送键用字典序裁掉“最小字符串”而非最旧；ISO 周键在 ±1 秒边界会分裂；每源上限不区分 forecast/reset；时钟回拨后 blocked 源仍被跳过；额度区仍按本地时区显示。
- 修复：`apply` 恢复 latestConfirmed；`merge` 合并成员已有确认来源；新增 `NotificationKeyHistory`；键改为整点桶；`merged()` 保留 reset；`makeSnapshot` 的最新字段改为从完整 fresh 集计算；回拨时清空 `blockedUntil`；额度区改北京时间。新增回归测试。

### Round 2 — FAIL

- High：seed 的确认组被代表源重新发布同 id 的原始行时，`merged()` 用原始行覆盖组，确认来源再次丢失。
- Medium：date-only 判定耦合服务日历；`latestStrong` 仍读裁剪后的 `recent`。
- 修复：`mergedSignal()` 在 id 碰撞时并集确认来源、保留 reset 类型/verified/strong；`latestStrong` 优先读 `latestReset`；新增“代表源重发”和“forecast 挤占时 latestStrong”回归测试。date-only 精度列为后续项。

### Round 2 re-review — PASS

- Critical/High：无。Round 2 High 已由 `mergedSignal()` 修复并有回归测试；`latestStrong` 已改读 `latestReset`。
- 复核新增项已关闭：无重置时间时低额度键回退 ISO 周，避免每小时重复；`CodexRadarCurrentSource` 使用 `event_id` 作为稳定 id；`resetSoon` 改为整点桶后同周两次重置不再共用键。
- 残余 Medium/Low 已写入「本轮不做」：date-only 时区精度、seed 的来源增删迁移、旧快照空确认、非 current source 的 id 复用、通知整点前 30 分钟边界、旧键迁移顺序、回拨后的 lastSuccessAt、同一小时低额度键。
- 结论：两轮对抗审查的 Critical/High 均已关闭，满足本轮目标；docs 中列出的架构债留待下一轮。
- `swift run codexinfo-tests`、Playwright、`tsc --noEmit` 全绿。
- 两轮独立对抗性审查：第一轮找缺陷并修复，第二轮复核修复并找新问题；两轮均无未关闭的 Critical/High。
