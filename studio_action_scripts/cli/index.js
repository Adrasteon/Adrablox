#!/usr/bin/env node
const http = require('http');
const https = require('https');
const { URL } = require('url');

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
        if (cmd === 'apply-patch') {
          // Usage: apply-patch <sessionId> <patchId> <baseCursor> <origin> '<operationsJson>'
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
          // Convenience: setName <sessionId> <instanceId> <name>
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
          const parsed = JSON.parse(data);
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
    console.error('Commands: list | call <name> [jsonArgs]');
    process.exit(2);
  }
  const cmd = argv[0];
  const url = process.env.MCP_ENDPOINT || 'http://127.0.0.1:44877/mcp';

  try {
    if (cmd === 'health') {
      // Initialize then list tools to verify server and plugin reachability
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

    console.error('Unknown command:', cmd);
    process.exit(2);
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(3);
  }
}

main();
