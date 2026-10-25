# CodexInfo acceptance checklist

The checklist closes the project: one automated gate and the manual checks of
the design spec (`docs/superpowers/specs/2026-10-24-codexinfo-design.md`,
section 7.4).

Every check is marked:

| Mark | Meaning |
| --- | --- |
| **automated** | Runs in `bash scripts/test.sh` and in the CI workflow. No account, no network. |
| **manual** | A person does it on a machine with a real account. The numbers cannot be produced in CI. |
| **USER GATE** | A person has to act inside Codex or edit `~/.codex/config.toml`. No script does it for them. |

The scripts never write `~/.codex/config.toml` and never read a real token
into a file. They only print the instructions.

Prerequisites on the machine: the Xcode Command Line Tools (`swift`), Node
24 with pnpm 10, `python3` and macOS 14 or newer for the app bundle. Every
command is run from the root of the repository.

---

## 0. The automated gate

```bash
bash scripts/test.sh
```

Expected output, in this order:

```
==> Swift suite
...
SUMMARY ran=186 failed=0
==> Web build
...
Generated .../Sources/CodexInfoCore/Generated/WebAssets.swift
==> Release build of the MCP server
Build complete!
==> MCP smoke
MCP smoke OK
==> Playwright suite
  27 passed (5.2s)
GATE OK
```

The script exits with `0` only when every step passed. The same steps run in
`.github/workflows/ci.yml` on `macos-14`.

## 1. Build the app bundle

```bash
bash scripts/build-app.sh
codesign --verify --deep --strict dist/CodexInfo.app && echo "signed"
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" dist/CodexInfo.app/Contents/Info.plist
```

Expected:

- `dist/CodexInfo.app` exists with `Contents/MacOS/CodexInfoApp` and
  `Contents/MacOS/codexinfo-mcp`.
- `codesign` prints `signed` (the bundle is signed ad-hoc).
- `PlistBuddy` prints the `codexinfo` scheme. The bundle also carries
  `LSUIElement` (accessory app, no Dock icon), `CFBundleIdentifier`
  `com.laoer.codexinfo`, `CFBundleShortVersionString` `0.1.0` and
  `LSMinimumSystemVersion` `14.0`.

---

## 2. The nine manual checks

The numbers of the checks come from a real account, so they are **manual**.

### Check 1 — Menu bar label and the panel

*Spec: 菜单栏出现 `84% · 42 tok/s · 正常`，点击开合面板。*

```bash
open dist/CodexInfo.app
pgrep -fl CodexInfoApp
ls -t ~/Library/Logs/DiagnosticReports/CodexInfoApp-*.ips 2>/dev/null | head -1
```

Expected:

- The menu bar carries the item with the quota, the rate and the model
  status (`84% · 42 tok/s · 正常` in the spec; the real numbers of the
  account).
- A left click opens the panel (340 x 780), a second click closes it.
- The panel shows the header, the quota, the reset cards, the reset radar,
  the model health, the current session with the rate, the account stats and
  the footer, in the order of the B layout.
- The process stays alive and the newest crash report is older than the
  start of the run.

### Check 2 — Quota and reset cards against the official page

*Spec: 周额度/重置卡与 Codex 官方用量页一致（≤1 个百分点、卡数一致）。*

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / "Library/Application Support/CodexInfo/snapshot.json"
d = json.loads(p.read_text())
print("quota:", d["quota"])
print("reset cards:", d["resetCredits"]["availableCount"], d["resetCredits"]["items"])
PY
```

Open the official usage page of the account in the browser and compare it
with the printed numbers.

Expected: the weekly remaining percentage is within one percentage point of
the official page and the number of reset cards is the same.

### Check 3 — The rate of a finished turn

*Spec: 完成一轮后，tok/s 与手算一致；生成中不伪造实时值。*

Run a turn in Codex, let it finish, then compute the rate by hand from the
session log:

```bash
LOG=$(find ~/.codex/sessions -name 'rollout-*.jsonl' -type f -print0 | xargs -0 ls -t | head -1)
python3 - "$LOG" <<'PY'
import json, sys
turns = {}
for line in open(sys.argv[1], encoding="utf-8", errors="ignore"):
    try:
        root = json.loads(line)
    except ValueError:
        continue
    payload = root.get("payload") or {}
    turn_id = payload.get("turn_id")
    if root.get("type") == "token_usage_record":
        usage = payload.get("usage") or {}
        turn = turns.setdefault(turn_id, {"out": 0})
        turn["out"] += usage.get("output_tokens", 0)
    if root.get("type") == "event_msg" and payload.get("type") == "task_complete":
        turn = turns.setdefault(turn_id, {"out": 0})
        turn["done"] = True
        turn["duration_ms"] = payload.get("duration_ms")
        turn["ttft_ms"] = payload.get("time_to_first_token_ms") or 0
