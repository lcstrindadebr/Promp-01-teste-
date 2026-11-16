const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {JSDOM}=require('jsdom');
// The real dist/index.html in jsdom, with the Supabase calls answered by `handler`.
// Scripts run in the page's VM context, like separate <script> tags (shared top-level let/const).
function setup(stored){
 const html=fs.readFileSync('dist/index.html','utf8').replace(/<script\b[^>]*><\/script>/g,'');
 const dom=new JSDOM(html,{url:'https://painel.test/',runScripts:'outside-only',pretendToBeVisual:true});
 const w=dom.window;
 w.SUPABASE_CONFIG={url:'https://test.supabase.co',key:'sb_publishable_test'};
 for(const [key,value] of stored||[])w.sessionStorage.setItem(key,value);
 w.setInterval=()=>0; // Background polling is driven explicitly by the tests.
 if(!w.crypto?.randomUUID)Object.defineProperty(w,'crypto',{value:require('crypto').webcrypto});
 const dialog=w.HTMLDialogElement?.prototype;
 if(dialog&&!dialog.showModal){
  dialog.showModal=function(){this.open=true;};
  dialog.close=function(){this.open=false;this.dispatchEvent(new w.Event('close'));};
 }
 w.HTMLElement.prototype.scrollIntoView=function(){};
 const calls=[];let handler=async()=>({ok:true,status:200,text:async()=>JSON.stringify([])});
 w.fetch=async(u,o)=>{calls.push([u,o]);if(String(u).endsWith('/rpc/my_access'))return {ok:true,status:200,text:async()=>JSON.stringify({role:'admin',active:true,services:[{id:'digimais_saldo_parcela',enabled:true},{id:'tjba_margem',enabled:true}]})};return handler(u,o)};
 const ctx=dom.getInternalVMContext();
 vm.runInContext(fs.readFileSync('dist/app.js','utf8'),ctx);vm.runInContext(fs.readFileSync('dist/supabase.js','utf8'),ctx);
 // Partner limits and guards (the part of partners.js before its DOM wiring), loaded next by the page too.
 vm.runInContext(fs.readFileSync('dist/partners.js','utf8').split('const quotaBox=')[0],ctx);
 const detached=new Map();
 const get=s=>w.document.querySelector(s)||detached.get(s)||detached.set(s,w.document.createElement('div')).get(s);
 return {ctx,get,calls,handler:f=>handler=f,window:w};
}
const response=(data,status=200)=>({ok:status<400,status,text:async()=>JSON.stringify(data)});
// Answers painel_consultas_sync the way the database does: every lot and job as one page.
const syncResponse=(jobs,lots)=>response({snapshot:'1:1:',next:null,rows:[
 ...lots.map(l=>({chave:'consulta_lotes:'+l.id,origem:'consulta_lotes',id:l.id,excluido:false,dados:l})),
 ...jobs.map(j=>({chave:'consulta_jobs:'+j.id,origem:'consulta_jobs',id:j.id,excluido:false,dados:j}))]});
