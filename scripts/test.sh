#!/usr/bin/env bash
# The one-command gate of the project.
#
# The gate runs the Swift suite, the web build, the release build of the MCP
# server, the MCP smoke against that binary and the Playwright suite against
# the built panel. Every step stops the gate when it fails.
#
# The gate never touches the Codex configuration and never reads a real
# account: the fixtures carry `tok_test` only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Swift suite"
swift run codexinfo-tests

echo "==> Web build"
bash "$ROOT/scripts/build-web.sh"

echo "==> Asset drift check"
# The generated asset is committed. When the web build changes it, the asset
# has to be regenerated and committed with the panel, so the shipped app never
# carries an outdated panel.
git diff --exit-code -- Sources/CodexInfoCore/Generated/WebAssets.swift

echo "==> Release build of the MCP server"
swift build -c release --product codexinfo-mcp
BIN="$(swift build -c release --show-bin-path)/codexinfo-mcp"

echo "==> MCP smoke"
python3 "$ROOT/scripts/mcp_smoke.py" "$BIN"

echo "==> Playwright suite"
# The suite starts its own preview server on the built artifact, so the
# single-file contract is what is tested.
pnpm --dir "$ROOT/Web" exec playwright install chromium
pnpm --dir "$ROOT/Web" exec playwright test

echo "GATE OK"