for turn_id, turn in turns.items():
    if not turn.get("done"):
        continue
    net = max((turn["duration_ms"] or 0) - turn["ttft_ms"], 1) / 1000
    print(turn_id, turn["out"], "output tokens,", round(turn["out"] / net, 1), "tok/s")
PY
```

Expected:

- The printed rate matches the rate of the panel (`输出速率`) within the
  rounding of the panel.
- While a turn is still running, the panel shows no live rate instead of a
  made up one.

### Check 4 — Insufficient baseline and suspected degradation

*Spec: 制造基线不足/速率下降，分别显示"数据不足/疑似降智"，证据可复核。*

The states of the panel are covered by the fixtures of the web app:

```bash
bash scripts/dev.sh
# open http://127.0.0.1:5173/?fixture=suspected
```

Expected:

- `?fixture=suspected` shows `疑似降智` with the evidence rows expanded
  (`当前 33.1 / 基线 45.1 tok/s`).
- The native panel shows `数据不足` when the local baseline has fewer turns
  than the minimum of the settings (8 by default):

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / "Library/Application Support/CodexInfo/snapshot.json"
print(json.loads(p.read_text())["health"])
PY
```

- The evidence is reproducible: the sample turns, the window and the two rates
  are printed, and the disclaimer `基于本机近 7 天基线，不代表官方结论` is
  shown.

### Check 5 — The four reset sources

*Spec: 四源 `x/4`，确认记录能打开原始出处；单源失败不拖垮其余源。*

```bash
python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / "Library/Application Support/CodexInfo/snapshot.json"
radar = json.loads(p.read_text())["resetRadar"]
for source in radar["sources"]:
    print(source["sourceName"], source["state"], source.get("lastSuccessAt"))
print("available:", sum(1 for s in radar["sources"] if s["state"] != "down"), "/", len(radar["sources"]))
PY
```

Expected:

- The panel shows `x/4 来源可用` for the four sources (`AI 哨兵记录`,
  `AI 哨兵信号`, `Codex Resets`, `官方状态`).
- A confirmed record opens its origin (`查看原始出处`).
- A source that fails shows `源不可用` for that source only; the other three
  keep their state and the confirmed records stay.

### Check 6 — A missing `auth.json`

*Spec: 退出 Codex 后额度回落会话快照；删除 auth 后提示登录且不崩溃。*

```bash
mv ~/.codex/auth.json ~/.codex/auth.json.bak
# wait for the next refresh of the panel (60 s) or press 刷新 in the panel
mv ~/.codex/auth.json.bak ~/.codex/auth.json
```

Expected:

- The panel shows the re-login hint, the app does not crash and the process
  stays alive (`pgrep -fl CodexInfoApp`).
- The quota falls back to the app-server or the session snapshot and the
  reset cards show `—`.
- After the file is back, the next refresh restores the official numbers.

### Check 7 — No token in the logs, the caches, the snapshot or the UI

*Spec: 日志、缓存、快照、UI 中检索不到 token；除白名单外无网络请求。*

The search prints the names of the files only; the token itself is never
written to the terminal or to a file:

