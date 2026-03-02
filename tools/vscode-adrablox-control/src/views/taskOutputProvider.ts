import * as vscode from 'vscode';
import { StateStore } from '../state/store';
import { TaskHistoryEntry } from '../state/types';

class TaskHistoryItem extends vscode.TreeItem {
  constructor(public readonly entry: TaskHistoryEntry) {
    super(entry.commandLabel, vscode.TreeItemCollapsibleState.None);
    this.description = `${entry.success ? 'ok' : 'failed'} @ ${new Date(entry.timestamp).toLocaleTimeString()}`;
    this.tooltip = [
      `${entry.commandLabel}`,
      `Exit code: ${entry.exitCode}`,
      entry.remediationHint ? `Hint: ${entry.remediationHint}` : 'Hint: none',
    ].join('\n');
    this.iconPath = new vscode.ThemeIcon(entry.success ? 'check' : 'error');
    this.command = {
      command: 'adrablox.task.rerun',
      title: 'Rerun Task',
      arguments: [entry],
    };
    this.contextValue = 'adrablox.taskHistoryItem';
  }
}

export class TaskOutputProvider implements vscode.TreeDataProvider<TaskHistoryItem> {
  private readonly onDidChangeTreeDataEmitter = new vscode.EventEmitter<TaskHistoryItem | undefined>();
  public readonly onDidChangeTreeData = this.onDidChangeTreeDataEmitter.event;

  constructor(private readonly store: StateStore) {}

  public refresh(): void {
    this.onDidChangeTreeDataEmitter.fire(undefined);
  }

  public getTreeItem(element: TaskHistoryItem): vscode.TreeItem {
    return element;
  }

  public getChildren(): TaskHistoryItem[] {
    const state = this.store.getState();
    return state.taskHistory.map((entry) => new TaskHistoryItem(entry));
  }
}
