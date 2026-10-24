# CodexInfo 设计文档

- 日期：2026-10-24
- 状态：设计已确认（第 1–6 节逐节确认），待实现
- 仓库：`https://github.com/laoertongxue/CodexInfo`
- 本地路径：`/Users/laoer/Documents/CodexInfo`
- 目标宿主：Codex 桌面版 + macOS 菜单栏
- 设计基线：用户提供的 Codex 用量弹层截图；布局采用 B 版“截图保真”

## 0. 摘要

CodexInfo 复刻截图中的 Codex 用量弹层，并补充两项判断：

1. **Token 输出速率**：按轮次计算生成吞吐，展示本轮值与近 5 轮中位。
2. **是否降智**：基于本机近 7 天、同模型/同档位基线，给出“正常 / 疑似降智 / 已降智（本地判定）/ 数据不足”四态及证据。

产品由两个入口组成：

- **macOS 菜单栏常驻 App**：常驻条显示 `额度 · 速率 · 模型状态`，点击展开完整面板。
- **Codex 桌面版插件**：MCP server + MCP App 面板 + skill，让 Codex 内也能查看同一份快照并唤起菜单栏面板。

第三方插件不能向 Codex 底部状态栏注入自定义 chip，因此底部额度 chip 保持 Codex 原生，常驻入口由菜单栏承担。

## 1. 背景与目标

截图中的弹层已经包含：周额度、重置卡、重置追踪、当前会话 Token、账号统计。用户还要求补充：

- Token 输出速率（tok/s）。
- 是否降智，且要有可复核的判定依据，而不是一句主观结论。

目标：

- 打开面板 2 秒内看到“还剩多少、何时重置、有没有重置卡、最近有没有重置、这轮模型是否异常”。
- 同一套数据同时服务菜单栏与 Codex 插件，数字必须一致。
- 凭证与对话正文不出本机；降智结论只基于本机数据，并明确标注“本地判定”。

## 2. 范围

### 2.1 本期范围

- macOS 14+ 菜单栏 App（`LSUIElement`，无 Dock 图标）。
- Codex 桌面版本地插件（`.codex-plugin/plugin.json` + `.mcp.json` + `skills/`）。
- 官方额度、重置卡、账号 Token；本地会话 Token、上下文、输出速率。
- 本地 7 天降智基线。
- 四源重置追踪、来源健康、交叉确认、通知。
- 浅色/深色面板；设置、开机启动、安装脚本、测试与验收。

### 2.2 明确不做

- 自动使用重置卡、自动购买、代用户执行任何额度操作。
- 注入或修改 Codex 客户端 UI、底部状态栏、`app.asar`。
- 读取、存储、展示、上传对话正文或工具输出内容。
- Windows / Linux、Codex CLI TUI 集成、移动端。
- 团队/工作区账号、多账号切换。
- 社区 Model IQ 参与降智结论。
- 首版不做周额度历史曲线、CSV 导出。

## 3. 术语与口径

| 术语 | 定义 |
| --- | --- |
| 周额度 | 官方返回的 10080 分钟窗口剩余百分比 |
| 五小时窗口 | 官方返回的 300 分钟窗口；本期解析但不展示 |
| 重置卡 | 官方 `rate-limit-reset-credits` 中 `status=available` 的卡片 |
| 重置追踪 | 对四个公开来源的轮询、归一化、交叉确认与健康展示 |
| 当前会话 | 有活动 turn 的最近会话；无活动时显示最近一次会话并标“最近会话” |
| 输出速率 | 一轮模型生成期间的输出 token 吞吐，单位 tok/s |
| 降智 | 本机近 7 天同模型/同档位基线下的持续性能异常，不代表官方结论 |
| 四源 | CodexRadar 记录、CodexRadar 信号、Codex Resets、OpenAI Status |

## 4. 产品设计

### 4.1 双入口

| 入口 | 承载 | 职责 |
| --- | --- | --- |
| 菜单栏 App | `NSStatusItem` + `NSPopover` + `WKWebView` | 常驻、通知、完整面板、设置 |
| Codex 插件 | MCP server + MCP App + skill | Codex 内查询、渲染同一面板、唤起菜单栏 |

- 不注入 Codex 底部状态栏；底部原生额度 chip 保持不动。
- 两个入口共用 `CodexInfoCore` 与同一份单文件 HTML，禁止两套口径。

### 4.2 面板布局（B 版）

面板宽度 340，最大高度 780，内部滚动；浅色/深色跟随系统。

| 顺序 | 区块 | 内容 | 状态 |
| --- | --- | --- | --- |
| 1 | 头部 | `用量`、plan 徽标、`刷新`、`关闭`（插件内隐藏关闭） | 固定 |
| 2 | 周额度 | 剩余百分比、进度条、重置时间、倒计时 | 固定 |
| 3 | 重置卡 | 可用张数、每张到期时间、剩余时长 | 固定；无卡显示“暂无可用重置卡” |
| 4 | 重置追踪 | 立即扫描、`x/4 来源可用`、最近确认记录、原始出处、上次/下次扫描、通知状态、可折叠来源健康 | 固定；可折叠 |
| 5 | 模型状态（新增） | 四态徽标、一行摘要、可展开证据 | 正常态证据默认折叠；疑似/已降智自动展开 |
| 6 | 当前会话 | 上下文、Token 总数、输入/输出、缓存读取、输出速率（新增） | 活动/最近会话两态 |
| 7 | 账号统计 | 今日 Token、累计 Token、更新时间 | 固定 |
| 8 | 底栏 | 模型、额度、更新时间 | 固定 |

