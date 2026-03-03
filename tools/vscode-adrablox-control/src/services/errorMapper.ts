export function mapRpcFailureHint(commandLabel: string, errorMessage: string): string {
  const lower = `${commandLabel} ${errorMessage}`.toLowerCase();

  if (lower.includes('econnrefused') || lower.includes('fetch failed') || lower.includes('connect') || lower.includes('127.0.0.1:44877')) {
    return 'MCP server appears unavailable. Start/verify server at http://127.0.0.1:44877/mcp, then retry.';
  }

  if (lower.includes('session') && (lower.includes('invalid') || lower.includes('not found') || lower.includes('missing'))) {
    return 'Session is invalid or missing. Run Open Session, then retry the action.';
  }

  if (lower.includes('cursor') && (lower.includes('stale') || lower.includes('invalid') || lower.includes('conflict'))) {
    return 'Tree cursor appears stale. Run Read Tree (or Open Session) and retry Subscribe Once.';
  }

  if (lower.includes('policy') || lower.includes('forbidden') || lower.includes('not allowed')) {
    return 'Operation was rejected by server policy. Check capability/policy constraints and retry with a permitted action.';
  }

  return 'RPC call failed. Retry once; if it still fails, use script fallback mode and inspect Task Output details.';
}
