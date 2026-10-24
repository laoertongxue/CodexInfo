---
name: codex-usage
description: Use when the user asks about Codex quota, weekly usage, reset cards, reset radar, output tokens per second, or whether the model seems degraded. Calls CodexInfo MCP tools and summarizes.
---

# CodexInfo

- For quota, reset cards, reset radar, tok/s or model health, call `get_usage_snapshot` first and answer from its result.
- Answer in at most three lines: weekly remaining, output rate, model status.
- For detailed evidence, call `get_model_health` and show the `signals` rows.
- For a full panel, call `show_usage_panel`; to open the menu-bar panel, call `open_dashboard`.
- Never claim a global reset recovered the user's personal quota; only `quota.weeklyResetsAt` drives the countdown.
