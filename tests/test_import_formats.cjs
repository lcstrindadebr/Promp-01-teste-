const fs=require('fs'),vm=require('vm'),assert=require('assert');
const XLSX=require('../dist/vendor/xlsx-0.20.3.min.js');
const {setup,response}=require('./test_frontend.cjs');
function excelFile(bookType,rows){const book=XLSX.utils.book_new();XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet(rows),'Clientes');const bytes=XLSX.write(book,{bookType,type:'buffer'});return {name:'clientes.'+(bookType==='biff8'?'xls':'xlsx'),size:bytes.length,arrayBuffer:async()=>bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength)};}
function textFile(name,text){return {name,size:Buffer.byteLength(text),text:async()=>text};}
(async()=>{
 let count=0;
 for(const file of [
 textFile('clientes.csv','nome;cpf;telefone\nCLIENTE TESTE;00123456789;11999999999'),
 textFile('clientes.csv','\uFEFF"nome","cpf","telefone"\r\n"CLIENTE, TESTE","00123456789","(11) 99999-9999"'),
 textFile('clientes.csv','sep=;\r\nnome;cpf;telefone\r\nCLIENTE TESTE;00123456789;11999999999'),
 textFile('clientes.tsv','nome\tcpf\ttelefone\nCLIENTE TESTE\t00123456789\t11999999999'),
 excelFile('xlsx',[['nome','cpf','telefone'],['CLIENTE TESTE','00123456789','11999999999']]),
 excelFile('biff8',[['Nome completo','CPF','Telefone com DDD'],['CLIENTE TESTE',123456789,11999999999]])]){
 const t=setup();t.ctx.XLSX=XLSX;let payload;
 vm.runInContext("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600,user:{id:'u'}}",t.ctx);
 t.handler(async(u,o)=>{if(u.includes('/rpc/create_consulta_campaign')){payload=JSON.parse(o.body);return response('new-campaign');}return response([]);});
 await t.get('#file').onchange({target:{files:[file]}});
 assert.equal(vm.runInContext('pending.length',t.ctx),1,file.name+': '+t.get('#importStatus').textContent);
 assert(t.get('#import').disabled,'Name required');t.get('#campaignName').value='Campanha '+file.name;t.get('#campaignName').oninput();assert(!t.get('#import').disabled);
 await t.get('#import').onclick();assert.equal(payload.p_items[0].cpf,'00123456789');assert.equal(payload.p_items[0].telefone,'11999999999');assert(t.get('#import').disabled);count++;
 }
 const t=setup();t.ctx.XLSX=XLSX;t.get('#campaignName').value='Teste';
 for(const [file,reason] of [
 [textFile('modelo.csv',fs.readFileSync('dist/modelo-importacao.csv','utf8')),'Nenhum cliente válido'],
 [textFile('vazio.csv','nome;cpf;telefone'),'apenas o cabeçalho'],
 [textFile('errado.csv','nome;cpf\nTESTE;00123456789'),'Colunas ausentes'],
 [textFile('errado.csv','nome;cpf;telefone\nTESTE;00123456789;123'),'Nenhum cliente válido'],
 [textFile('errado.pdf','fake'),'Formato não suportado'],
 [excelFile('xlsx',[['nome','cpf','telefone'],...Array.from({length:1001},()=>['TESTE','00123456789','11999999999'])]),'até 1.000'],
 [{name:'corrompido.xlsx',size:4,arrayBuffer:async()=>new Uint8Array([80,75,0,0]).buffer},'Não foi possível abrir']]){
 await t.get('#file').onchange({target:{files:[file]}});assert(t.get('#import').disabled);assert(t.get('#importStatus').textContent.includes(reason),t.get('#importStatus').textContent);t.get('#campaignName').oninput();assert(t.get('#importStatus').textContent.includes(reason),'Name edit must preserve file error');
 }
 // A slow old file must never overwrite the newly selected file.
 let release;const slow={name:'slow.csv',size:100,text:()=>new Promise(r=>release=r)};
 const old=t.get('#file').onchange({target:{files:[slow]}});
 await t.get('#file').onchange({target:{files:[textFile('new.csv','nome;cpf;telefone\nNOVO;00123456789;11999999999')]}});
 release('nome;cpf;telefone\nANTIGO;00123456789;11999999999');await old;assert.equal(vm.runInContext('pending[0].nome',t.ctx),'NOVO');
 console.log(`PASS: ${count} real file variants through upload → enabled button → campaign RPC; invalid/template/header-only/corrupt/oversize-row files; persistent errors; selection race`);
})().catch(e=>{console.error(e);process.exitCode=1});