```bash
python3 - <<'PY'
import json, pathlib, re
home = pathlib.Path.home()
tokens = []
auth = json.loads((home / ".codex/auth.json").read_text())
for key in ("access_token", "accessToken"):
    if isinstance(auth.get(key), str):
        tokens.append(auth[key])
for key, value in (auth.get("tokens") or {}).items():
    if key.lower().endswith("token") and isinstance(value, str):
        tokens.append(value)
creds = home / ".dsh/.credentials.yaml"
if creds.exists():
    match = re.search(r"deepseek-account-platform/default:\s*\n(?:.*\n)*?\s*token:\s*(\S+)", creds.read_text())
    if match:
        tokens.append(match.group(1).strip("'\""))
mini_auth = home / ".minimax/auth/prod/cn/mcode-public/auth.json"
if mini_auth.exists():
    records = json.loads(mini_auth.read_text()).get("records", {})
    for key, record in records.items():
        if "mcode.oauth" in key and isinstance(record, dict) and record.get("accessToken"):
            tokens.append(record["accessToken"])
print("tokens found:", len(tokens))
roots = [home / "Library/Application Support/CodexInfo", home / "Library/Logs/CodexInfo"]
hits = []
for root in roots:
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if path.is_file() and any(token in path.read_text(errors="ignore") for token in tokens):
            hits.append(str(path))
print("files that carry a token:", hits or "none")
PY
```

The hosts the app talks to, while it runs:

```bash
lsof -nP -a -p "$(pgrep -x CodexInfoApp)" -iTCP 2>/dev/null | awk 'NR>1 {print $9}' | sort -u
grep -rho 'https://[a-zA-Z0-9./_-]*' Sources/CodexInfoCore Sources/CodexInfoLive | sort -u
```

Expected:

- `files that carry a token: none` (Codex, DeepSeek and MiniMax tokens are checked).
- Only the whitelisted hosts appear: `chatgpt.com`, `codexradar.com`,
  `codex-reset.com`, `status.openai.com`, `platform.deepseek.com` and
  `www.minimaxi.com`. When the system routes the traffic through a local
  proxy (for example `127.0.0.1:7890`), the first command shows the proxy
  instead of the hosts; the second command then lists only those six hosts.
- A token-bearing client never follows a redirect to another source: the
  official, DeepSeek and MiniMax clients each pin their own `SourceHosts`
  set, and the host-set unit test covers the four sets.

---

### Check 8 — The overlay in the four clients

*Spec: 4.1.1.*

The overlay is on by default. Bring each client to the front and check the
chip next to its native model selector:

Before the numbers, grant the precise anchor: 「设置 → 客户端贴片 → 授权…」,
allow CodexInfo in System Settings → Privacy & Security → Accessibility, then
restart CodexInfo. Without the permission, Codex / DeepSeek use the
calibrated window fallback; the Qoder and MiniMax badges are hidden (their
composers have no reliable window-only position) until the permission is granted.

| Client | Expected chip | Where the value comes from |
| --- | --- | --- |
| ChatGPT / Codex | `额度 71% · 会话 —` (or a rate while a turn runs) | the existing snapshot |
| Qoder | `额度 48% · 会话 —` | the last `[AccountUsage]` line of the Qoder log |
| MiniMax Code | `额度 93% · 会话 —` | `coding_plan/remains`, general model |
| DeepSeek Harness | `余额 ¥41.60 · 会话 —` | the platform wallet summary |

The numbers are examples. Also check:

1. The chip and the native model selector share the same horizontal center
   line; the selector's hover background stays fully visible, with a gap of
   about 14pt between the chip and the background.
2. Move or resize the client window, or open/close the Qoder file explorer:
   the chip follows within half a second.
3. Click the chip: the menu bar panel opens on the matching client tab; the
   client composer does not receive the click.
4. Turn 「设置 → 客户端贴片」 off: every chip disappears; turn it on: the
   chip of the frontmost client returns.
5. Bring another app to the front: no chip floats over it.
6. Qoder only refreshes when its own `main.log` receives a new usage line;
   the chip may keep the last value until then.

