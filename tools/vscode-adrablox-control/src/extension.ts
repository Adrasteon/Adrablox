import * as vscode from 'vscode';
import { registerPhase1Commands } from './commands/phase1Commands';
import { McpClient } from './services/mcpClient';
import { ScriptRunner } from './services/scriptRunner';
import { StateStore } from './state/store';
import { ActionsViewProvider } from './views/actionsViewProvider';
import { StatusViewProvider } from './views/statusViewProvider';
import { TaskOutputProvider } from './views/taskOutputProvider';
import { WorkspaceTreeProvider } from './views/workspaceTreeProvider';

export function activate(context: vscode.ExtensionContext): void {
  const output = vscode.window.createOutputChannel('Adrablox Control');
  const store = new StateStore();
  const runner = new ScriptRunner(output);
  const mcpClient = new McpClient(output);

  const statusView = new StatusViewProvider(store);
  const actionsView = new ActionsViewProvider();
  const workspaceTreeView = new WorkspaceTreeProvider(store);
  const taskOutputView = new TaskOutputProvider(store);

  context.subscriptions.push(
    output,
    vscode.window.registerTreeDataProvider('adrablox.status', statusView),
    vscode.window.registerTreeDataProvider('adrablox.actions', actionsView),
    vscode.window.registerTreeDataProvider('adrablox.workspaceTree', workspaceTreeView),
    vscode.window.registerTreeDataProvider('adrablox.taskOutput', taskOutputView),
  );

  registerPhase1Commands(context, {
    mcpClient,
    runner,
    store,
    statusView,
    workspaceTreeView,
    taskOutputView,
    output,
  });
}

export function deactivate(): void {
  // no-op
}
