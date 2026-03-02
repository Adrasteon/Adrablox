# VS Code UX Extension Plan: Phases 4 + 5

Last updated: 2026-03-02

## Purpose

Define post-MVP implementation for Adrablox VS Code UX in two sequential phases:

- **Phase 4**: reliability/performance foundation via direct MCP JSON-RPC integration.
- **Phase 5**: UX acceleration via guided workflows and diagnostics polish.

This plan assumes Phase 1–3 are complete and stable on `dev/testing-debugging`.

## Current baseline (from MVP)

- Script-backed actions are implemented and validated in UI.
- Active target state, tree view, task history, full health check, and rerun are present.
- Extension lives under `tools/vscode-adrablox-control/`.

## Design principles for Phases 4 + 5

1. **Script parity first**: direct RPC must match existing script behavior before replacing defaults.
2. **Safe fallback always**: keep script fallback available per command.
3. **Fast, actionable UX**: failures map to next-click remediation.
4. **Incremental rollout**: command-by-command migration, not big-bang rewrite.

---

## Phase 4: Direct MCP Client Foundation

### Goals

- Replace high-traffic script wrappers with direct HTTP JSON-RPC calls for core session operations.
- Reduce latency and parsing brittleness from shell output extraction.
- Preserve operational safety with script fallback toggles.

### Scope

#### In scope

- New `mcpClient` service in extension:
  - `initialize`
  - `openSession`
  - `readTree`
  - `subscribeChanges`
  - `closeSession`
- Command migration path:
  - `adrablox.session.open`
  - `adrablox.session.readTree`
  - `adrablox.session.subscribeOnce`
  - `adrablox.check.fullHealth` (session/read/subscribe segments)
- Per-command execution strategy:
  - `Direct RPC (default)`
  - `Script fallback on failure`
- Typed error mapping for common failures:
  - server unavailable
  - invalid/no session
  - stale cursor
  - policy rejection/conflict

#### Out of scope

- Replacing all scripts in one phase.
- Bridge protocol redesign.
- Plugin-side protocol changes.

### Deliverables

1. `src/services/mcpClient.ts` with typed request/response models.
2. `src/services/errorMapper.ts` for remediation-focused messages.
3. Command-level strategy switch (`rpc-first` with script fallback).
4. Task Output entries include mode metadata (`rpc` vs `script`).
5. Extension setting(s):
   - `adrablox.transport.mode` (`rpc-first` | `script-only`)
   - `adrablox.transport.enableFallback` (boolean)

### Acceptance criteria

1. Migrated commands complete successfully in direct RPC mode for normal flows.
2. On forced RPC failure, fallback path succeeds when scripts are healthy.
3. Error messages remain actionable and consistent with MVP standards.
4. No regression in target-selection behavior and tree refresh.
5. Compile + click-tests pass for both `rpc-first` and `script-only` modes.

### Validation plan

- Unit-level: request/response decoding and error mapping.
- Integration-level:
  - open/read/subscribe round trip against local MCP server.
  - fallback simulation by intentionally breaking RPC endpoint.
- UX-level:
  - confirm status/task output parity between execution modes.

### Risks and mitigations

- **Risk**: response-shape drift over MCP versions.
  - **Mitigation**: central schema guards + clear downgrade to script mode.
- **Risk**: duplicate logic across script and RPC paths.
  - **Mitigation**: shared command orchestration and common result model.

---

## Phase 5: Guided Workflows + Diagnostics UX

### Goals

- Reduce multi-step operator effort to one-click guided flows.
- Improve diagnosis speed with bundled checks and structured outputs.

### Scope

#### In scope

- Guided workflows in Actions view:
  - **Quick Start**: server health -> open session -> read tree
  - **Sync Diagnostics**: connect verify -> full health -> live check -> smoke
  - **Release Readiness (light)**: health + smoke + summary report
- Workspace Tree enhancements:
  - name/class filter
  - `Read Subtree` context action against selected target
- Task Output enhancements:
  - grouped run summaries
  - copyable diagnostic bundle (text/markdown)

#### Out of scope

- Visual redesign/theming changes.
- New protocol features requiring server-side contract revisions.

### Deliverables

1. Workflow runner service (step pipeline with checkpoint state).
2. New commands:
   - `adrablox.workflow.quickStart`
   - `adrablox.workflow.syncDiagnostics`
   - `adrablox.workflow.releaseReadiness`
3. Tree filtering UI + subtree action wiring.
4. Diagnostic report export command:
   - `adrablox.logs.exportReport`

### Acceptance criteria

1. Quick Start completes without terminal usage in healthy environment.
2. Sync Diagnostics yields a single, shareable pass/fail summary.
3. Tree filter performs correctly without breaking selection state.
4. Read Subtree action honors active target/session context.
5. Task Output provides sufficient evidence for PR/review updates.

### Validation plan

- Workflow happy path + at least two failure injection cases per workflow.
- Verify remediation links/buttons for each failed checkpoint.
- Confirm report export content includes command, mode, exit/result, and key error context.

### Risks and mitigations

- **Risk**: workflow complexity creates opaque failures.
  - **Mitigation**: per-step logs + resumable checkpoints.
- **Risk**: UI overcrowding in Actions view.
  - **Mitigation**: grouped sections + concise labels + optional advanced commands.

---

## Proposed implementation order

1. Add `mcpClient` + transport settings scaffolding.
2. Migrate `open/read/subscribe` to RPC-first with fallback.
3. Migrate `fullHealth` internals to shared orchestration.
4. Add workflow runner and Quick Start.
5. Add Sync Diagnostics + report export.
6. Add tree filter + Read Subtree action.
7. Stabilization pass and docs updates.

## Definition of done (Phases 4 + 5)

- All Phase 4 and Phase 5 acceptance criteria pass.
- No MVP regressions in existing click-based flows.
- Reviewer can run guided workflows and collect diagnostics without manual script invocation.
- Documentation updated in MVP spec and README with new commands/settings.
