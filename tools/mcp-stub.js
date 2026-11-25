const readline = require('node:readline');

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
const version = process.env.HYPERAGENT_STUB_VERSION || 'witness';

rl.on('line', line => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }
  if (!message || typeof message !== 'object' || typeof message.method !== 'string') {
    return;
  }
  if (message.method.startsWith('notifications/')) {
    return;
  }
  if (message.id === undefined || message.id === null) {
    return;
  }
  let result = {};
  if (message.method === 'initialize') {
    result = {
      protocolVersion: '2025-06-18',
      capabilities: { tools: {}, resources: {}, prompts: {} },
      serverInfo: { name: 'hyperagent', version }
    };
  } else if (message.method === 'tools/list') {
    result = { tools: [] };
  } else if (message.method === 'resources/list') {
    result = { resources: [] };
  } else if (message.method === 'prompts/list') {
    result = { prompts: [] };
  }
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: message.id, result }) + '\n');
});