- 模型状态放在重置追踪之后、当前会话之前，保持截图原有节奏。
- 输出速率放在当前会话最后一行。
- 面板不显示“新增”标记；该标记只存在于设计对照稿。

### 4.3 状态与交互

| 对象 | 状态 | 规则 |
| --- | --- | --- |
| 周额度 | 正常 / 偏低 / 危险 / 未知 | 未知显示 `—`；颜色只做提示，不改变数值 |
| 重置卡 | 正常 / <72h / <24h / 已过期 | 只展示可用卡；<72h 橙色，<24h 红色，已过期隐藏 |
| 模型状态 | 正常 / 疑似降智 / 已降智（本地判定）/ 数据不足 | 见 5.6 |
| 四源 | 可用 / 降级 / 不可用 | `x/4 来源可用`；失败源单独显示最后成功时间 |
| 数据新鲜度 | 新鲜 / 过期 / 加载中 / 错误 | 超过 5 分钟标“数据可能过期” |
| 当前会话 | 生成中 / 空闲 / 无数据 | 有 `task_started` 无 `task_complete` 为生成中；否则空闲 |

交互：

- 刷新：立即重拉官方额度、重置卡、账号与会话快照。
- 立即扫描：只触发四源扫描，不刷新额度。
- 查看原始出处：用系统浏览器打开来源 URL。
- 通知设置：打开系统通知设置；通知关闭时新动态仍在面板高亮。
- 关闭：仅菜单栏面板；插件面板无关闭按钮。
- 设置：菜单栏右键或面板齿轮打开原生设置窗口。

### 4.4 菜单栏

- 常驻条默认片段：`84% · 42 tok/s · 正常`。
- 使用 `NSStatusItem` + 属性字符串保留颜色；不使用 `MenuBarExtra` 的纯文本标签。
- 左键开合面板；右键菜单：立即刷新、扫描重置源、设置、开机启动、退出。
- 片段可在设置中启用/排序：周额度、输出速率、模型状态、重置卡数量、更新时间。
- 无数据时用 `—`，不显示 0；模型状态未知显示“数据不足”。

### 4.5 设置

原生 SwiftUI 窗口，分四组：

1. **常驻条**：片段开关与顺序、刷新间隔。
2. **模型基线**：基线窗口（7/14/30 天）、最少轮数（默认 8）、阈值档位、是否启用降智判定。标准档：速率 ≤70%、TTFT ≥2 倍或 +2s；保守档：速率 ≤60%、TTFT ≥3 倍或 +3s，其余信号不变。
3. **重置追踪**：每个源启用/URL/超时、扫描间隔（默认 60s，最小 30s）、通知开关。
4. **隐私与维护**：清除本地缓存、登录态检测、开机启动、版本与日志目录。

所有设置落在 `~/Library/Application Support/CodexInfo/settings.json`；不写入 Codex 配置。

### 4.6 通知

触发条件：

- 新的“已交叉确认”重置。
- 新的强信号（来源标记 `severity=strong`）。
- 任一可用重置卡 <24h 到期；同一张卡只通知一次。
- 周额度 <10%；同一重置周期只通知一次。

通知关闭时只高亮，不弹系统通知；开启时首次请求权限。通知内容只含额度/时间/来源，不含对话内容；同一事件、同一张卡、同一周期额度只通知一次，重启不重复。

### 4.7 空态、错误与过期

- 加载：骨架行，不显示假数字。
- 无数据：统一 `—`，附一句原因（未登录、无会话、源不可用）。
- 登录失效：`登录已失效，请在 Codex 中重新登录`；额度可回落会话快照，重置卡显示 `—`。
- 源失败：对应源行显示错误与最后成功时间；不阻塞其他源。
- 过期：保留旧值并标“数据可能过期”；不把旧值当实时值。
- 崩溃恢复：面板重载后重新取快照；MCP server 重启不影响菜单栏。

## 5. 数据口径

### 5.1 额度

数据源优先级：

1. 官方 `GET https://chatgpt.com/backend-api/wham/usage`（Bearer）。
2. app-server `account/rateLimits/read`。
3. 最近会话 `token_count.rate_limits`。

规则：

- 先过滤 `limit_id == "codex"`；若返回 `rate_limits_by_limit_id`，取其中的 `codex` 桶。
- 不假设 `primary` 一定是周窗口；按 `window_minutes` 分桶：`10080` 周、`300` 五小时。
- 周剩余 = `clamp(100 - used_percent, 0, 100)`，四舍五入为整数。
- 重置时间只取 `resets_at`（epoch 秒）；缺失时显示 `—`，不推算倒计时。
- 五小时窗口本期只解析、不展示。
- 刷新 60 秒；手动刷新立即执行；刷新失败保留旧值并标过期。
- 与 Codex 官方用量页对照，允许 ≤1 个百分点误差。
- 官方响应字段以 M0 实测校准；解析器容忍字段缺失，缺失时走下一优先级。

### 5.2 重置卡

数据源优先级：

1. `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`（Bearer）。
2. app-server `rateLimitResetCredits`。

规则：

