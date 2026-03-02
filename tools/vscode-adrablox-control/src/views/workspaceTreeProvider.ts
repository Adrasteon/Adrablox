import * as vscode from 'vscode';
import { StateStore } from '../state/store';
import { WorkspaceInstanceNode } from '../state/types';

export class WorkspaceTreeItem extends vscode.TreeItem {
  constructor(
    public readonly instanceId: string,
    public readonly node: WorkspaceInstanceNode,
    collapsibleState: vscode.TreeItemCollapsibleState,
    isActiveTarget: boolean,
  ) {
    super(`${node.Name} (${node.ClassName})`, collapsibleState);
    this.description = isActiveTarget ? 'active target' : undefined;
    this.tooltip = `${node.ClassName}\nID: ${instanceId}`;
    this.contextValue = 'adrablox.workspaceNode';
    this.command = {
      command: 'adrablox.workspace.setActiveTarget',
      title: 'Set Active Target',
      arguments: [instanceId],
    };
  }
}

export class WorkspaceTreeProvider implements vscode.TreeDataProvider<WorkspaceTreeItem> {
  private readonly onDidChangeTreeDataEmitter = new vscode.EventEmitter<WorkspaceTreeItem | undefined>();
  public readonly onDidChangeTreeData = this.onDidChangeTreeDataEmitter.event;

  constructor(private readonly store: StateStore) {}

  public refresh(): void {
    this.onDidChangeTreeDataEmitter.fire(undefined);
  }

  public getTreeItem(element: WorkspaceTreeItem): vscode.TreeItem {
    return element;
  }

  public getChildren(element?: WorkspaceTreeItem): WorkspaceTreeItem[] {
    const state = this.store.getState();
    const snapshot = state.workspaceTree;

    if (!snapshot) {
      return [];
    }

    const getItem = (instanceId: string): WorkspaceTreeItem | null => {
      const node = snapshot.instances[instanceId];
      if (!node) {
        return null;
      }

      const hasChildren = node.Children.length > 0;
      return new WorkspaceTreeItem(
        instanceId,
        node,
        hasChildren ? vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None,
        state.activeTargetInstanceId === instanceId,
      );
    };

    if (!element) {
      const rootId = state.activeRootInstanceId ?? snapshot.instanceId;
      const rootItem = getItem(rootId);
      return rootItem ? [rootItem] : [];
    }

    const children = element.node.Children
      .map((id) => getItem(id))
      .filter((item): item is WorkspaceTreeItem => item !== null)
      .sort((left, right) => left.node.Name.localeCompare(right.node.Name));

    return children;
  }
}
