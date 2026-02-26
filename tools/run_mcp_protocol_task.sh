#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found in PATH" >&2
  exit 1
fi

cd "$WORKSPACE_DIR"

echo "Starting MCP server..."
cargo run -p mcp-server > /tmp/mcp-server.log 2>&1 &
SERVER_PID=$!

cleanup() {
  if kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    echo "Stopping MCP server..."
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

READY=false
for _ in $(seq 1 90); do
  if curl -sf "http://127.0.0.1:44877/health" >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 0.5
done

if [ "$READY" != "true" ]; then
  echo "MCP server did not become healthy in time." >&2
  exit 1
fi

echo "Server is healthy. Running protocol contract test..."
python3 "$SCRIPT_DIR/mcp_protocol_contract_test.py"

echo "Protocol contract task completed successfully."