- 只展示 `status == "available"` 且未过期的卡；按 `expires_at` 升序。
- `available_count` 存在时用于总数；不存在时用可用卡数量。两者不一致时以列表为准并标注。
- 字段：`id` 只保留后 6 位；`granted_at`、`expires_at`、`reset_type`、`title`。
- 到期阈值：<72h 橙色，<24h 红色；不自动使用、不调用 `consume`。
- 无卡显示“暂无可用重置卡”，不显示 0 张的进度条。

### 5.3 当前会话

数据源：`~/.codex/sessions/**/*.jsonl`。若设置 `CODEX_HOME`，以该目录为准。

关键事件：

| 事件 | 用途 |
| --- | --- |
| `turn_context` | 实际 model、effort、comp_hash |
| `thread_settings_applied` | 用户选择的 model、reasoning_effort、service_tier、provider |
| `token_usage_record` | 每次响应的 usage、turn/thread 累计；按 `response_id` 去重 |
| `event_msg.task_started` | 轮次开始、turn_id |
| `event_msg.task_complete` | `duration_ms`、`time_to_first_token_ms`、完成时间 |
| `event_msg.token_count` | `last_token_usage`、`total_token_usage`、`model_context_window`、`rate_limits` |
| `event_msg.item_completed` | `item.type`、`started_at_ms`、`completed_at_ms` |
| `compacted` | 上下文压缩次数 |

规则：

- “当前会话” = 最近修改的会话文件；有 `task_started` 无 `task_complete` 时标“生成中”，否则标“最近会话”。若同时有多个活动会话，取最近写入文件，并在设置中说明该口径。
- 上下文 Token = `last_token_usage.total_tokens`；窗口 = `model_context_window`；上下文百分比 = 两者相除。`last_token_usage` 缺失时回落到 `thread_token_usage.total_tokens / model_context_window`。
- Token 总数 = `thread_token_usage.total_tokens`；缺失时按 `response_id` 去重后累加 `token_usage_record.usage.total_tokens`。输入/输出/缓存同理。
- 多响应轮次按 `response_id` 去重；同一响应不重复累加。
- `item.type` 为 PascalCase：`Reasoning`、`AgentMessage` 为模型生成；`CommandExecution`、`McpToolCall`、`FileChange`、`Extension` 为工具类。
- 不解析、不持久化、不向上层暴露 `content`、`aggregated_output`、工具结果等正文字段；解析器只取白名单字段。

### 5.4 输出速率

一轮的输出 token 数：

`output_tokens_turn = Σ token_usage_record.usage.output_tokens`（按 `response_id` 去重）。

生成时间优先用模型型 item 的时长：

`generation_ms = min(Σ (completed_at_ms - started_at_ms), max(duration_ms - time_to_first_token_ms, 1))`。

求和只取 `event.payload.item.type` 为 `AgentMessage` 或 `Reasoning` 的 `item_completed` 事件；`started_at_ms`、`completed_at_ms` 是事件字段，不是 item 内部字段。

若模型型 item 缺失或为 0，回退：

`generation_ms = max(duration_ms - time_to_first_token_ms - tool_ms, 1)`。

其中 `tool_ms` 为 `item_completed` 事件中 `CommandExecution + McpToolCall + FileChange + Extension` 的时长之和。

输出速率：

`tok_per_sec = output_tokens_turn / max(generation_ms, 1) * 1000`。

展示：

- 只对已完成轮次计算；展示本轮值 + 同模型/同档位近 5 轮中位，保留 1 位小数。
- 生成中不伪造实时值；显示上一轮值并标“生成中”，或显示 `—`。
- 按 OpenAI usage 语义，`output_tokens` 为总输出、`reasoning_output_tokens` 为其子集；M0 用实测样本校验，若不一致则在 UI 标注口径并以 `output_tokens` 为速率分母。另展示推理占比 `reasoning_output_tokens / output_tokens`。
- 工具调用密度 = 工具类 item 数 / (output_tokens / 1000)；`output_tokens == 0` 时该轮不参与判定。
- 首 token = `time_to_first_token_ms / 1000`，保留 1 位小数。
- 无样本显示 `—`；分母异常（≤0）丢弃该轮，不产生无穷大。

### 5.5 账号统计

数据源优先级：

1. `GET https://chatgpt.com/backend-api/wham/usage/daily-token-usage-breakdown?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&group_by=day`，可带 `x-openai-codex-usage-categories: 1`。
2. 本地全量会话索引：按 `response_id` 去重，按本机时区切日。

规则：

- “今日”按本机时区的自然日；跨时区/夏令时由 `Calendar` 处理。
- “累计”优先官方返回的账号总量；回落为本地索引累计。
- 面板标注数据来源（官方/本地）；两者差异不静默合并。
- 刷新 5 分钟；手动刷新立即执行。
- 账号接口的响应字段以 M0 实测校准；失败回落本地，且不影响额度与会话展示。

### 5.6 降智判定

#### 5.6.1 基线

- 时间窗：近 7 天（设置可改 14/30 天）。
- 样本：同一 `model + reasoning_effort + service_tier + provider`，最多 30 轮，至少 8 轮。
- 剔除：报错、中断、`duration_ms <= 0`、无 `token_usage_record` 的轮次。
- 统计：中位数 + MAD；MAD 为 0 时用 IQR；仍为 0 时不做该信号判定。
- 当前值：最近 1 个已完成轮次；持续异常用最近 3 轮中至少 2 轮命中同一信号。

#### 5.6.2 异常信号

