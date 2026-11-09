const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const dist = path.resolve(__dirname, '../dist');
const html = fs.readFileSync(path.join(dist, 'index.html'), 'utf8');
const scripts = [...html.matchAll(/<script src="([^"?]+)(?:\?[^"]*)?"/g)]
  .map(([, source]) => source)
  .filter(source => source !== 'supabase-config.js' && !source.startsWith('vendor/'));

if (!scripts.includes('amigoz-api.js')) throw Error('O painel precisa carregar a integração Amigoz.');
const combined = scripts.map(source => fs.readFileSync(path.join(dist, source), 'utf8')).join('\n;\n');
new vm.Script(combined);
console.log('PASS: scripts do painel compilam no mesmo escopo global');
