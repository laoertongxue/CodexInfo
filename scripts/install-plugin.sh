#!/usr/bin/env bash
# Builds the MCP server and prepares the local plugin.
#
# The script never touches ~/.codex/config.toml: it prints the two blocks the
# user has to add, so the change of the configuration stays a decision of the
# user.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --product codexinfo-mcp
BIN="$ROOT/.build/release/codexinfo-mcp"
PLUGIN="$ROOT/plugins/codexinfo"
mkdir -p "$PLUGIN/bin"
cp "$BIN" "$PLUGIN/bin/codexinfo-mcp"
chmod +x "$PLUGIN/bin/codexinfo-mcp"
python3 - "$PLUGIN" <<'PY'
import json, pathlib, sys

plugin = pathlib.Path(sys.argv[1])
template = (plugin / ".mcp.json.template").read_text()
data = json.loads(template)
server = data["mcpServers"]["codexinfo"]
server["command"] = server["command"].replace(
    "__CODEXINFO_MCP_BINARY__", str(plugin / "bin" / "codexinfo-mcp")
)
server["cwd"] = server["cwd"].replace("__CODEXINFO_PLUGIN_DIR__", str(plugin))
(plugin / ".mcp.json").write_text(json.dumps(data, indent=2) + "\n")
PY
echo "Plugin ready: $PLUGIN"
echo "Add these lines to ~/.codex/config.toml (back up first):"
echo "[marketplaces.codexinfo]"
echo "source_type = \"local\""
echo "source = \"$ROOT\""
echo "[plugins.\"codexinfo@codexinfo\"]"
echo "enabled = true"