| 信号 | 阈值 | 适用条件 |
| --- | --- | --- |
| 输出速率下降 | 当前 ≤ 基线 70%，且稳健 z ≤ -2 | 基线 ≥8 轮 |
| 首 token 变慢 | (当前 ≥ 基线 2 倍，或 ≥ 基线 +2s)，且稳健 z ≥ 2 | 基线 ≥8 轮且基线 >0 |
| 推理占比下降 | 当前 ≤ 基线 50% | 基线推理占比 ≥5% |
| 工具调用密度下降 | 当前 ≤ 基线 60% | 基线密度 ≥0.5 次/千 token |
| 路由异常 | 实际 model/effort/service_tier 与用户选择不一致，或实际档位更低 | 有 `turn_context` 与 `thread_settings_applied` |

补充：

- `comp_hash` 变化只作为“配置指纹变化”证据展示，**单独不计入异常信号**。
- 周额度消耗速度、社区消息不参与降智结论。
- 模型切换后基线重建，显示“新模型基线积累中”。

#### 5.6.3 结论

| 结论 | 规则 |
| --- | --- |
| 数据不足 | 基线 <8 轮，或 24 小时内无已完成轮次 |
| 正常 | 0–1 个异常信号 |
| 疑似降智 | ≥2 个信号，且至少 1 个性能信号；或路由异常 + 1 个信号 |
| 已降智（本地判定） | (≥3 个信号，或路由降档 + ≥2 个信号) 且最近 3 轮中至少 2 轮持续命中 |

性能信号 = 输出速率、首 token、推理占比、工具调用密度；路由异常单独计一类。

- 路由异常单独出现时，结论仍为正常，但证据区显示“路由不一致”；不与降智混为一谈。
- “路由降档”只在档位可比较时判定：effort 顺序 `low < medium < high < xhigh`；模型等级不可比较时只记“模型不一致”，不记“降档”。实际 service_tier 缺失时只用 model/effort 比较。
- 最近 3 轮不足 3 轮时，最高只能判“疑似降智”，不能判“已降智”。

UI 必须显示：

- `基于本机近 7 天基线，不代表官方结论`。
- 样本轮数、基线时间窗、模型/档位。
- 每条证据的“当前值 / 基线 / 变化”；不展示对话正文。
- 数据不足时说明原因（样本不足或 24 小时无新轮次）。

### 5.7 重置追踪（四源）

默认源：

| 面板名称 | 默认 URL | 用途 |
| --- | --- | --- |
| AI 哨兵记录 | `https://codexradar.com/current.json` | 权益事件与记录 |
| AI 哨兵信号 | `https://codexradar.com/feed.xml` | 信号流 |
| Codex Resets | `https://codex-reset.com/api/feed`、`https://codex-reset.com/api/status` | 重置与额度事件 |
| 官方状态 | `https://status.openai.com/api/v2/summary.json` | 服务健康，不证明重置 |

归一化字段：`id`、`source_id`、`source_name`、`kind`（reset / banked / limits / verifying / status / note）、`severity`、`title`、`summary`、`published_at`、`url`、`verified`、`scope`、`raw_hash`。

规则：

- 三个重置类来源：AI 哨兵记录、AI 哨兵信号、Codex Resets。
- Codex Resets 以 `/api/feed` 为主；`/api/status` 失败只把该源标为降级，不判整源不可用。
- “来源已确认” = 至少 2 个重置类来源交叉确认；仅 1 个来源显示“单一来源”。
- 官方状态只作旁证；服务事故不等于额度重置。
- 去重：来源 ID + 规范化标题 + ±6 小时时间窗。
- 缓存：最近 20 条总记录，每源最近 10 条；保留最后成功时间。
- 扫描：默认 60 秒；单源 10 秒超时；失败退避 1/2/5/15 分钟。
- 面板显示 `x/4 来源可用`、上次扫描、下次扫描、每源健康。
- 通知按 4.6；通知关闭时新动态在面板高亮；来源未提供 `severity` 时不触发强信号通知。
- 保留免责声明：`站点消息不等于个人额度恢复；无明确时间不推算倒计时。`
- 源 URL 可在设置中修改；更换“AI 哨兵”站点只需改配置，不改代码结构。

### 5.8 格式、时间与新鲜度

- 数字：`1.24M`、`3.3B`、`42.3 tok/s`、`84%`；百分比整数，速率 1 位小数。
- 时间：本机时区，`yyyy/MM/dd HH:mm`；剩余时长 `N 天 N 小时`，不足 1 小时显示 `N 分钟`。
- 刷新：额度 60s、会话 5s、账号 5min、四源 60s；手动刷新立即执行。
- 新鲜度：超过 5 分钟标“数据可能过期”；不隐藏旧值。
- 倒计时只基于明确的 `resets_at`；缺失不推算。

### 5.9 隐私与凭证

- 允许读取 `~/.codex/auth.json` 的 access token；token 只驻留内存。
- token 只发送到 `chatgpt.com`；不写日志、不写缓存、不写快照、不进 UI。
- 不读取、不存储、不上传对话正文、工具输出、附件内容。
- 会话索引只保留数值、模型/档位、事件时间、计数；`id` 只保留后缀。
- 网络白名单：`chatgpt.com`、`codexradar.com`、`codex-reset.com`、`status.openai.com`；用户自定义源在设置中显式启用后加入本次白名单，只接受 HTTPS，拒绝 loopback/私网/链路本地地址，且重定向必须仍在白名单内。
- 提供“清除本地数据”，删除索引、快照、源缓存、基线。

