# Adrablox Control (Phase 1 MVP)

Click-first VS Code extension scaffold for common Adrablox workflows.

## Implemented in Phase 1 + Phase 2

- Activity Bar container: `Adrablox`
- Views:
  - `Status`
  - `Workspace Tree`
  - `Actions`
- Click commands:
  - `Adrablox: Connect Verify`
  - `Adrablox: Open Session`
  - `Adrablox: Read Tree`
  - `Adrablox: Subscribe Once`
  - `Adrablox: Export Snapshot`
  - `Adrablox: Import Snapshot`
  - `Adrablox: Run Smoke Test`

## Phase 2 behavior

- `Read Tree` stores a workspace tree model and renders it in `Workspace Tree`.
- Clicking a tree node sets the `Active Target`.
- `Subscribe Once` checks for remote changes and auto-refreshes tree state when updates are detected.
- Snapshot export/import are available as click actions.

## Development

```powershell
Set-Location tools/vscode-adrablox-control
npm install
npm run compile
```

Then press `F5` in VS Code from this extension folder to launch an Extension Development Host.
