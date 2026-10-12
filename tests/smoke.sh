#!/bin/bash
# End-to-end test against a fixture database: starts an agent, talks MCP to it through `mcp`.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=.build/debug/dayone-unlocked
TMP=$(mktemp -d); trap 'kill $AGENT 2>/dev/null; wait $AGENT 2>/dev/null; rm -rf "$TMP"' EXIT
sqlite3 "$TMP/fixture.sqlite" < tests/make-fixture.sql
export DAYONE_UNLOCKED_DB="$TMP/fixture.sqlite" DAYONE_UNLOCKED_SOCKET="$TMP/agent.sock" DAYONE_UNLOCKED_SKIP_AUTH=1
"$BIN" agent 2>"$TMP/agent.log" & AGENT=$!
for _ in $(seq 50); do [ -S "$TMP/agent.sock" ] && break; sleep 0.1; done

call() { printf '%s\n' "$@" | "$BIN" mcp; }
call '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
     '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
     '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
     '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_journals","arguments":{}}}' \
     '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search_entries","arguments":{"query":"hiking"}}}' \
     '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_entries","arguments":{"tag":"outdoors","order":"oldest"}}}' \
     '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"on_this_day","arguments":{"date":"10-12","max_chars":5}}}' \
     '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_entries","arguments":{"start_date":"2026-01-01","end_date":"2026-03-01"}}}' \
     '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"search_entries","arguments":{"query":"100%"}}}' \
     '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_entry","arguments":{"id":"aaa2"}}}' \
     '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"list_tags","arguments":{}}}' \
     '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"get_entries","arguments":{"start_date":"bad"}}}' \
     '{"jsonrpc":"2.0","id":12,"method":"nope"}'
