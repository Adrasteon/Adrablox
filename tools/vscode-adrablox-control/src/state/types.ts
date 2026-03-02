export type ServerStatus = 'unknown' | 'healthy' | 'down';

export interface WorkspaceInstanceNode {
  Id: string;
  Name: string;
  ClassName: string;
  Parent: string | null;
  Children: string[];
}

export interface WorkspaceTreeSnapshot {
  sessionId: string;
  instanceId: string;
  cursor: string;
  instances: Record<string, WorkspaceInstanceNode>;
}

export interface AdrabloxState {
  serverStatus: ServerStatus;
  activeSessionId: string | null;
  activeRootInstanceId: string | null;
  activeTargetInstanceId: string | null;
  lastTreeCursor: string | null;
  workspaceTree: WorkspaceTreeSnapshot | null;
  taskHistory: TaskHistoryEntry[];
  lastCommand: string | null;
  lastResult: 'success' | 'failure' | null;
}

export interface RunResult {
  success: boolean;
  commandLabel: string;
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface TaskHistoryEntry {
  id: string;
  timestamp: string;
  commandLabel: string;
  success: boolean;
  exitCode: number;
  remediationHint: string | null;
  scriptRelativePath: string;
  args: string[];
}
