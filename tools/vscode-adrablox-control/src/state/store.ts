import { AdrabloxState } from './types';
import { TaskHistoryEntry } from './types';

export class StateStore {
  private readonly maxHistory = 50;

  private state: AdrabloxState = {
    serverStatus: 'unknown',
    activeSessionId: null,
    activeRootInstanceId: null,
    activeTargetInstanceId: null,
    lastTreeCursor: null,
    workspaceTree: null,
    taskHistory: [],
    lastCommand: null,
    lastResult: null,
  };

  public getState(): AdrabloxState {
    return { ...this.state };
  }

  public patch(update: Partial<AdrabloxState>): void {
    this.state = {
      ...this.state,
      ...update,
    };
  }

  public addTaskHistory(entry: TaskHistoryEntry): void {
    const nextHistory = [entry, ...this.state.taskHistory].slice(0, this.maxHistory);
    this.state = {
      ...this.state,
      taskHistory: nextHistory,
    };
  }
}