module.exports={setup,response,syncResponse};
if(require.main===module)(async()=>{
 const t=setup();assert.equal(t.calls.length,0,'No data request before login');assert.equal(t.get('#appShell').hidden,true);
 await assert.rejects(vm.runInContext('add([{nome:"X",cpf:"00000000000",telefone:"11999999999"}])',t.ctx),/Entre/);
 t.handler(async u=>u.includes('/token?')?response({access_token:'test',refresh_token:'test',expires_in:3600,user:{id:'user1',email:'test@example.com'}}):response([]));
 t.get('#email').value='test@example.com';t.get('#password').value='password';await t.get('#login').onsubmit({preventDefault(){}});assert.equal(t.get('#appShell').hidden,false);assert.equal(t.get('#loginPage').hidden,true);
 await t.get('#logout').onclick();assert.equal(t.get('#appShell').hidden,true);assert.equal(t.get('#loginPage').hidden,false);
 const bad=setup();bad.handler(async()=>response({error_code:'invalid_credentials',msg:'Invalid login credentials'},400));bad.get('#email').value='test@example.com';bad.get('#password').value='wrong';await bad.get('#login').onsubmit({preventDefault(){}});assert.equal(bad.get('#appShell').hidden,true);assert.match(bad.get('#loginError').textContent,/inválidos/);
 const stale=setup([['apoiarcred-auth:https://test.supabase.co',JSON.stringify({access_token:'revoked',refresh_token:'x',expires_at:Date.now()/1000+3600})]]);stale.handler(async()=>response({},401));await new Promise(setImmediate);assert.equal(stale.get('#appShell').hidden,true,'Revoked stored session must not open dashboard');
 t.get('#consultationLogPanel').open=true; // The robot log is only built while its panel is open.
 vm.runInContext("records=[{id:'job',nome:'CLIENTE',cpf:'00123456789',status:'Processando',progress:70,stage:'CPF enviado',date:'2026-10-30T20:00:00Z'}];render()",t.ctx);
 assert(t.get('#rows').innerHTML.includes('value="70"'));assert(t.get('#rows').innerHTML.includes('70%'));assert(!t.get('#rows').innerHTML.includes('CPF enviado'));assert(t.get('#rows').innerHTML.includes('Consultando...'));assert(!t.get('#consultationLogs').textContent.includes('CPF enviado'));
 vm.runInContext("records=[{id:'job',nome:'CLIENTE',cpf:'00123456789',status:'Não é cliente',progress:100,stage:'Não é cliente',date:'2026-10-30T20:00:00Z'}];render()",t.ctx);
 assert(t.get('#consultationLogs').textContent.includes('Não é cliente'));assert(t.get('#rows').innerHTML.includes('value="100"'));assert(t.get('#rows').innerHTML.includes('Não é cliente'));
 vm.runInContext("records=[{id:'job',nome:'CLIENTE',status:'Revisão',saldo:1234.56,parcelas:24,valorParcela:123.4,date:'2026-10-30T20:00:00Z'}];render()",t.ctx);
 assert(t.get('#rows').innerHTML.includes('123,40'));assert(t.get('#rows').innerHTML.includes('1.234,56'));
 vm.runInContext("records=[{id:'job',nome:'CLIENTE',cpf:'00123456789',status:'Erro',progress:40,stage:'Selecionar empréstimo consignado',message:'Tempo excedido: detalhe técnico <img src=x>',date:'2026-10-30T20:00:00Z'}];render()",t.ctx);
 assert(!t.get('#rows').innerHTML.includes('Selecionar empréstimo'));assert(!t.get('#rows').innerHTML.includes('detalhe técnico'));
 assert(t.get('#consultationLogs').textContent.includes('detalhe técnico <img src=x>'));
 vm.runInContext("records=[{status:'Erro',cpf:'fixture-one',robot_slot:1,message:'Falha do primeiro'},{status:'Erro',cpf:'fixture-two',robot_slot:2,message:'Falha do segundo'},{status:'Concluída',cpf:'fixture-legacy',message:'Histórico'}]",t.ctx);
 t.get('#consultationLogRobot').value='2';t.get('#consultationLogRobot').onchange();
 assert(t.get('#consultationLogs').textContent.includes('Robô 2'));
 assert(t.get('#consultationLogs').textContent.includes('Falha do segundo'));
 assert(!t.get('#consultationLogs').textContent.includes('Falha do primeiro'));
 t.get('#consultationLogRobot').value='unassigned';t.get('#consultationLogRobot').onchange();
 assert(t.get('#consultationLogs').textContent.includes('fixture-legacy'));
 assert(!t.get('#consultationLogs').textContent.includes('fixture-two'));
 await t.get('#logout').onclick();assert.equal(t.get('#consultationLogs').textContent,'Nenhuma consulta encerrada para este filtro.');assert.equal(t.get('#consultationLogPanel').open,false);
 const html=fs.readFileSync('dist/index.html','utf8');assert(/<details id="consultationLogPanel"(?![^>]*\bopen\b)/.test(html));
 const rows=vm.runInContext('csvParse("nome;cpf;telefone\\nCliente;00123456789;11999999999")',t.ctx);assert.equal(rows[1][1],'00123456789');
 const model=fs.readFileSync('dist/modelo-importacao.csv','utf8');assert(model.includes('nome;cpf;telefone'));
 assert(fs.readFileSync('dist/index.html','utf8').includes('href="modelo-importacao.csv" download'));
 assert(!fs.readFileSync('dist/index.html','utf8').includes('id="mode"'));console.log('PASS: login gate, login failure, logout, revoked session, authenticated-only requests, CSV and no mode selector');
})().catch(e=>{console.error(e);process.exitCode=1});
