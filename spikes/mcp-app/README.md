# M0 result

- Date: 2026-10-24
- Host: Codex desktop (version to be recorded by the user at the gate)
- Result: **PENDING USER GATE** — local protocol check passes; host rendering has NOT yet been observed.
- Spike root (absolute): `/Users/laoer/Documents/CodexInfo/.worktrees/codexinfo-implementation/spikes/mcp-app`
- Tool name: `show_spike_panel`
- Resource URI: `ui://codexinfo-spike/panel.html` (`text/html;profile=mcp-app`)

This is a throwaway feasibility spike. It must not be imported into `Sources/`, and no part of
it is production code. The only open question is whether the current Codex desktop host renders
an MCP App (`ui://` resource with `text/html;profile=mcp-app`) in an iframe.

## What was verified locally (no Codex involved)

Command run from the worktree root:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"ui://codexinfo-spike/panel.html"}}' \
  | node spikes/mcp-app/server.mjs
```

Observed: three JSON-RPC lines. `initialize` returns protocol `2025-06-18`; `tools/list` includes
`show_spike_panel` with `_meta.ui.resourceUri`; `resources/read` returns the HTML with
`mimeType: text/html;profile=mcp-app` and the text `CodexInfo MCP App OK`.
`resources/list`, `tools/call`, `ping`, and unknown-tool/unknown-resource errors were also
checked and behave as specified.

Local protocol is correct. **Host rendering is unverified.**

## Manual verification steps (user)

Do these only when you choose to run the external gate. They modify Codex configuration and
install a plugin; the implementer did not perform them.

1. Note the current Codex desktop build version (record it in this file if the gate passes).
2. Register the local marketplace rooted at this worktree's spike directory. Either:
   - In Codex plugin settings, add a local marketplace at
     `/Users/laoer/Documents/CodexInfo/.worktrees/codexinfo-implementation/spikes/mcp-app`,
     install `codexinfo-spike`, and enable it; or
   - Add the TOML below to `~/.codex/config.toml` and restart Codex.
3. Start a new Codex session and ask the model to call `show_spike_panel`
   (for example: "call the show_spike_panel tool").
4. Observe the rendered panel.

### Config block 1 — local marketplace

```toml
[marketplaces.codexinfo-spike]
source_type = "local"
source = "/Users/laoer/Documents/CodexInfo/.worktrees/codexinfo-implementation/spikes/mcp-app"
```

### Config block 2 — enable the plugin

```toml
[plugins."codexinfo-spike@codexinfo-spike"]
enabled = true
```

The spike's `.mcp.json` already points at the absolute paths in this worktree:

- `command`: `/opt/homebrew/bin/node` (value of `which node` on this machine)
- `args[0]`: `/Users/laoer/Documents/CodexInfo/.worktrees/codexinfo-implementation/spikes/mcp-app/server.mjs`
- `cwd`: `/Users/laoer/Documents/CodexInfo/.worktrees/codexinfo-implementation/spikes/mcp-app`

## What the user should observe

- PASS: the tool result is rendered as an iframe/panel showing the heading
  `CodexInfo MCP App OK` and the sentence
  "If you can read this inside Codex, the host renders MCP Apps."
- FAIL: the tool runs and returns text but no `ui://` panel/iframe is rendered, or the plugin
  cannot load the server (check that `node` starts the server and that Codex was restarted).

## Recording the gate

After observing the host, replace the result line above with one of:

- `PASS` — tool list `resourceUri` rendered in the MCP App iframe. Record the Codex build version
  and the exact observation.
- `FAIL` — tool ran but the host did not render `ui://`. Fallback: plugin returns a text summary
  plus `open_dashboard`; the menu bar panel is primary.

Until the user records the observation, M0 remains **PENDING USER GATE**; Task 17's MCP App UI
must not be started on the assumption that it passed.
