import * as http from 'node:http';
import * as https from 'node:https';
import * as vscode from 'vscode';
import { WorkspaceTreeSnapshot } from '../state/types';

interface JsonRpcResponse<T = unknown> {
  result?: T;
  error?: {
    code?: number;
    message?: string;
    data?: unknown;
  };
}

interface ToolCallResult {
  structuredContent?: unknown;
  content?: Array<{ text?: string; type?: string }>;
}

export interface OpenSessionResult {
  sessionId: string;
  rootInstanceId: string;
}

export interface SubscribeChangesResult {
  cursor: string;
  changed: boolean;
}

export class MpcClientError extends Error {
  constructor(message: string, public readonly code?: number) {
    super(message);
    this.name = 'McpClientError';
  }
}

export class McpClient {
  constructor(private readonly output: vscode.OutputChannel) {}

  private getEndpoint(): string {
    const config = vscode.workspace.getConfiguration('adrablox');
    return config.get<string>('transport.endpoint', 'http://127.0.0.1:44877/mcp');
  }

  private async postJson<T>(payload: object): Promise<T> {
    const endpoint = this.getEndpoint();
    const url = new URL(endpoint);
    const body = JSON.stringify(payload);
    const client = url.protocol === 'https:' ? https : http;

    return new Promise<T>((resolve, reject) => {
      const req = client.request(
        {
          hostname: url.hostname,
          port: url.port || (url.protocol === 'https:' ? 443 : 80),
          path: `${url.pathname}${url.search}`,
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(body),
          },
        },
        (res) => {
          let data = '';
          res.setEncoding('utf8');
          res.on('data', (chunk) => {
            data += chunk;
          });
          res.on('end', () => {
            try {
              const parsed = JSON.parse(data || '{}') as T;
              resolve(parsed);
            } catch (err) {
              reject(new Error(`Invalid JSON response from MCP endpoint: ${(err as Error).message}`));
            }
          });
        },
      );

      req.on('error', reject);
      req.write(body);
      req.end();
    });
  }

  private async callTool<TStructured = unknown>(name: string, args: Record<string, unknown>): Promise<TStructured> {
    const payload = {
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name,
        arguments: args,
      },
    };

    this.output.appendLine(`RPC tools/call -> ${name}`);
    const response = await this.postJson<JsonRpcResponse<ToolCallResult>>(payload);

    if (response.error) {
      throw new MpcClientError(response.error.message ?? `RPC error while calling ${name}`, response.error.code);
    }

    const structured = response.result?.structuredContent as TStructured | undefined;
    if (!structured) {
      throw new MpcClientError(`Missing structuredContent in RPC response for ${name}`);
    }

    return structured;
  }

  public async openSession(projectPath: string): Promise<OpenSessionResult> {
    const structured = await this.callTool<{
      sessionId?: string;
      rootInstanceId?: string;
    }>('roblox.openSession', { projectPath });

    if (!structured.sessionId || !structured.rootInstanceId) {
      throw new MpcClientError('RPC openSession response missing sessionId/rootInstanceId');
    }

    return {
      sessionId: structured.sessionId,
      rootInstanceId: structured.rootInstanceId,
    };
  }

  public async readTree(sessionId: string, instanceId: string): Promise<WorkspaceTreeSnapshot> {
    const structured = await this.callTool<{
      sessionId?: string;
      instanceId?: string;
      cursor?: string;
      instances?: WorkspaceTreeSnapshot['instances'];
    }>('roblox.readTree', { sessionId, instanceId });

    if (!structured.sessionId || !structured.instanceId || !structured.cursor || !structured.instances) {
      throw new MpcClientError('RPC readTree response missing required fields');
    }

    return {
      sessionId: structured.sessionId,
      instanceId: structured.instanceId,
      cursor: structured.cursor,
      instances: structured.instances,
    };
  }

  public async subscribeChanges(sessionId: string, cursor?: string): Promise<SubscribeChangesResult> {
    const args: Record<string, unknown> = { sessionId };
    if (cursor != null) {
      args.cursor = cursor;
    }

    const structured = await this.callTool<{
      cursor?: string;
      added?: Record<string, unknown>;
      updated?: unknown[];
      removed?: unknown[];
    }>('roblox.subscribeChanges', args);

    if (!structured.cursor) {
      throw new MpcClientError('RPC subscribeChanges response missing cursor');
    }

    const addedCount = Object.keys(structured.added ?? {}).length;
    const updatedCount = (structured.updated ?? []).length;
    const removedCount = (structured.removed ?? []).length;

    return {
      cursor: structured.cursor,
      changed: addedCount > 0 || updatedCount > 0 || removedCount > 0,
    };
  }

  public async closeSession(sessionId: string): Promise<void> {
    await this.callTool('roblox.closeSession', { sessionId });
  }
}
