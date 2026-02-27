Studio action scripts
=====================

Small, focused helpers to send JSON-RPC requests to the running MCP server and exercise common Studio actions.

Layout
- bin/: small reusable caller (for portability)
- actions/: single-purpose scripts (open_session, read_tree, etc.)

Examples
- Run the open session action:
  powershell -NoProfile -File studio_action_scripts\actions\open_session.ps1

Notes
- These scripts use the existing `tools/send_mcp_rpc.ps1` helper when available.
