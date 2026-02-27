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
