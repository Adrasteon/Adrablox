import * as cp from 'node:child_process';
import * as path from 'node:path';
import * as vscode from 'vscode';
import { RunResult } from '../state/types';

export class ScriptRunner {
  constructor(private readonly output: vscode.OutputChannel) {}

  public async runPowerShellScript(
    workspaceRoot: string,
    scriptRelativePath: string,
    args: string[],
    commandLabel: string,
  ): Promise<RunResult> {
    const scriptPath = path.join(workspaceRoot, scriptRelativePath);
    const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args];

    return new Promise<RunResult>((resolve) => {
      const child = cp.spawn('powershell', psArgs, { cwd: workspaceRoot, windowsHide: true });

      let stdout = '';
      let stderr = '';

      child.stdout.on('data', (chunk: Buffer) => {
        const text = chunk.toString();
        stdout += text;
        this.output.append(text);
      });

      child.stderr.on('data', (chunk: Buffer) => {
        const text = chunk.toString();
        stderr += text;
        this.output.append(text);
      });

      child.on('close', (code) => {
        const exitCode = typeof code === 'number' ? code : 1;
        resolve({
          success: exitCode === 0,
          commandLabel,
          stdout,
          stderr,
          exitCode,
          transportMode: 'script',
        });
      });

      child.on('error', (err) => {
        resolve({
          success: false,
          commandLabel,
          stdout,
          stderr: `${stderr}\n${err.message}`,
          exitCode: 1,
          transportMode: 'script',
        });
      });
    });
  }
}
