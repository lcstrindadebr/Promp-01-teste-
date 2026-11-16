const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();t.ctx.document.createElement=()=>({hidden:false,innerHTML:'',className:''});t.get('#settings-robots').prepend=()=>{};t.get('#settings-digimais-api').append=()=>{};t.get('#digiPilotMode').setAttribute=()=>{};t.get('#consultationLogPanel').addEventListener=()=>{};
 vm.runInContext('function applyAccessUi(){};function switchSettings(){};function resetApiSettings(){};function renderMonitoring(){};function robotDuration(v){return String(v)};let monitoringSnapshot=null;',t.ctx);
 vm.runInContext(fs.readFileSync('dist/digimais-pilot.js','utf8'),t.ctx);
 vm.runInContext("authenticated=true;session={access_token:'fixture',expires_at:Date.now()/1000+3600};currentAccess={active:true,role:'partner'}",t.ctx);
 await vm.runInContext('loadDigiPilot()',t.ctx);assert.equal(t.calls.length,0);assert.equal(vm.runInContext('digiPilot.hidden',t.ctx),true);
 t.handler(async()=>response({mode:'api',paused:false,max_concurrency:12}));vm.runInContext("currentAccess.role='admin'",t.ctx);await vm.runInContext('loadDigiPilot()',t.ctx);
 assert.equal(vm.runInContext('digiPilot.hidden',t.ctx),false);assert.equal(t.get('#digiPilotMode').value,'1');assert.equal(t.get('#digiPilotMax').value,12);
 assert.match(vm.runInContext('digiPilot.innerHTML',t.ctx),/max="50"/);
 assert.match(vm.runInContext('digiApiLog.innerHTML',t.ctx),/value="50">API 50/);
 t.get('#digiPilotPaused').checked=true;t.get('#digiPilotMax').value=50;
 await t.get('#digiPilotForm').onsubmit({preventDefault(){}});
 assert.deepEqual(JSON.parse(t.calls.at(-1)[1].body),{p_mode:'api',p_paused:true,p_max:50});
 let releaseDetails;
 t.handler(()=>new Promise(resolve=>{releaseDetails=resolve;}));
 t.get('#settings-digimais-api').hidden=false;
 vm.runInContext(`currentPage='settings';records=[
  {id:'job-1',execution_mode:'api',status:'Revisão',date:'2026-11-12T04:00:00Z',cpf:'000.000.000-00',message:'Resumo da primeira consulta'},
  {id:'job-2',execution_mode:'api',status:'Aguardando',date:'2026-11-12T04:01:00Z',cpf:'000.000.000-00',api_handoff:{api_slot:50,message:'Encaminhamento'}}
 ];`,t.ctx);
 const before=t.calls.length;
 const loading=vm.runInContext('renderDigiApiLogs()',t.ctx);
 await new Promise(setImmediate);
 assert.equal(t.calls.length,before+1);
 assert.match(t.calls.at(-1)[0],/id=in\.\(job-2%2Cjob-1\)/);
 assert.match(t.get('#digiApiLogContent').textContent,/Resumo da primeira consulta/);
 assert.match(t.get('#digiApiLogContent').textContent,/Encaminhada ao robô/);
 vm.runInContext('records=records.map(row=>({...row}));renderDigiApiLogs()',t.ctx);
 assert.equal(t.calls.length,before+1,'A atualização da fila não reinicia a busca em andamento');
 t.handler(async()=>response({message:'Falha de conexão'},503));
 releaseDetails(response([{id:'job-1',message:'Detalhe da consulta'}]));
 await loading;
 await new Promise(setImmediate);
 assert.match(t.get('#digiApiLogContent').textContent,/Resumo da primeira consulta/);
 assert.match(t.get('#digiApiLogContentCount').textContent,/Detalhes indisponíveis/);
 vm.runInContext('resetApiSettings()',t.ctx);assert.equal(vm.runInContext('digiPilot.hidden',t.ctx),true);
 assert.equal(vm.runInContext('digiPilotEpoch',t.ctx),-1);
 console.log('PASS: admin pilot visibility, load, save, pause and logout reset');
})().catch(e=>{console.error(e);process.exitCode=1});