## 6. 架构

### 6.1 仓库与 target

```text
CodexInfo/
├─ Package.swift
├─ Sources/
│  ├─ CodexInfoCore/          # 数据与判定
│  │  └─ Generated/WebAssets.swift  # 由 Web 构建生成并提交
│  ├─ CodexInfoApp/           # 菜单栏 App
│  └─ CodexInfoMCP/           # MCP server
├─ Web/                       # React + Vite，构建单文件面板
├─ .agents/plugins/marketplace.json
├─ plugins/codexinfo/
│  ├─ .codex-plugin/plugin.json
│  ├─ .mcp.json.template
│  ├─ skills/codex-usage/SKILL.md
│  ├─ assets/icon.svg
│  └─ bin/                    # 构建产物，gitignore
├─ scripts/
├─ Tests/
└─ docs/
```

- `CodexInfoCore`：库；两个可执行 target 共用。
- `CodexInfoApp`：`LSUIElement` 菜单栏 App。
- `CodexInfoMCP`：stdio MCP server。
- 面板 HTML 由 Vite 构建为单文件，脚本生成 base64 Swift 常量；App 与 MCP 共用，避免两套 UI。
- 运行时不依赖 Node；Node 只用于构建 Web。

### 6.2 Core 模块

| 模块 | 职责 |
| --- | --- |
| `CredentialStore` | 读取 auth.json；内存缓存 ≤60s；401 重读一次 |
| `CodexAppServerClient` | 启动/握手/关闭 `codex app-server`；超时与重连 |
| `QuotaService` | 官方额度、app-server、会话回落；窗口分桶 |
| `ResetCreditService` | 官方重置卡、app-server 回落；排序与阈值 |
| `SessionIndexer` | JSONL 增量索引；活动会话；白名单字段 |
| `UsageAnalytics` | 上下文、累计、账号统计、输出速率、基线 |
| `DegradationAnalyzer` | 降智四态与证据 |
| `ResetRadarService` | 四源适配、去重、交叉确认、健康、退避 |
| `SnapshotBuilder` | 汇总各服务为统一快照 |
| `SnapshotStore` | 原子写快照/索引/源缓存/基线 |
| `NotificationService` | 本地通知与权限状态 |

### 6.3 数据流与缓存

```text
官方 /wham ─┐
app-server ─┼─> QuotaService / ResetCreditService ─┐
会话 JSONL ─┴─> SessionIndexer / UsageAnalytics ───┼─> SnapshotBuilder ─> snapshot.json
四源 HTTP ────> ResetRadarService ─────────────────┘
                                      │
                                      ├─> WKWebView（native bridge）
                                      └─> MCP App（host bridge）
```

- App 写 `~/Library/Application Support/CodexInfo/snapshot.json`（原子替换）。
- MCP 优先读 <60 秒的快照；过期或缺失时自行计算并写 `mcp-snapshot.json`，避免写冲突。
- `session-index.json` 按 `path + size + mtime` 增量；`baseline.json` 按模型/档位分组；`sources.json` 缓存四源。
- 所有写入使用临时文件 + rename；读取失败回落到上一份有效快照。

### 6.4 菜单栏宿主

- `NSStatusItem` + `NSPopover`；属性字符串常驻条。
- `WKWebView` 加载单文件 HTML；`WKScriptMessageHandler` 接收：
  `getSnapshot`、`refresh`、`scan`、`openURL`、`openSettings`、`close`。
- Swift → Web 通过 `evaluateJavaScript("window.codexInfo.render(snapshot)")`。
- CSP：`default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'`。
- 禁止外部导航；外部链接交给系统浏览器。
- 设置窗口原生 SwiftUI；面板只负责展示与轻交互。
- `LSUIElement=true`；`SMAppService.mainApp` 开机启动；单实例锁。

### 6.5 Codex 插件与 MCP

插件结构：

```text
plugins/codexinfo/
├─ .codex-plugin/plugin.json
├─ .mcp.json                 # 安装脚本生成，绝对路径
├─ .mcp.json.template
├─ skills/codex-usage/SKILL.md
├─ assets/icon.svg
└─ bin/codexinfo-mcp         # 构建产物
```

`.codex-plugin/plugin.json` 关键字段：

```json
{
  "name": "codexinfo",
  "version": "0.1.0",
  "description": "Codex usage, reset cards, reset radar, output speed and local model-health verdict.",
  "author": { "name": "laoer" },
  "mcpServers": "./.mcp.json",
  "skills": "./skills/",
  "interface": {
    "displayName": "CodexInfo",
    "shortDescription": "Quota, reset cards, tok/s and local model health",
    "category": "Developer Tools",
    "composerIcon": "./assets/icon.svg",
    "logo": "./assets/icon.svg"
  }
}
```

MCP server：

- stdio JSON-RPC 2.0；stdout 只输出协议消息，日志写 stderr。
- `initialize` 声明 tools/resources，协议版本 `2025-06-18`，按宿主支持协商；`resources/list` 返回 UI 资源描述；支持 `ping`、`notifications/initialized`。
- tools：
  - `get_usage_snapshot`：额度、重置卡、当前会话、账号、速率、健康摘要、四源摘要。
  - `get_model_health`：降智结论、证据、基线元数据。
  - `scan_reset_sources`：触发一次四源扫描，返回健康与最近记录。
  - `show_usage_panel`：返回 MCP App UI 资源 + 三行文本摘要。
  - `open_dashboard`：通过 `codexinfo://show` 唤起菜单栏面板。
