Studio action scripts
=====================

Small, focused helpers to send JSON-RPC requests to the running MCP server and exercise common Studio actions.

Layout
- bin/: small reusable caller (for portability)
- actions/: single-purpose scripts (open_session, read_tree, etc.)

Examples
- Run the open session action:
  powershell -NoProfile -File studio_action_scripts\actions\open_session.ps1

Common flows
- Export a snapshot to file:
  powershell -NoProfile -File studio_action_scripts\actions\snapshot_export.ps1 -SessionId "sess:..." -OutFile exported_snapshot.json
- Import a snapshot (server-side import with progress polling):
  powershell -NoProfile -File studio_action_scripts\actions\snapshot_import.ps1 -SessionId "sess:..." -InFile exported_snapshot.json

CLI helper
- The Node CLI under `studio_action_scripts/cli` exposes helpful commands (`health`, `list`, `open-session`, `read-tree`, `snapshot-export`, `snapshot-import`, `ws-tail`). Run:
  node studio_action_scripts/cli/index.js health

Notes
- The MCP server now returns some tool payloads wrapped in `structuredContent`; the action scripts and CLI unwrap this automatically.
- The server also emits import progress events on a WebSocket push stream at `ws://127.0.0.1:44877/mcp-stream`. The CLI `ws-tail` connects to that endpoint. Plugins that cannot use WebSocket can poll `roblox.importProgress` via `tools/call`.
