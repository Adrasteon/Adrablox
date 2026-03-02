import * as vscode from 'vscode';
import { mapRpcFailureHint } from '../services/errorMapper';
import { McpClient, OpenSessionResult, SubscribeChangesResult } from '../services/mcpClient';
import { ScriptRunner } from '../services/scriptRunner';
import { StateStore } from '../state/store';
import { RunResult, TaskHistoryEntry, WorkspaceTreeSnapshot } from '../state/types';
import { StatusViewProvider } from '../views/statusViewProvider';
import { TaskOutputProvider } from '../views/taskOutputProvider';
import { WorkspaceTreeProvider } from '../views/workspaceTreeProvider';

interface CommandDeps {
  mcpClient: McpClient;
  runner: ScriptRunner;
  store: StateStore;
  statusView: StatusViewProvider;
  workspaceTreeView: WorkspaceTreeProvider;
  taskOutputView: TaskOutputProvider;
  output: vscode.OutputChannel;
}

function getWorkspaceRoot(): string {
  const folder = vscode.workspace.workspaceFolders?.[0];
  if (!folder) {
    throw new Error('Open the Adrablox workspace folder before using Adrablox Control commands.');
  }
  return folder.uri.fsPath;
}

function refreshAllViews(deps: CommandDeps): void {
  deps.statusView.refresh();
  deps.workspaceTreeView.refresh();
  deps.taskOutputView.refresh();
}

function updateStatusFromResult(store: StateStore, result: RunResult): void {
  store.patch({
    lastCommand: result.commandLabel,
    lastResult: result.success ? 'success' : 'failure',
  });
}

function extractJsonObject(text: string): unknown | null {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }

  const candidate = text.slice(start, end + 1);
  try {
    return JSON.parse(candidate);
  } catch {
    return null;
  }
}

function parseOpenSessionResult(stdout: string): { sessionId: string; rootInstanceId: string } | null {
  const parsed = extractJsonObject(stdout) as
    | {
        result?: {
          structuredContent?: {
            sessionId?: string;
            rootInstanceId?: string;
          };
        };
      }
    | null;

  const sessionId = parsed?.result?.structuredContent?.sessionId;
  const rootInstanceId = parsed?.result?.structuredContent?.rootInstanceId;

  if (!sessionId || !rootInstanceId) {
    return null;
  }

  return { sessionId, rootInstanceId };
}

function parseReadTreeResult(stdout: string): WorkspaceTreeSnapshot | null {
  const parsed = extractJsonObject(stdout) as
    | {
        result?: {
          structuredContent?: {
            sessionId?: string;
            instanceId?: string;
            cursor?: string;
            instances?: Record<string, { Id: string; Name: string; ClassName: string; Parent: string | null; Children: string[] }>;
          };
        };
      }
    | null;

  const content = parsed?.result?.structuredContent;
  if (!content?.sessionId || !content.instanceId || !content.cursor || !content.instances) {
    return null;
  }

  return {
    sessionId: content.sessionId,
    instanceId: content.instanceId,
    cursor: content.cursor,
    instances: content.instances,
  };
}

function parseSubscribeResult(stdout: string): { cursor: string; changed: boolean } | null {
  const parsed = extractJsonObject(stdout) as
    | {
        result?: {
          structuredContent?: {
            cursor?: string;
            added?: Record<string, unknown>;
            updated?: unknown[];
            removed?: unknown[];
          };
        };
      }
    | null;

  const content = parsed?.result?.structuredContent;
  if (!content?.cursor) {
    return null;
  }

  const addedCount = Object.keys(content.added ?? {}).length;
  const updatedCount = (content.updated ?? []).length;
  const removedCount = (content.removed ?? []).length;

  return {
    cursor: content.cursor,
    changed: addedCount > 0 || updatedCount > 0 || removedCount > 0,
  };
}