- `show_usage_panel` 的工具 `_meta` 同时包含：
  `ui.resourceUri`、`ui/resourceUri`、`openai/outputTemplate`，值均为 `ui://codexinfo/panel.html`。
- `resources/read` 返回单文件 HTML，MIME 为 `text/html;profile=mcp-app`；同时兼容 `text/html+skybridge`。
- MCP server 只读白名单输入路径，只写自身缓存目录（`mcp-snapshot.json` 等）；不接受工具传入任意文件路径。

skill `codex-usage`：

- 触发词：额度、用量、重置卡、重置追踪、tok/s、输出速度、降智、模型状态。
- 行为：先调 `get_usage_snapshot`，用三行以内摘要回答；需要完整面板时调 `show_usage_panel` 或 `open_dashboard`。
- 不猜测额度；不把四源消息说成个人额度恢复。

本地 marketplace：

- 仓库根 `.agents/plugins/marketplace.json` 指向 `./plugins/codexinfo`。
- 用户配置：
  `[marketplaces.codexinfo] source_type="local" source="/Users/laoer/Documents/CodexInfo"`，
  `[plugins."codexinfo@codexinfo"] enabled=true`。
- 安装脚本默认只打印这两行；`--write-config` 才写入，并先备份。

### 6.6 构建、签名与安装

- `scripts/build-web.sh`：Vite 单文件构建 + 生成 `WebAssets.swift`。
- `scripts/build-app.sh`：`swift build -c release`，组装 `dist/CodexInfo.app`，写 `Info.plist`，ad-hoc 签名。
- `scripts/install-plugin.sh`：构建 `codexinfo-mcp`，复制到 `plugins/codexinfo/bin/`，生成绝对路径 `.mcp.json`，打印配置步骤。
- `scripts/dev.sh`：启动 Vite dev server + mock bridge + App（debug），用于 UI 迭代。
- `Info.plist`：`LSUIElement=true`、`CFBundleURLTypes=codexinfo`、`LSMinimumSystemVersion=14.0`。
- 本地开发使用 ad-hoc 签名；分发公证放到后续版本。
- App 非沙盒运行，直接读用户主目录下的 `~/.codex`；不申请 Full Disk Access，除非系统实际拦截。

### 6.7 失败与降级矩阵

| 失败 | 行为 |
| --- | --- |
| MCP App 本地不可渲染 | 插件返回三行摘要 + `open_dashboard`；菜单栏面板不受影响 |
| auth.json 缺失/401 | 提示重新登录；额度回落 app-server/会话；重置卡显示 `—` |
| app-server 启动失败 | 回落到官方接口或会话 `rate_limits` |
| 会话日志损坏/字段缺失 | 跳过坏行；未知事件忽略；不影响其他指标 |
| 单源超时/429/HTML 变更 | 该源降级，其余源继续；`x/4` 与最后成功时间 |
| 快照过期 | 保留旧值并标“数据可能过期” |
| WKWebView 崩溃 | 重新加载面板并重取快照 |
| 菜单栏 App 未安装/未运行 | `open_dashboard` 返回安装/启动提示；插件摘要仍可用 |
| MCP server 退出 | Codex 侧提示插件不可用；菜单栏继续运行 |

### 6.8 安全边界

- 凭证：token 只在内存；不写日志、缓存、快照、UI；错误信息不回显 token。
- 进程：只启动固定路径的 Codex CLI；参数数组，不拼 shell；设置源 URL 只接受 `http/https`。
- 文件：运行时只读 `~/.codex/sessions`、`~/.codex/auth.json`；只写 App Support 下的自身目录。安装脚本仅在显式 `--write-config` 时写 `~/.codex/config.toml`，并先备份。
- 网络：只访问白名单；UI 侧 `connect-src 'none'`。
- 工具：MCP tools 不接受任意路径、不执行用户命令。
- 日志：只记录计数、耗时、错误类型；不记录正文、token、URL query 中的敏感值。

## 7. 测试与验收

### 7.1 单元测试

- 额度：槽位互换、300/10080 分桶、`limit_id` 过滤、`used_percent` 边界、`resets_at` 缺失。
- 重置卡：排序、过期过滤、<72h/<24h 阈值、ID 脱敏。
- 会话：活动/空闲、响应去重、工具耗时、缺失 `task_complete`、`compacted`、超大数值。
- 速率：合成一轮已知 token/时长，断言 tok/s 误差 ≤0.1；分母异常丢弃。
- 降智：正常、单信号、双信号、路由降档、基线不足、MAD=0 六组。
- 四源：字段缺失、重复事件、时区、跨源确认、单源、超时/429/HTML 变更。
- 脱敏：假 auth 注入，断言日志/快照/缓存无 token。

### 7.2 契约与集成测试

- 官方接口用 `URLProtocol` mock：路径、query、Authorization、401 重读一次、429 退避。
- app-server 假进程：`initialize` → `account/rateLimits/read` 成功/超时/退出；stdout 不污染。
- MCP 脚本化客户端：`initialize`、`tools/list`、`resources/read`、`tools/call`；验证 `_meta` 三字段与 MIME。
- 插件冒烟：本地 marketplace 安装 → 插件可见 → `show_usage_panel` 渲染 → `get_usage_snapshot` 有数据 → `open_dashboard` 唤起。

