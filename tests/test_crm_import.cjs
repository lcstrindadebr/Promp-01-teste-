const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const app = fs.readFileSync('dist/app.js','utf8');
const context = vm.createContext({$:() => ({})});
vm.runInContext(app.slice(app.indexOf('function csvParse('), app.indexOf("$('#single').onsubmit")), context);
vm.runInContext(app.slice(app.indexOf('function importHeader('), app.indexOf('function validateImportClassification(')), context);
vm.runInContext(fs.readFileSync('dist/crm-import.js','utf8'), context);
const read = (content, state = 'BA', agreement = 'TJBA') =>
  context.crmReadClientFile({name:'base.csv', size:content.length, text:async () => content},state,agreement);

test('imports CPF and optional contact fields, preserving leading zeros', async () => {
  const rows = await read('cpf;nome;telefone;estado;convênio\n000.000.001-01;Teste;(75) 99999-9999;Bahia;TJBA');
  assert.equal(JSON.stringify(rows),'[{"cpf":"00000000101","nome":"Teste","telefone":"75999999999"}]');
});

test('rejects mismatched region and duplicate CPF without partial import', async () => {
  await assert.rejects(read('cpf;uf\n00000000101;SP'),/estado diferente/);
  await assert.rejects(read('cpf;convênio\n00000000101;Outro'),/convênio diferente/);
  await assert.rejects(read('cpf\n00000000101\n000.000.001-01'),/CPF repetido/);
});

test('accepts the provider code or catalog display name in an imported row', async () => {
  for (const name of ['amigoz_33', 'Polícia Militar - São Paulo']) {
    const csv = 'cpf;estado;convênio\n00000000101;São Paulo;' + name;
    const rows = await context.crmReadClientFile(
      {name:'base.csv',size:csv.length,text:async () => csv},
      'SP','amigoz_33','Polícia Militar - São Paulo'
    );
    assert.equal(rows[0].cpf,'00000000101');
  }
});
