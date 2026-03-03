import * as vscode from 'vscode';
import { StateStore } from '../state/store';

class StatusItem extends vscode.TreeItem {
  constructor(label: string, description: string) {
    super(label, vscode.TreeItemCollapsibleState.None);
    this.description = description;
  }
}

export class StatusViewProvider implements vscode.TreeDataProvider<StatusItem> {
  private readonly onDidChangeTreeDataEmitter = new vscode.EventEmitter<StatusItem | undefined>();
  public readonly onDidChangeTreeData = this.onDidChangeTreeDataEmitter.event;

  constructor(private readonly store: StateStore) {}

  public refresh(): void {
    this.onDidChangeTreeDataEmitter.fire(undefined);
  }

  public getTreeItem(element: StatusItem): vscode.TreeItem {
    return element;
  }

  public getChildren(): StatusItem[] {
    const state = this.store.getState();

    return [
      new StatusItem('Server', state.serverStatus),
      new StatusItem('Session', state.activeSessionId ?? 'none'),
      new StatusItem('Root Target', state.activeRootInstanceId ?? 'none'),
      new StatusItem('Active Target', state.activeTargetInstanceId ?? 'none'),
      new StatusItem('Tree Cursor', state.lastTreeCursor ?? 'none'),
      new StatusItem('Last Command', state.lastCommand ?? 'none'),
      new StatusItem('Last Result', state.lastResult ?? 'none'),
    ];
  }
}
