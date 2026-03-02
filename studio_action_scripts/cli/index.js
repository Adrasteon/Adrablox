#!/usr/bin/env node
const http = require('http');
const https = require('https');
const { URL } = require('url');
const fs = require('fs');

function parseWsTailArgs(args) {
  const out = {
    url: null,
    authToken: process.env.MCP_WS_AUTH_TOKEN || null,
    since: null,
    limit: 100,
    dryRun: false,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === '--auth-token') {
      out.authToken = args[i + 1] || null;
      i += 1;
      continue;
    }
    if (arg === '--since') {
      const raw = args[i + 1];
      out.since = raw != null ? Number(raw) : null;
      i += 1;
      continue;
    }
    if (arg === '--limit') {
      const raw = args[i + 1];
      const parsed = Number(raw);
      out.limit = Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 100;
      i += 1;
      continue;
    }
    if (arg === '--dry-run') {
      out.dryRun = true;
      continue;
    }
    if (!out.url && !arg.startsWith('--')) {
      out.url = arg;
    }
  }

  return out;
}

function postJson(url, obj) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const body = JSON.stringify(obj);
    const opts = {
      hostname: u.hostname,
      port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: u.pathname + (u.search || ''),
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };
    const lib = u.protocol === 'https:' ? https : http;
    const req = lib.request(opts, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data || '{}');
          resolve(parsed);
        } catch (err) {
          reject(new Error('Invalid JSON response: ' + err.message + '\n' + data));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0) {
    console.error('Usage: adrablox-studio <command> [args]');
    console.error('Commands: health | list | call | ws-tail | open-session | read-tree | get-properties | apply-patch | set-name | conflict-recover');
    process.exit(2);
  }
  const cmd = argv[0];
  const url = process.env.MCP_ENDPOINT || 'http://127.0.0.1:44877/mcp';

  try {
    if (cmd === 'health') {
      const initPayload = { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25', capabilities: { resources: { subscribe: true }, tools: {} }, clientInfo: { name: 'studio-cli-health', version: '0.1.0' } } };
      const initResp = await postJson(url, initPayload);
      console.log('initialize ->', JSON.stringify(initResp.result || initResp, null, 2));

      const listPayload = { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} };
      const listResp = await postJson(url, listPayload);
      console.log('tools/list ->', JSON.stringify(listResp.result || listResp, null, 2));
      return;
    }

    if (cmd === 'list') {
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp, null, 2));
      return;
    }

    if (cmd === 'call') {
      const name = argv[1];
      const args = argv[2] ? JSON.parse(argv[2]) : {};
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp, null, 2));
      return;
    }

    if (cmd === 'ws-tail') {
      // Usage: ws-tail [url] [--auth-token token] [--since seq] [--limit n] [--dry-run]
      const parsed = parseWsTailArgs(argv.slice(1));
      const endpoint = process.env.MCP_ENDPOINT || 'http://127.0.0.1:44877/mcp';
      const defaultPushUrl = endpoint.replace(/^http/, 'ws').replace(/\/mcp$/, '/mcp-stream');
      const defaultRpcUrl = endpoint.replace(/^http/, 'ws').replace(/\/mcp$/, '/mcp-stream/ws-rpc');
      const wsUrl = parsed.url || (parsed.since != null ? defaultRpcUrl : defaultPushUrl);

      if (parsed.dryRun) {
        console.log(JSON.stringify({
          command: 'ws-tail',
          wsUrl,
          hasAuthToken: !!parsed.authToken,
          since: parsed.since,
          limit: parsed.limit,
        }, null, 2));
        return;
      }

      try {
        const WebSocket = require('ws');
        const options = {};
        if (parsed.authToken) {
          options.headers = {
            Authorization: `Bearer ${parsed.authToken}`,
          };
          options.protocol = `bearer,${parsed.authToken}`;
        }

        const ws = new WebSocket(wsUrl, options);
        ws.on('open', () => {
          console.log('ws open', wsUrl);
          if (parsed.since != null) {
            ws.send(JSON.stringify({ cmd: 'replay', since: parsed.since, limit: parsed.limit }));
          }
        });
        ws.on('message', (data) => console.log(data.toString()));
        ws.on('close', () => process.exit(0));
        ws.on('error', (err) => { console.error('ws error', err.message); process.exit(3); });
      } catch (e) {
        console.error('WebSocket support requires the "ws" package. Install with: npm install in studio_action_scripts/cli');
        process.exit(2);
      }
      return;
    }

    if (cmd === 'open-session') {
      const projectPath = argv[1] || 'src';
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.openSession', arguments: { projectPath } } };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp, null, 2));
      return;
    }

    if (cmd === 'read-tree') {
      const sessionId = argv[1];
      const instanceId = argv[2];
      if (!sessionId || !instanceId) {
        console.error('Usage: adrablox-studio read-tree <sessionId> <instanceId>');
        process.exit(2);
      }
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.readTree', arguments: { sessionId, instanceId } } };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp, null, 2));
      return;
    }

    if (cmd === 'get-properties') {
      const sessionId = argv[1];
      const instanceId = argv[2];
      if (!sessionId || !instanceId) {
        console.error('Usage: adrablox-studio get-properties <sessionId> <instanceId>');
        process.exit(2);
      }
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.readObject', arguments: { sessionId, instanceId } } };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp, null, 2));
      return;
    }

    if (cmd === 'apply-patch') {
      const sessionId = argv[1];
      const patchId = argv[2] || 'cli_patch_001';
      const baseCursor = argv[3] || null;
      const origin = argv[4] || 'cli';
      const opsJson = argv[5] || '[]';
      const operations = opsJson ? JSON.parse(opsJson) : [];
      const args = { sessionId, patchId, baseCursor, origin, operations };
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.applyPatch', arguments: args } };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp, null, 2));
      return;
    }

    if (cmd === 'set-name') {
      const sessionId = argv[1];
      const instanceId = argv[2];
      const name = argv[3];
      if (!sessionId || !instanceId || !name) {
        console.error('Usage: adrablox-studio set-name <sessionId> <instanceId> <name>');
        process.exit(2);
      }
      const operations = [{ op: 'setName', instanceId, name }];
      const args = { sessionId, patchId: 'set_name_cli', baseCursor: null, origin: 'cli-set-name', operations };
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.applyPatch', arguments: args } };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp, null, 2));
      return;
    }

    if (cmd === 'conflict-recover') {
      // Usage: conflict-recover <sessionId> '<operationsJson>' [baseCursor]
      const sessionId = argv[1];
      const opsJson = argv[2] || '[]';
      const baseCursor = argv[3] || null;
      if (!sessionId) {
        console.error('Usage: adrablox-studio conflict-recover <sessionId> "<operationsJson>" [baseCursor]');
        process.exit(2);
      }
      let operations = [];
      try { operations = opsJson ? JSON.parse(opsJson) : []; } catch (e) { console.error('Invalid operations JSON:', e.message); process.exit(2); }
      const patchId = 'cli_conflict_recover_' + Date.now();
      const args = { sessionId, patchId, baseCursor, origin: 'cli-conflict-recover', operations };
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.applyPatch', arguments: args } };
      const resp = await postJson(url, payload);
      if (resp && resp.error) {
        console.error('applyPatch error:', JSON.stringify(resp.error, null, 2));
        const newBase = resp.error && resp.error.data && resp.error.data.latestCursor ? resp.error.data.latestCursor : null;
        if (newBase) {
          console.log('Detected conflict. Retrying with latest cursor:', newBase);
          args.baseCursor = newBase;
          const retry = { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'roblox.applyPatch', arguments: args } };
          const resp2 = await postJson(url, retry);
          console.log(JSON.stringify(resp2, null, 2));
          return;
        }
        process.exit(3);
      }
      console.log(JSON.stringify(resp.result || resp, null, 2));
      return;
    }

    if (cmd === 'snapshot-export') {
      // Usage: snapshot-export <sessionId> [outFile]
      const sessionId = argv[1];
      const outFile = argv[2] || null;
      if (!sessionId) {
        console.error('Usage: adrablox-studio snapshot-export <sessionId> [outFile]');
        process.exit(2);
      }
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.exportSnapshot', arguments: { sessionId } } };
      const resp = await postJson(url, payload);
      const content = resp.result || resp;
      if (outFile) {
        try {
          fs.writeFileSync(outFile, JSON.stringify(content, null, 2), 'utf8');
          console.log('Wrote snapshot to', outFile);
        } catch (e) {
          console.error('Failed to write file:', e.message);
          process.exit(3);
        }
      } else {
        console.log(JSON.stringify(content, null, 2));
      }
      return;
    }

    if (cmd === 'snapshot-import') {
      // Usage: snapshot-import <sessionId> <inFile>
      const sessionId = argv[1];
      const inFile = argv[2];
      if (!sessionId || !inFile) {
        console.error('Usage: adrablox-studio snapshot-import <sessionId> <inFile>');
        process.exit(2);
      }
      let data;
      try { data = JSON.parse(fs.readFileSync(inFile, 'utf8')); } catch (e) { console.error('Failed to read/parse snapshot:', e.message); process.exit(3); }
      // If the snapshot was exported via tools/call wrapper, unwrap structuredContent
      if (data && data.structuredContent) {
        data = data.structuredContent;
      } else if (data && data.result && data.result.structuredContent) {
        data = data.result.structuredContent;
      }
      const payload = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'roblox.importSnapshot', arguments: { sessionId, snapshot: data } } };
      const resp = await postJson(url, payload);
      console.log(JSON.stringify(resp.result || resp, null, 2));
      return;
    }

    console.error('Unknown command:', cmd);
    process.exit(2);
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(3);
  }
}

main();
