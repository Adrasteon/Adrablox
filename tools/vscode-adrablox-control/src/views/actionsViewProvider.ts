import * as vscode from 'vscode';

class ActionItem extends vscode.TreeItem {
  constructor(label: string, commandId: string, tooltip?: string) {
    super(label, vscode.TreeItemCollapsibleState.None);
    this.command = {
      command: commandId,
      title: label,
    };
    this.tooltip = tooltip ?? label;
  }
}

export class ActionsViewProvider implements vscode.TreeDataProvider<ActionItem> {
  private readonly items: ActionItem[] = [
    new ActionItem('Run Full Health Check', 'adrablox.check.fullHealth', 'Run connect/session/tree/subscribe/smoke checks with one click'),
    new ActionItem('Connect Verify', 'adrablox.check.connectVerify', 'Run connect_verify.ps1'),
    new ActionItem('Open Session', 'adrablox.session.open', 'Run open_session.ps1'),
    new ActionItem('Read Tree', 'adrablox.session.readTree', 'Run read_tree.ps1 for current session/root target'),
    new ActionItem('Subscribe Once', 'adrablox.session.subscribeOnce', 'Poll subscribeChanges once and refresh tree if changed'),
    new ActionItem('Export Snapshot', 'adrablox.snapshot.export', 'Run snapshot_export.ps1 for current session'),
    new ActionItem('Import Snapshot', 'adrablox.snapshot.import', 'Run snapshot_import.ps1 and refresh tree'),
    new ActionItem('Run Smoke Test', 'adrablox.sync.smokeTest', 'Run run_mcp_smoke_task.ps1'),
  ];

  public getTreeItem(element: ActionItem): vscode.TreeItem {
    return element;
  }

  public getChildren(): ActionItem[] {
    return this.items;
  }
}