function getRemediationHint(commandLabel: string, scriptRelativePath: string, result: RunResult): string | null {
  if (result.success) {
    return null;
  }

  if (result.transportMode === 'rpc') {
    return mapRpcFailureHint(commandLabel, result.stderr);
  }

  if (scriptRelativePath.includes('connect_verify')) {
    return 'Ensure mcp-server is running on http://127.0.0.1:44877/mcp, then run Connect Verify again.';
  }
  if (scriptRelativePath.includes('open_session')) {
    return 'Ensure Roblox Studio is open with the Adrablox plugin loaded, then retry Open Session.';
  }
  if (scriptRelativePath.includes('read_tree')) {
    return 'Open a session first and verify the active target/root instance ID before retrying Read Tree.';
  }
  if (scriptRelativePath.includes('subscribe_changes')) {
    return 'Session/cursor may be stale. Re-open session and retry Subscribe Once.';
  }
  if (scriptRelativePath.includes('snapshot_export')) {
    return 'Ensure a valid session exists and output file path is writable before exporting snapshot.';
  }
  if (scriptRelativePath.includes('snapshot_import')) {
    return 'Ensure snapshot JSON is valid and session is active before importing.';
  }
  if (scriptRelativePath.includes('run_mcp_smoke_task')) {
    return 'Verify no port conflicts on 44877 and that server startup scripts can execute from this workspace.';
  }

  return result.stderr.trim().length > 0
    ? 'Inspect Adrablox output details, fix the reported error, then rerun the action.'
    : null;
}

function showFailureWithHint(commandLabel: string, hint: string | null): void {
  if (hint) {
    vscode.window.showErrorMessage(`${commandLabel} failed. ${hint}`);
  } else {
    vscode.window.showErrorMessage(`${commandLabel} failed. See Adrablox output for details.`);
  }
}

function makeTaskHistoryEntry(
  commandLabel: string,
  scriptRelativePath: string,
  args: string[],
  result: RunResult,
  remediationHint: string | null,
): TaskHistoryEntry {
  const now = new Date();
  return {
    id: `${now.getTime()}-${Math.random().toString(16).slice(2, 8)}`,
    timestamp: now.toISOString(),
    commandLabel,
    transportMode: result.transportMode,
    success: result.success,
    exitCode: result.exitCode,
    remediationHint,
    scriptRelativePath,
    args: [...args],
  };
}

function getTransportConfig(): { mode: 'rpc-first' | 'script-only'; enableFallback: boolean; projectPath: string } {
  const config = vscode.workspace.getConfiguration('adrablox');
  const mode = config.get<'rpc-first' | 'script-only'>('transport.mode', 'rpc-first');
  const enableFallback = config.get<boolean>('transport.enableFallback', true);
  const projectPath = config.get<string>('session.projectPath', 'src');
  return {
    mode,
    enableFallback,
    projectPath,
  };
}

function createRpcSuccessResult(commandLabel: string, payload: unknown): RunResult {
  return {
    success: true,
    commandLabel,
    stdout: JSON.stringify(payload),
    stderr: '',
    exitCode: 0,
    transportMode: 'rpc',
  };
}

function createRpcFailureResult(commandLabel: string, err: unknown): RunResult {
  const message = err instanceof Error ? err.message : String(err);
  return {
    success: false,
    commandLabel,
    stdout: '',
    stderr: message,
    exitCode: 1,
    transportMode: 'rpc',
  };
}