---

### Check 9 — The client switcher in the panel

*Spec: 4.1.2.*

Open the menu bar panel. The tabs `Codex / Qoder / MiniMax / DeepSeek` sit
under the header; the Codex tab is the full panel from Check 1. Switch the
tabs and check:

| Tab | Expected |
| --- | --- |
| Qoder | `套餐内 Credits 826 / 2,000`, `已使用 42%`, `剩余 1,174`, `2026/11/23 10:52 刷新`, `资源包 400 / 500`, `已使用 80%`, `剩余 100`, source `本地用量日志`; no model row |
| MiniMax | `5 小时限额 0 / 100`, `2026/10/25 15:00 重置`, `周限额 10 / 150`, `2026/10/26 00:00 重置`, `重置卡 3 张`（完全重置，带到期）, `MiniMax M3.1 Flash · 思考`, source `官方额度接口` |
| DeepSeek | `余额 ¥41.60`, `DeepSeek V4 Flash · Max`, source `官方钱包` |

The numbers are examples. Also check:

1. The footer of each client panel sits at the bottom of the popover; no
   empty space is left below it.
2. The MiniMax panel shows the 5-hour and weekly windows as used / total
   points, each with its own reset time and countdown; the reset-card section
   lists the three cards as `完全重置` with their expiry and countdown, and the
   panel never offers a use action.
3. 「刷新」and the 30-second refresh update both the Codex snapshot and the
   three client panels; the floating badge of the same client shows the same
   number.
4. The tabs are absent inside the Codex plugin (MCP mode shows only Codex).
5. The tab selection is kept while the panel page is loaded; a reload or an
   app restart returns to Codex.

---

## 3. USER GATE — Install the Codex plugin

**This step needs a person.** The script builds the plugin and prints the two
blocks; it never edits `~/.codex/config.toml`.

```bash
bash scripts/install-plugin.sh
```

The script prints:

```toml
[marketplaces.codexinfo]
source_type = "local"
source = "<the path of the repository>"
[plugins."codexinfo@codexinfo"]
enabled = true
```

Then, by hand:

1. Back up the configuration: `cp ~/.codex/config.toml ~/.codex/config.toml.bak`
2. Add the two printed blocks to `~/.codex/config.toml`.
3. Restart Codex.

Expected: `CodexInfo` appears in the plugin settings of Codex.

## 4. USER GATE — The MCP App in Codex

**This step needs a person.** The rendering of the MCP App can only be
checked inside Codex.

1. Ask `查看我的 Codex 用量`.
   The model calls `get_usage_snapshot` and answers in at most three lines.
2. Ask `打开用量面板`.
   - If the M0 gate passed, `show_usage_panel` renders the panel inside
     Codex.
   - If the M0 gate failed, the plugin answers with the text summary and
     `open_dashboard` opens the menu bar panel (`codexinfo://show`).
3. Ask `当前模型正常吗` and check that `get_model_health` answers with the
   verdict and the signals.

---

## 5. Performance

```bash
/usr/bin/time -lp open dist/CodexInfo.app
```

Expected: the app opens without a crash and the panel paints in at most two
seconds once a snapshot exists.

---

## 6. Sign-off

| Check | Kind | Result | Date | Name |
| --- | --- | --- | --- | --- |
| 0. Automated gate | automated | | | |
| 1. Build the bundle | automated | | | |
| 1. Menu bar and panel | manual | | | |
| 2. Quota and reset cards | manual | | | |
| 3. Rate of a finished turn | manual | | | |
| 4. Baseline and degradation | manual | | | |
| 5. The four reset sources | manual | | | |
| 6. A missing `auth.json` | manual | | | |
| 7. No token anywhere | manual | | | |
| 8. The overlay in four clients | manual | | | |
| 9. The client switcher | manual | | | |
| A. Install the Codex plugin | **USER GATE** | | | |
| B. The MCP App in Codex | **USER GATE** | | | |
| Performance | manual | | | |
