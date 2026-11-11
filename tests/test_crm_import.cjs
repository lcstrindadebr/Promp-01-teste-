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

test('imports reported margin and Amigoz eligibility without treating blank as zero', async () => {
  const rows = await read('cpf;margem_livre;saque_amigoz_elegivel;saque_amigoz_valor\n00000000101;1.234,56;Sim;250,00\n00000000102;0;Não;');
  assert.equal(rows[0].margem_livre,1234.56);
  assert.equal(rows[0].saque_amigoz_elegivel,true);
  assert.equal(rows[0].saque_amigoz_valor,250);
  assert.equal(rows[1].margem_livre,0);
  assert.equal(rows[1].saque_amigoz_elegivel,false);
  assert.equal(rows[1].saque_amigoz_valor,undefined);
  await assert.rejects(read('cpf;saque_amigoz_elegivel;saque_amigoz_valor\n00000000101;Não;50'),/incompatíveis/);
});

test('downloads a real Excel template with exactly the import columns', () => {
  const sheetContext=vm.createContext({});
  vm.runInContext(fs.readFileSync('dist/vendor/xlsx-0.20.3.min.js','utf8'),sheetContext);
  const xlsx=sheetContext.XLSX;
  const book=xlsx.read(fs.readFileSync('dist/modelo-clientes.xlsx'),{type:'buffer',sheetRows:10002});
  assert.equal(book.SheetNames[0],'Clientes');
  const sheet=book.Sheets.Clientes;
  const rows=xlsx.utils.sheet_to_json(sheet,{header:1,blankrows:false});
  const expected=fs.readFileSync('dist/modelo-clientes.csv','utf8').trim().split(';');
  assert.equal(JSON.stringify(rows),JSON.stringify([expected]));
  assert(xlsx.utils.decode_range(sheet['!fullref']||sheet['!ref']).e.r<=10000);
});

test('filled agreement workbooks round-trip through the Excel import', async () => {
  vm.runInContext(fs.readFileSync('dist/vendor/xlsx-0.20.3.min.js','utf8'),context);
  const agreements=[
    {uf:'BA',codigo:'saeb',nome:'Governo da Bahia',servicos:['consigx_margem']},
    {uf:'SP',codigo:'amigoz_23',nome:'Governo de São Paulo',servicos:['amigoz_margem','amigoz_saque','digimais_saldo']}
  ];
  for (const agreement of agreements) {
    const rows=context.crmAgreementTemplate(agreement,true);
    const book=context.crmAgreementWorkbook(agreement,rows,true);
    const buffer=context.XLSX.write(book,{type:'array',bookType:'xlsx',compression:true});
    assert.equal(book.SheetNames.join(','),'Clientes,Como preencher');
    const [client]=await context.crmReadClientFile({name:'exemplo.xlsx',size:buffer.byteLength,arrayBuffer:async()=>buffer},
      agreement.uf,agreement.codigo,agreement.nome,agreement.servicos);
    assert.equal(client.margem_emprestimo,180.50);
    assert.equal(client.margem_cartao,65.20);
    assert.equal(client.numero_matricula,'000123');
    assert.equal(client.saque_amigoz_valor,agreement.uf==='SP'?250:undefined);
  }
  await assert.rejects(context.crmReadClientFile({
    name:'base.csv',size:100,text:async()=> 'cpf;saque_amigoz_elegivel\n00000000892;Sim'
  },'BA','saeb','Governo da Bahia',['consigx_margem']),/Saque Amigoz indisponível/);
});
