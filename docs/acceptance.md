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
SUMMARY ran=148 failed=0
==> Web build
...
Generated .../Sources/CodexInfoCore/Generated/WebAssets.swift
==> Release build of the MCP server
Build complete!
==> MCP smoke
MCP smoke OK
==> Playwright suite
  22 passed (3.6s)
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

## 2. The seven manual checks

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
import json, pathlib
home = pathlib.Path.home()
auth = json.loads((home / ".codex/auth.json").read_text())
tokens = auth.get("tokens") or {}
candidates = [auth.get("access_token"), auth.get("accessToken"),
              tokens.get("access_token"), tokens.get("accessToken")]
token = next((c for c in candidates if isinstance(c, str) and c), "")
print("token found:", bool(token), "length:", len(token))
roots = [home / "Library/Application Support/CodexInfo", home / "Library/Logs/CodexInfo"]
hits = []
for root in roots:
    if not root.exists():
        continue
    for path in root.rglob("*"):
        if path.is_file() and token and token in path.read_text(errors="ignore"):
            hits.append(str(path))
print("files that carry the token:", hits or "none")
PY
```

The hosts the app talks to, while it runs:

```bash
lsof -nP -a -p "$(pgrep -x CodexInfoApp)" -iTCP 2>/dev/null | awk 'NR>1 {print $9}' | sort -u
grep -rho 'https://[a-zA-Z0-9./_-]*' Sources/CodexInfoCore Sources/CodexInfoLive | sort -u
```

Expected:

- `files that carry the token: none`.
- Only the whitelisted hosts appear: `chatgpt.com`, `codexradar.com`,
  `codex-reset.com` and `status.openai.com`. When the system routes the
  traffic through a local proxy (for example `127.0.0.1:7890`), the first
  command shows the proxy instead of the hosts; the second command then has
  to list nothing but the four hosts above.

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
| A. Install the Codex plugin | **USER GATE** | | | |
| B. The MCP App in Codex | **USER GATE** | | | |
| Performance | manual | | | |