### 7.3 UI 与视觉

- 同一份单文件 HTML 用 mock bridge 在浏览器跑 Playwright/Chrome DevTools。
- 340×780，浅色/深色；四态模型、无重置卡、源 2/4、过期、登录失效、生成中/空闲。
- 截图基线入库；不写真实账号数据。
- 键盘可达、焦点可见、对比度达标。

### 7.4 手动验收

1. 菜单栏出现 `84% · 42 tok/s · 正常`，点击开合面板。
2. 周额度/重置卡与 Codex 官方用量页一致（≤1 个百分点、卡数一致）。
3. 完成一轮后，tok/s 与手算一致；生成中不伪造实时值。
4. 制造基线不足/速率下降，分别显示“数据不足/疑似降智”，证据可复核。
5. 四源 `x/4`，确认记录能打开原始出处；单源失败不拖垮其余源。
6. 退出 Codex 后额度回落会话快照；删除 auth 后提示登录且不崩溃。
7. 日志、缓存、快照、UI 中检索不到 token；除白名单外无网络请求。

### 7.5 性能与 CI

- 冷启动面板 ≤2s（有快照）；会话冷索引 ≤10s；增量 ≤100ms；常驻内存 ≤150MB。
- GitHub Actions `macos-14`：`swift test` + Web build + MCP 契约测试；视觉快照仅本地。
- 完成定义：命令全部通过并贴输出；手动验收 1–7 逐项打勾。

## 8. 里程碑

| 里程碑 | 交付 | 验收门槛 | 估算 |
| --- | --- | --- | --- |
| M0 可行性冒烟 | 最小本地插件 + MCP App 渲染；官方接口/凭证；app-server；WKWebView 壳 | 面板能渲染；接口字段实测；失败有降级结论 | 0.5–1 天 |
| M1 核心与菜单栏 | Core + 额度/重置卡/会话/速率 + 菜单栏面板 | 真实数据；单测；截图基线 | 2–3 天 |
| M2 插件 | MCP tools + MCP App + skill + 安装脚本 | 插件可见、面板渲染、唤起菜单栏 | 1–2 天 |
| M3 降智 | 基线引擎 + 模型状态 UI | 四态与证据；合成样本回归 | 1–2 天 |
| M4 重置追踪 | 四源 + 健康 + 通知 | `x/4`、确认记录、通知、免责声明 | 2 天 |
| M5 收口 | 设置、深色、开机启动、打包、文档 | 全量手动验收 | 1 天 |

M0 是硬门槛：若本地插件无法渲染 MCP App，立即切“插件文本摘要 + 菜单栏主面板”，不回退到注入客户端。

## 9. 风险

| 风险 | 影响 | 对策 |
| --- | --- | --- |
| 本地插件不支持 MCP App | 插件内无完整面板 | M0 验证；降级为摘要 + 唤起菜单栏 |
| Codex 更新改插件协议 | 插件失效 | manifest 最小化；集成测试；可读错误 |
| 会话 schema 变化 | 速率/降智失真 | 容忍缺失；未知事件忽略；fixture 回归 |
| 大日志性能 | 启动慢/内存高 | 增量索引；预算；后台解析 |
| 四源脆弱/限流 | 追踪不完整 | API 优先；单源隔离；退避；URL 可配置 |
| 降智误判 | 误导用户 | 保守阈值；最少 8 轮；“疑似”措辞；证据行 |
| 凭证泄露 | 安全事件 | 内存驻留；脱敏；白名单；发布前审计 |
| 菜单栏与插件不一致 | 信任受损 | 共用 Core/快照/HTML |
| 全局重置误读 | 决策错误 | 倒计时只取官方 `resets_at`；免责声明 |
| 签名/公证 | 分发受阻 | 先 ad-hoc；后续 Developer ID + 公证 |

## 10. 证据与参考

本机已核实：

- 插件结构：`/Users/laoer/Library/Application Support/Codex/executor-plugins/codex-app-tools/.codex-plugin/plugin.json:1`、`.mcp.json:1`；包含 `mcpServers`、`skills`、绝对路径 `command`、`cwd`。
- 本地 marketplace：`/Users/laoer/.codex/.tmp/bundled-marketplaces/openai-bundled/.agents/plugins/marketplace.json:1`；`source.source=local`、`path=./plugins/...`。
- 本地 marketplace 配置：`/Users/laoer/.codex/config.toml:219` 起 `[marketplaces.openai-bundled] source_type="local"`；插件启停见 `config.toml:60` 起。
- Codex CLI 路径：`/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`。
- app-server 启动参数：`app-server --listen stdio://`；方法与 `account/rateLimits/read`、`account/read`。
- MCP Apps：Codex `app.asar` 内含 `ui://`、`text/html;profile=mcp-app`、`text/html+skybridge`、`_meta.ui.resourceUri`、`openai/outputTemplate`（二进制字符串检索确认，无行号）。
- 官方接口：
  - `GET https://chatgpt.com/backend-api/wham/usage`
  - `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`
  - `GET https://chatgpt.com/backend-api/wham/usage/daily-token-usage-breakdown`
  - `GET https://chatgpt.com/backend-api/wham/usage/plan_limit_history?days=7`