export function registerPhase1Commands(context: vscode.ExtensionContext, deps: CommandDeps): void {
  const executeScript = async (
    scriptRelativePath: string,
    args: string[],
    commandLabel: string,
  ): Promise<{ result: RunResult; remediationHint: string | null }> => {
    const workspaceRoot = getWorkspaceRoot();
    deps.output.show(true);
    deps.output.appendLine(`\n> ${commandLabel}`);

    const result = await deps.runner.runPowerShellScript(workspaceRoot, scriptRelativePath, args, commandLabel);
    const remediationHint = getRemediationHint(commandLabel, scriptRelativePath, result);

    updateStatusFromResult(deps.store, result);
    deps.store.addTaskHistory(makeTaskHistoryEntry(commandLabel, scriptRelativePath, args, result, remediationHint));
    refreshAllViews(deps);

    return { result, remediationHint };
  };

  const executeRpc = async (
    commandLabel: string,
    scriptRelativePathForHistory: string,
    operation: () => Promise<unknown>,
  ): Promise<{ result: RunResult; remediationHint: string | null; payload: unknown | null }> => {
    deps.output.show(true);
    deps.output.appendLine(`\n> ${commandLabel} (rpc)`);

    let result: RunResult;
    let payload: unknown | null = null;
    try {
      payload = await operation();
      result = createRpcSuccessResult(commandLabel, payload);
    } catch (err) {
      result = createRpcFailureResult(commandLabel, err);
    }

    const remediationHint = getRemediationHint(commandLabel, scriptRelativePathForHistory, result);
    updateStatusFromResult(deps.store, result);
    deps.store.addTaskHistory(makeTaskHistoryEntry(commandLabel, scriptRelativePathForHistory, [], result, remediationHint));
    refreshAllViews(deps);

    return { result, remediationHint, payload };
  };

  const executeCoreAction = async (
    commandLabel: string,
    scriptRelativePath: string,
    scriptArgs: string[],
    rpcOperation: () => Promise<unknown>,
  ): Promise<{ result: RunResult; remediationHint: string | null; payload: unknown | null }> => {
    const transport = getTransportConfig();
    if (transport.mode === 'script-only') {
      const scriptResult = await executeScript(scriptRelativePath, scriptArgs, commandLabel);
      return { ...scriptResult, payload: null };
    }

    const rpcResult = await executeRpc(commandLabel, scriptRelativePath, rpcOperation);
    if (rpcResult.result.success || !transport.enableFallback) {
      return rpcResult;
    }

    deps.output.appendLine(`RPC failed for ${commandLabel}; falling back to script.`);
    const scriptResult = await executeScript(scriptRelativePath, scriptArgs, `${commandLabel} (fallback)`);
    return { ...scriptResult, payload: null };
  };

  context.subscriptions.push(
    vscode.commands.registerCommand('adrablox.check.connectVerify', async () => {
      try {
        const { result, remediationHint } = await executeScript(
          'studio_action_scripts/actions/connect_verify.ps1',
          ['-Pretty'],
          'Connect Verify',
        );

        deps.store.patch({ serverStatus: result.success ? 'healthy' : 'down' });
        refreshAllViews(deps);

        if (result.success) {
          vscode.window.showInformationMessage('Adrablox connect verify passed.');
        } else {
          showFailureWithHint('Connect Verify', remediationHint);
        }
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.session.open', async () => {
      try {
        const transport = getTransportConfig();
        const { result, remediationHint, payload } = await executeCoreAction(
          'Open Session',
          'studio_action_scripts/actions/open_session.ps1',
          ['-Pretty'],
          () => deps.mcpClient.openSession(transport.projectPath),
        );

        if (!result.success) {
          showFailureWithHint('Open Session', remediationHint);
          return;
        }

        const session = result.transportMode === 'rpc'
          ? (payload as OpenSessionResult | null)
          : parseOpenSessionResult(result.stdout);
        if (!session) {
          vscode.window.showWarningMessage('Open Session ran, but session metadata could not be parsed from output.');
          return;
        }

        deps.store.patch({
          serverStatus: 'healthy',
          activeSessionId: session.sessionId,
          activeRootInstanceId: session.rootInstanceId,
          activeTargetInstanceId: session.rootInstanceId,
          workspaceTree: null,
        });
        refreshAllViews(deps);
        vscode.window.showInformationMessage(`Session opened: ${session.sessionId}`);
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.session.readTree', async () => {
      try {
        const state = deps.store.getState();
        if (!state.activeSessionId) {
          vscode.window.showWarningMessage('No active session. Run Open Session first.');
          return;
        }

        const instanceId = state.activeTargetInstanceId ?? state.activeRootInstanceId ?? 'ref_root';
        const { result, remediationHint, payload } = await executeCoreAction(
          'Read Tree',
          'studio_action_scripts/actions/read_tree.ps1',
          ['-SessionId', state.activeSessionId, '-InstanceId', instanceId, '-Pretty'],
          () => deps.mcpClient.readTree(state.activeSessionId!, instanceId),
        );

        if (result.success) {
          const tree = result.transportMode === 'rpc'
            ? (payload as WorkspaceTreeSnapshot | null)
            : parseReadTreeResult(result.stdout);
          if (tree) {
            deps.store.patch({
              workspaceTree: tree,
              lastTreeCursor: tree.cursor,
              activeTargetInstanceId: state.activeTargetInstanceId ?? tree.instanceId,
            });
          }
          refreshAllViews(deps);
          vscode.window.showInformationMessage('Read Tree completed.');
        } else {
          showFailureWithHint('Read Tree', remediationHint);
        }
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.workspace.setActiveTarget', async (payload: string | { instanceId?: string }) => {
      const instanceId = typeof payload === 'string' ? payload : payload?.instanceId;
      if (!instanceId) {
        return;
      }
      deps.store.patch({ activeTargetInstanceId: instanceId });
      refreshAllViews(deps);
      vscode.window.showInformationMessage(`Active target set: ${instanceId}`);
    }),

    vscode.commands.registerCommand('adrablox.session.subscribeOnce', async () => {
      try {
        const state = deps.store.getState();
        if (!state.activeSessionId) {
          vscode.window.showWarningMessage('No active session. Run Open Session first.');
          return;
        }

        const cursor = state.lastTreeCursor ?? '0';
        const { result, remediationHint, payload } = await executeCoreAction(
          'Subscribe Once',
          'studio_action_scripts/actions/subscribe_changes.ps1',
          ['-SessionId', state.activeSessionId, '-Cursor', cursor, '-Pretty'],
          () => deps.mcpClient.subscribeChanges(state.activeSessionId!, cursor),
        );

        if (!result.success) {
          showFailureWithHint('Subscribe Once', remediationHint);
          return;
        }

        const subscribe = result.transportMode === 'rpc'
          ? (payload as SubscribeChangesResult | null)
          : parseSubscribeResult(result.stdout);
        if (subscribe) {
          deps.store.patch({ lastTreeCursor: subscribe.cursor });
        }

        if (subscribe?.changed) {
          const latest = deps.store.getState();
          const refreshTree = await executeCoreAction(
            'Read Tree (refresh after subscribe)',
            'studio_action_scripts/actions/read_tree.ps1',
            ['-SessionId', latest.activeSessionId!, '-InstanceId', latest.activeRootInstanceId ?? 'ref_root', '-Pretty'],
            () => deps.mcpClient.readTree(latest.activeSessionId!, latest.activeRootInstanceId ?? 'ref_root'),
          );

          if (refreshTree.result.success) {
            const tree = refreshTree.result.transportMode === 'rpc'
              ? (refreshTree.payload as WorkspaceTreeSnapshot | null)
              : parseReadTreeResult(refreshTree.result.stdout);
            if (tree) {
              deps.store.patch({
                workspaceTree: tree,
                lastTreeCursor: tree.cursor,
              });
            }
          }
        }

        refreshAllViews(deps);
        vscode.window.showInformationMessage(subscribe?.changed ? 'Subscribe detected changes and tree was refreshed.' : 'Subscribe completed: no changes.');
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.snapshot.export', async () => {
      try {
        const state = deps.store.getState();
        if (!state.activeSessionId) {
          vscode.window.showWarningMessage('No active session. Run Open Session first.');
          return;
        }

        const defaultPath = vscode.Uri.file(`${getWorkspaceRoot()}\\studio_action_scripts\\out\\snapshot.ui.json`);
        const target = await vscode.window.showSaveDialog({
          defaultUri: defaultPath,
          filters: { JSON: ['json'] },
          saveLabel: 'Export Snapshot',
        });

        if (!target) {
          return;
        }

        const { result, remediationHint } = await executeScript(
          'studio_action_scripts/actions/snapshot_export.ps1',
          ['-SessionId', state.activeSessionId, '-OutFile', target.fsPath, '-Pretty'],
          'Snapshot Export',
        );

        if (result.success) {
          vscode.window.showInformationMessage(`Snapshot exported: ${target.fsPath}`);
        } else {
          showFailureWithHint('Snapshot Export', remediationHint);
        }
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.snapshot.import', async () => {
      try {
        const state = deps.store.getState();
        if (!state.activeSessionId) {
          vscode.window.showWarningMessage('No active session. Run Open Session first.');
          return;
        }

        const selected = await vscode.window.showOpenDialog({
          canSelectMany: false,
          canSelectFiles: true,
          canSelectFolders: false,
          openLabel: 'Import Snapshot',
          filters: { JSON: ['json'] },
        });

        if (!selected || selected.length === 0) {
          return;
        }

        const inFile = selected[0].fsPath;
        const { result, remediationHint } = await executeScript(
          'studio_action_scripts/actions/snapshot_import.ps1',
          ['-SessionId', state.activeSessionId, '-InFile', inFile, '-Pretty'],
          'Snapshot Import',
        );

        if (!result.success) {
          showFailureWithHint('Snapshot Import', remediationHint);
          return;
        }

        const latest = deps.store.getState();
        const refreshTree = await executeScript(
          'studio_action_scripts/actions/read_tree.ps1',
          ['-SessionId', latest.activeSessionId!, '-InstanceId', latest.activeRootInstanceId ?? 'ref_root', '-Pretty'],
          'Read Tree (refresh after import)',
        );

        if (refreshTree.result.success) {
          const tree = parseReadTreeResult(refreshTree.result.stdout);
          if (tree) {
            deps.store.patch({
              workspaceTree: tree,
              lastTreeCursor: tree.cursor,
            });
          }
        }

        refreshAllViews(deps);
        vscode.window.showInformationMessage('Snapshot import completed and tree refreshed.');
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.sync.smokeTest', async () => {
      try {
        const { result, remediationHint } = await executeScript('tools/run_mcp_smoke_task.ps1', [], 'Run Smoke Test');

        if (result.success) {
          deps.store.patch({ serverStatus: 'healthy' });
          refreshAllViews(deps);
          vscode.window.showInformationMessage('Smoke Test completed successfully.');
        } else {
          deps.store.patch({ serverStatus: 'down' });
          refreshAllViews(deps);
          showFailureWithHint('Smoke Test', remediationHint);
        }
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.check.fullHealth', async () => {
      try {
        const summary: string[] = [];

        const connect = await executeScript(
          'studio_action_scripts/actions/connect_verify.ps1',
          ['-Pretty'],
          'Health: Connect Verify',
        );
        if (!connect.result.success) {
          deps.store.patch({ serverStatus: 'down' });
          refreshAllViews(deps);
          showFailureWithHint('Full Health Check', connect.remediationHint);
          return;
        }
        deps.store.patch({ serverStatus: 'healthy' });
        summary.push('connect=ok');

        const transport = getTransportConfig();
        const open = await executeCoreAction(
          'Health: Open Session',
          'studio_action_scripts/actions/open_session.ps1',
          ['-Pretty'],
          () => deps.mcpClient.openSession(transport.projectPath),
        );
        if (!open.result.success) {
          refreshAllViews(deps);
          showFailureWithHint('Full Health Check', open.remediationHint);
          return;
        }
        const session = open.result.transportMode === 'rpc'
          ? (open.payload as OpenSessionResult | null)
          : parseOpenSessionResult(open.result.stdout);
        if (!session) {
          refreshAllViews(deps);
          vscode.window.showErrorMessage('Full Health Check failed: could not parse session metadata from Open Session output.');
          return;
        }

        deps.store.patch({
          activeSessionId: session.sessionId,
          activeRootInstanceId: session.rootInstanceId,
          activeTargetInstanceId: session.rootInstanceId,
        });
        summary.push('session=ok');

        const read = await executeCoreAction(
          'Health: Read Tree',
          'studio_action_scripts/actions/read_tree.ps1',
          ['-SessionId', session.sessionId, '-InstanceId', session.rootInstanceId, '-Pretty'],
          () => deps.mcpClient.readTree(session.sessionId, session.rootInstanceId),
        );
        if (!read.result.success) {
          refreshAllViews(deps);
          showFailureWithHint('Full Health Check', read.remediationHint);
          return;
        }
        const tree = read.result.transportMode === 'rpc'
          ? (read.payload as WorkspaceTreeSnapshot | null)
          : parseReadTreeResult(read.result.stdout);
        if (tree) {
          deps.store.patch({
            workspaceTree: tree,
            lastTreeCursor: tree.cursor,
          });
        }
        summary.push('read=ok');

        const cursor = deps.store.getState().lastTreeCursor ?? '0';
        const subscribe = await executeCoreAction(
          'Health: Subscribe Once',
          'studio_action_scripts/actions/subscribe_changes.ps1',
          ['-SessionId', session.sessionId, '-Cursor', cursor, '-Pretty'],
          () => deps.mcpClient.subscribeChanges(session.sessionId, cursor),
        );
        if (!subscribe.result.success) {
          refreshAllViews(deps);
          showFailureWithHint('Full Health Check', subscribe.remediationHint);
          return;
        }
        summary.push('subscribe=ok');

        const smoke = await executeScript('tools/run_mcp_smoke_task.ps1', [], 'Health: Smoke Test');
        if (!smoke.result.success) {
          deps.store.patch({ serverStatus: 'down' });
          refreshAllViews(deps);
          showFailureWithHint('Full Health Check', smoke.remediationHint);
          return;
        }
        deps.store.patch({ serverStatus: 'healthy' });
        summary.push('smoke=ok');

        refreshAllViews(deps);
        vscode.window.showInformationMessage(`Full Health Check passed (${summary.join(', ')}).`);
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),

    vscode.commands.registerCommand('adrablox.task.rerun', async (entry: TaskHistoryEntry) => {
      try {
        if (!entry?.scriptRelativePath) {
          vscode.window.showWarningMessage('No runnable task payload was provided.');
          return;
        }

        const rerun = await executeScript(
          entry.scriptRelativePath,
          entry.args ?? [],
          `Rerun: ${entry.commandLabel}`,
        );

        if (rerun.result.success) {
          vscode.window.showInformationMessage(`Rerun succeeded: ${entry.commandLabel}`);
        } else {
          showFailureWithHint(`Rerun: ${entry.commandLabel}`, rerun.remediationHint);
        }
      } catch (err) {
        vscode.window.showErrorMessage((err as Error).message);
      }
    }),
  );
}
