# VS Code UX Extension MVP Spec (Click-first Adrablox Control)

Last updated: 2026-03-02

## Purpose

Provide a click-first UX inside VS Code for common Adrablox workflows so users do not need to run PowerShell scripts manually for day-to-day operations.

This extension wraps existing repository commands first (low-risk), then progressively moves to direct JSON-RPC where it improves reliability and speed.

## Design goals

1. One obvious entry point in VS Code.
2. One-click execution for common operations.
3. Visible status for Server, Session, Sync, and Live bridge.
4. Target selection in a Roblox tree view, reused by actions.
5. Clear error messages with actionable remediation.

## Non-goals (MVP)

- Replacing the MCP server protocol.
- Replacing Studio plugin logic.
- Implementing custom theming/complex animation.
- Full no-script backend rewrite in MVP.

## User journeys (MVP)

### Journey A: Quick Start

1. User opens Activity Bar → Adrablox.
2. Clicks `Start Server`.
3. Clicks `Open Session`.
4. Sees status chips: Server `Healthy`, Session `Active`.
5. Clicks `Read Tree` and sees Roblox hierarchy.

### Journey B: Targeted Action

1. User selects a node in the tree (`ModuleScript`, `Folder`, etc.).
2. Extension marks it as `Active Target`.
3. User clicks an action (`Read Subtree`, `Export Snapshot`, etc.).
4. Action runs against selected target without retyping IDs.

### Journey C: Health + Sync Check

1. User clicks `Run Health Check`.
2. Extension runs connect/session/smoke checks.
3. Results shown in one panel: pass/fail with links to logs.

## Information architecture

Activity Bar container: `Adrablox`

Views:

1. `Adrablox: Status`
   - Server status chip (`Healthy`/`Down`)
   - Session status (`Active`/`None` + sessionId)
   - Sync status (`Idle`/`Watching`/`Error`)
   - Bridge status (`Connected`/`Disconnected`)
   - Last run summary (latest command + result)

2. `Adrablox: Workspace Tree`
   - Roblox instance tree from `readTree`
   - Search/filter by name/class
   - `Set Active Target` on selection
   - Breadcrumb for selected node

3. `Adrablox: Actions`
   - Grouped buttons (Connection, Session, Sync, Diagnostics)
   - Inline argument pickers where required

4. `Adrablox: Task Output`
   - Chronological run history
   - Expandable logs
   - Copy command / copy error details

## Command surface (MVP)

### Connection

- `adrablox.server.start`
- `adrablox.server.stop`
- `adrablox.server.health`
- `adrablox.bridge.status`

### Session

- `adrablox.session.open`
- `adrablox.session.close`
- `adrablox.session.readTree`
- `adrablox.session.subscribeOnce`

### Snapshot + sync

- `adrablox.snapshot.export`
- `adrablox.snapshot.import`
- `adrablox.sync.liveCheck`
- `adrablox.sync.smokeTest`

### Diagnostics

- `adrablox.check.connectVerify`
- `adrablox.check.fullHealth`
- `adrablox.logs.openLast`

## Script-to-command mapping (MVP backend)

Use existing scripts first:

- `adrablox.check.connectVerify` → `studio_action_scripts/actions/connect_verify.ps1`
- `adrablox.session.open` → `studio_action_scripts/actions/open_session.ps1`
- `adrablox.session.readTree` → `studio_action_scripts/actions/read_tree.ps1`
- `adrablox.session.subscribeOnce` → `studio_action_scripts/actions/subscribe_changes.ps1`
- `adrablox.snapshot.export` → `studio_action_scripts/actions/snapshot_export.ps1`
- `adrablox.snapshot.import` → `studio_action_scripts/actions/snapshot_import.ps1`
- `adrablox.sync.liveCheck` → `tools/live_file_check.ps1`
- `adrablox.sync.smokeTest` → `tools/run_mcp_smoke_task.ps1`

`adrablox.server.start` and `adrablox.server.stop` should use a dedicated terminal/session manager in the extension.

## Target selection model

State held by extension:

- `activeSessionId: string | null`
- `activeTargetInstanceId: string | null`
- `lastTreeCursor: string | null`

Behavior:

1. `Open Session` stores `activeSessionId` and root ID.
2. `Read Tree` refreshes tree model.
3. Tree click sets `activeTargetInstanceId`.
4. Actions requiring target use `activeTargetInstanceId` by default.
5. If no target is selected, action prompts user.

## Error UX requirements

- Every failed action shows:
  - short reason,
  - probable cause,
  - suggested next click.
- Common examples:
  - `Server down` → show `Start Server` button.
  - `No session` → show `Open Session` button.
  - `Bridge disconnected` → show bridge checklist link.
- Raw stderr remains available in `Task Output`.

## Security and safety

- Keep MCP (HTTP JSON-RPC) as authoritative control plane.
- Treat bridge/live-runtime features as optional capability, never hard dependency for core sync.
- Do not persist secrets in plaintext logs.
- Keep localhost defaults unless explicitly configured.

## MVP extension project structure

Proposed location:

`tools/vscode-adrablox-control/`

```text
tools/vscode-adrablox-control/
  package.json
  tsconfig.json
  README.md
  src/
    extension.ts
    state/
      store.ts
      types.ts
    commands/
      connectionCommands.ts
      sessionCommands.ts
      syncCommands.ts
      diagnosticsCommands.ts
    services/
      scriptRunner.ts
      mcpClient.ts
      terminalService.ts
      statusService.ts
    views/
      statusViewProvider.ts
      workspaceTreeProvider.ts
      actionsViewProvider.ts
      taskOutputProvider.ts
    models/
      treeNode.ts
      runResult.ts
```

## `package.json` contributions (MVP)

- `viewsContainers.activitybar`:
  - `adrablox`
- `views` under container:
  - `adrablox.status`
  - `adrablox.workspaceTree`
  - `adrablox.actions`
  - `adrablox.taskOutput`
- `commands`:
  - all `adrablox.*` commands listed above
- `menus`:
  - context menu on tree nodes (`Set Active Target`, `Read Subtree`)

## Acceptance criteria (MVP)

1. User can complete open/read/sync/smoke workflows without opening terminal manually.
2. User can select a target node in tree and run target-bound action by click.
3. Status panel always reflects current server/session state within 3s refresh.
4. Errors are actionable and logs are inspectable from UI.
5. Existing script-based behavior remains unchanged and reusable.

## Implementation phases

### Phase 1 (1–2 days)

- Scaffold extension.
- Add Status + Actions views.
- Implement `connectVerify`, `openSession`, `readTree`, `smokeTest` command wiring.

### Phase 2 (1–2 days)

- Add Workspace Tree + active target state.
- Add snapshot actions and subscribe-once view refresh.

### Phase 3 (1 day)

- Add Full Health command and improved remediation messaging.
- Add polished task output history and command rerun.

## Future enhancements (post-MVP)

- Replace script wrappers with direct JSON-RPC client for core actions.
- Add guided workflows (`Quick Start`, `Release Readiness`, `Sync Diagnostics`).
- Add optional bridge capability panel with attach troubleshooting automation.