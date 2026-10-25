# CodexInfo

[![CI](https://github.com/laoertongxue/CodexInfo/actions/workflows/ci.yml/badge.svg)](https://github.com/laoertongxue/CodexInfo/actions/workflows/ci.yml)

macOS 菜单栏里的 AI 编程客户端用量面板：把 **Codex、Qoder、MiniMax Code、DeepSeek Harness** 的额度、重置卡与输出速率集中到一处，并在各客户端输入区叠加一个只读、可点击的额度贴片。

不修改客户端包，不注入 DOM；贴片是独立浮窗。点击贴片会打开菜单栏面板并选中对应客户端。

[下载最新版](https://github.com/laoertongxue/CodexInfo/releases/latest) · [验收清单](docs/acceptance.md) · [架构评审](docs/architecture-review.md) · [设计文档](docs/superpowers/specs/2026-10-24-codexinfo-design.md) · [实现记录](docs/implementation-log.md)

## 功能

- **菜单栏常驻面板**：周额度、重置卡、本机周额度上次/下次重置（北京时间）、社区重置记录与预告、模型状态（本地降智判断）、当前会话 tok/s、账号 Token 统计。
- **四客户端切换**：Codex / Qoder / MiniMax / DeepSeek 四个标签，各自显示自己的额度口径。
- **只读悬浮贴片**：ChatGPT / Codex、Qoder、DeepSeek Harness、MiniMax Code 的输入区各显示自己的额度或余额；跟随原生模型选择器，点击打开对应面板。
- **分段额度**：
  - Qoder：套餐内 Credits 与资源包，已用 / 总数、已使用 %、剩余点数、套餐刷新时间。
  - MiniMax：5 小时限额与周限额、各自重置时间与倒计时、可用重置卡（只展示，不使用）。
  - DeepSeek：官方钱包余额（normal + bonus）。
  - Codex：官方 `/wham/usage`、会话日志与重置卡。
- **30 秒刷新**：Codex 快照与三个客户端并行读取；也可从面板或右键菜单手动刷新。
- **可选 Codex 插件**：在 Codex 会话里渲染同一块面板；插件不注入 Codex 的底部状态栏。

## 下载与安装

### 直接下载

1. 打开 [Releases](https://github.com/laoertongxue/CodexInfo/releases/latest)，下载 `CodexInfo-0.1.1-macos-arm64.zip` 和 `SHA256SUMS.txt`。
2. 解压，把 `CodexInfo.app` 拖到「应用程序」。
3. 首次打开：在 Finder 中右键 `CodexInfo.app` →「打开」。应用使用 ad-hoc 签名，未做 Apple 公证，因此不能双击直接打开。
4. 如果仍被 Gatekeeper 拦截，可清除隔离属性：

   ```bash
   xattr -dr com.apple.quarantine /Applications/CodexInfo.app
   open /Applications/CodexInfo.app
   ```

5. 菜单栏出现用量文字后，左键打开面板；在「设置」中打开「客户端贴片」，并按提示授予辅助功能权限（用于把贴片对齐到模型选择器）。

> 当前 Release 为 Apple Silicon（arm64）、macOS 14+ 构建。Intel Mac 请从源码构建。

### 安装 Codex 插件（可选）

菜单栏 App 可以独立使用。若要在 Codex 会话里也看到面板，需要从源码安装插件：

```bash
git clone https://github.com/laoertongxue/CodexInfo.git
cd CodexInfo
bash scripts/install-plugin.sh
```

脚本会构建 MCP server 并把两段配置打印出来。先备份 `~/.codex/config.toml`，再把脚本输出的配置加入该文件，然后重启 Codex：

```toml
[marketplaces.codexinfo]
source_type = "local"
source = "/path/to/CodexInfo"

[plugins."codexinfo@codexinfo"]
enabled = true
```

插件只读取 Codex 自己的用量接口与会话日志，不读取对话正文。

## 使用

- **左键**菜单栏图标：打开 / 关闭面板。
- **右键**菜单栏图标：刷新、扫描重置源、设置、开机启动、退出。
- **面板标签**：Codex / Qoder / MiniMax / DeepSeek；切换后底部高度随内容收缩。
- **贴片**：只在对应客户端位于前台时显示；点击打开面板并选中该客户端。Qoder / MiniMax 没有精确辅助功能锚点时会隐藏，避免遮挡模型选择器；Codex / DeepSeek 在未授权时使用窗口位置估算。
- **重置卡**：只展示张数、类型、到期时间与倒计时，不提供使用或购买操作。

## 数据来源

| 客户端 | 来源 | 显示 |
| --- | --- | --- |
| Codex | 官方 `/wham/usage`、重置卡接口、`~/.codex/sessions/**/*.jsonl` | 周额度、重置卡、tok/s、模型状态、账号 Token |
| Qoder | 本地 `main*.log` 中的 `[AccountUsage] 用量响应摘要` | 套餐内 Credits、资源包、已使用 %、剩余、刷新时间 |
| MiniMax Code | 官方 coding plan 与 reset card 接口（OAuth） | 5 小时 / 周限额、重置时间、重置卡 |
| DeepSeek Harness | 官方钱包接口（本地 grant） | 余额、模型 / 档位 |

社区重置源：CodexRadar、codex-reset.com、status.openai.com；至少两个重置类来源一致才标记为已确认。

重置追踪先显示**本机周额度窗口**：上次/下次重置按北京时间显示，重置后 1 小时内标「刚刚重置」。社区记录即使只有一个来源也会直接显示；最新预告会单独列出并保留原文，不再隐藏到折叠区里。雷达记录会从上一份快照恢复，来源暂时失败或只返回空页时不会清空最近重置。额度每 60 秒刷新、重置源每 60 秒扫描；在「设置 → 通知」中开启后，周额度重置前 15 分钟会发一次系统提醒。

## 隐私与安全

- 访问令牌只在内存中，只发往各自官方域（`chatgpt.com`、`platform.deepseek.com`、`www.minimaxi.com`）；不写日志、不落缓存、不写快照。
- 每个带令牌的 HTTP client 只允许自己的 host 集合，跨源重定向会被拒绝；所有请求带超时。
- Qoder 的凭证是加密的 Chromium 存储，**不读取**；只读它自己打印的用量日志。
- 不读取对话正文。辅助功能只读取控件角色、标签与 frame，用于贴片对齐。
- 重置卡只读展示，不自动使用、不自动购买。
- `docs/acceptance.md` 的 Check 7 提供本地扫描脚本，只打印命中文件名，不打印 token。

## 从源码构建

要求：macOS 14+、Xcode 16+（Swift 6）、Node.js 24、pnpm 10。

```bash
git clone https://github.com/laoertongxue/CodexInfo.git
cd CodexInfo
bash scripts/test.sh          # Swift + Web + MCP smoke + Playwright
bash scripts/build-app.sh     # 生成 dist/CodexInfo.app（ad-hoc 签名）
open dist/CodexInfo.app
```

安装插件：

```bash
bash scripts/install-plugin.sh
```

## 项目结构

```text
Sources/CodexInfoCore   # 模型、HTTP 白名单、快照与设置
Sources/CodexInfoLive   # 官方接口、会话日志、客户端额度 provider
Sources/CodexInfoApp    # 菜单栏、面板宿主、悬浮贴片、设置
Sources/CodexInfoMCP    # MCP server
Web/                    # React 单文件面板（Vite）
plugins/codexinfo/      # Codex 插件与 MCP 配置模板
docs/                   # 设计、验收与实现记录
scripts/                # 构建、测试与插件安装脚本
```

## 验证与已知限制

- 本地与 CI 使用同一套门禁：Swift 186 项测试、Playwright 27 项、tsc、MCP smoke、bundle 签名校验。
- Release 为 arm64 + ad-hoc 签名，未公证；Intel 需自行构建。
- Qoder 额度随它自己的用量日志刷新而更新，本项目不主动请求 Qoder 后端。
- 客户端 UI 更新可能改变辅助功能树；贴片定位依赖 AX 锚点，必要时需要重新校准。
- 面板里的重置卡与额度来自各客户端自己的账号；本项目不提供账号、额度或充值。

## 许可

仓库暂未附带 LICENSE 文件；如需复用代码，请先联系作者。