- 会话日志：`~/.codex/sessions/**/rollout-*.jsonl`；事件 `turn_context`、`thread_settings_applied`、`token_usage_record`、`task_started`、`task_complete`、`token_count`、`item_completed`、`compacted`；`item_completed.item.type` 实测为 `Reasoning`、`AgentMessage`、`CommandExecution`、`McpToolCall`、`FileChange`、`Extension`、`ContextCompaction` 等。
- 四源：`https://codexradar.com/current.json`、`https://codexradar.com/feed.xml`、`https://codex-reset.com/api/feed`、`https://codex-reset.com/api/status`、`https://status.openai.com/api/v2/summary.json`。
- 参考实现：`github.com/WineChord/codex-radar`（MIT）；仅参考额度读取、app-server 启动、状态栏组织方式，不整段照搬。

设计对照稿位于本地 `.superpowers/brainstorm/`（已 gitignore），不提交真实账号数据。

## 11. 决策记录

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D1 | Codex 插件 + macOS 菜单栏双入口 | 插件不能注入底部 chip；菜单栏承担常驻 |
| D2 | Swift 原生：SwiftPM + SwiftUI/NSStatusItem + WKWebView + Swift MCP | 用户选择原生/轻量；共用 Core 保证口径 |
| D3 | B 版“截图保真”布局 | 保留截图原有节奏；新增信息靠后 |
| D4 | 降智只做本地基线 | 可复核、不依赖社区黑盒；避免双重口径 |
| D5 | 四源追踪，≥2 重置类来源交叉确认 | 降低单源误报；官方状态只作旁证 |
| D6 | 允许直读 auth.json，仅内存驻留 | 账号统计与重置卡需要官方接口；用户明确允许 |
| D7 | 不做自动用卡/购买/注入 | 风险高、不可逆；本期只读 |
| D8 | M0 先验 MCP App，失败即降级 | 插件宿主能力是最大不确定性 |

## 12. 附录 A：快照 JSON

```json
{
  "generatedAt": "2026-10-24T14:20:39+08:00",
  "freshness": { "quota": "fresh", "session": "fresh", "account": "fresh", "sources": "fresh" },
  "quota": {
    "planType": "pro",
    "weeklyRemainingPercent": 84,
    "weeklyResetsAt": "2026-10-26T11:03:00+08:00",
    "source": "official"
  },
  "resetCredits": {
    "availableCount": 1,
    "items": [
      { "idSuffix": "a1b2c3", "status": "available", "expiresAt": "2026-11-07T07:55:00+08:00", "title": "Full reset" }
    ]
  },
  "session": {
    "isActive": true,
    "label": "当前会话",
    "model": "gpt-6.1-sol",
    "effort": "xhigh",
    "serviceTier": "default",
    "contextTokens": 147000,
    "contextWindow": 475000,
    "totalTokens": 1240000,
    "inputTokens": 1180000,
    "outputTokens": 58300,
    "cachedInputTokens": 1020000,
    "reasoningOutputTokens": 7000,
    "outputTokensPerSecond": 42.3,
    "medianOutputTokensPerSecond": 45.1,
    "ttftMs": 3900
  },
  "account": { "todayTokens": 1800000, "totalTokens": 3300000000, "source": "official", "updatedAt": "2026-10-24T14:20:39+08:00" },
  "health": {
    "status": "normal",
    "baselineWindowDays": 7,
    "sampleTurns": 12,
    "model": "gpt-6.1-sol",
    "effort": "xhigh",
    "signals": [],
    "disclaimer": "基于本机近 7 天基线，不代表官方结论"
  },
  "resetRadar": {
    "sourcesAvailable": 3,
    "sourcesTotal": 4,
    "lastScanAt": "2026-10-24T14:20:51+08:00",
    "nextScanAt": "2026-10-24T14:21:51+08:00",
    "latestConfirmed": {
      "title": "第 13 天额度重置完成",
      "summary": "覆盖所有付费用户",
      "publishedAt": "2026-10-18T05:12:00+08:00",
      "verified": true,
      "confirmingSources": ["AI 哨兵记录", "AI 哨兵信号", "Codex Resets"],
      "scope": "所有付费用户",
      "url": "https://codex-reset.com/zh/radar"
    }
  }
}
```

## 13. 附录 B：MCP tools

| tool | 输入 | 输出 |
| --- | --- | --- |
| `get_usage_snapshot` | `{ "refresh"?: boolean }` | 快照 JSON（同附录 A） |
| `get_model_health` | `{ "windowDays"?: 7 }` | 结论、证据、基线元数据 |
| `scan_reset_sources` | `{ "sourceIds"?: string[] }` | 每源健康、最近记录、下次扫描 |
| `show_usage_panel` | 无 | UI 资源 + 三行摘要 |
| `open_dashboard` | 无 | `opened` / 错误 |

`show_usage_panel` 的工具 `_meta`：

```json
{
  "ui": { "resourceUri": "ui://codexinfo/panel.html" },
  "ui/resourceUri": "ui://codexinfo/panel.html",
  "openai/outputTemplate": "ui://codexinfo/panel.html"
}
```

UI 资源：

- URI：`ui://codexinfo/panel.html`
- MIME：`text/html;profile=mcp-app`
- 兼容 MIME：`text/html+skybridge`
- 内容：单文件 HTML（React 构建，内联 JS/CSS），无外部网络请求。
