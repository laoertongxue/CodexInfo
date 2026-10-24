#!/usr/bin/env python3
"""Checks the MCP server over stdio.

The check needs neither the network nor a signed-in account: it only asks the
server for its handshake, for its tools and for the panel resource. The
standard output of the server must carry the protocol messages only, and the
server must exit with a clean status when the input ends.
"""
import json
import subprocess
import sys


def send(proc, message):
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()


def receive(proc):
    line = proc.stdout.readline()
    if not line:
        raise AssertionError("the server closed its output before the answer")
    return json.loads(line)


def main():
    if len(sys.argv) < 2:
        print("usage: mcp_smoke.py <path to codexinfo-mcp>", file=sys.stderr)
        return 2
    binary = sys.argv[1]
    proc = subprocess.Popen(
        [binary],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    try:
        send(proc, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        init = receive(proc)
        assert init["result"]["serverInfo"]["name"] == "codexinfo", init

        send(proc, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools = receive(proc)
        names = [tool["name"] for tool in tools["result"]["tools"]]
        for tool in ("get_usage_snapshot", "get_model_health", "show_usage_panel", "open_dashboard"):
            assert tool in names, tools

        send(
            proc,
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "resources/read",
                "params": {"uri": "ui://codexinfo/panel.html"},
            },
        )
        resource = receive(proc)
        assert resource["result"]["contents"][0]["mimeType"] == "text/html;profile=mcp-app", resource
    finally:
        proc.stdin.close()

    status = proc.wait(timeout=15)
    assert status == 0, f"the server exited with the status {status}"
    rest = proc.stdout.read()
    assert rest.strip() == "", f"the server wrote more than the protocol messages: {rest!r}"
    print("MCP smoke OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
