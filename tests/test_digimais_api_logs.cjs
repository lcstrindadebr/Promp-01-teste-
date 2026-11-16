const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup}=require('./test_frontend.cjs');
// Real page in jsdom: settings.js builds the Configurações sections, digimais-pilot.js fills the API log.
(async()=>{
const t=setup(),run=code=>vm.runInContext(code,t.ctx),$=s=>t.window.document.querySelector(s);
run('function loadAmigozTables(){};function loadApiTokens(){};function loadApiDocs(){};function applyAccessUi(){};');
for(const file of ['monitoramento','settings'])run(fs.readFileSync('dist/'+file+'.js','utf8')); // page order
run(fs.readFileSync('dist/digimais-pilot.js','utf8'));
run(`authenticated=true;currentAccess={active:true,role:'admin'};records=[
 {execution_mode:'robot',cpf:'ROBOT'},
 {execution_mode:'api',api_slot:2,cpf:'API_CLIENT',date:'2026-11-11',status:'Revisão',resultado_saldo:{sucesso:false,etapa:'autenticação',motivo_interrupcao:'HTTP_429',eventos:[{horario:'2026-11-11',etapa:'autenticação',status:'interrompida'}],http_status:429,erro:'HTTP 429',todasMensagens:['<script>unsafe</script>']}},
 {execution_mode:'api',cpf:'QUEUED',status:'Aguardando'},{execution_mode:'api',cpf:'RUNNING',status:'Processando'},
 {execution_mode:'robot',cpf:'ROBOT_QUEUE',status:'Aguardando'},{execution_mode:'robot',cpf:'ROBOT_DONE',status:'Concluída'}];`);
assert.deepEqual(Array.from(run('consultationLogRecords()'),r=>r.cpf),['ROBOT_DONE']);
const log=()=>$('#digiApiLogContent').textContent;
// The log is built only while Configurações → Log da API Digi+ is open, from finished attempts.
run("currentPage='settings';switchSettings('digimais-api')");
const refresh=async()=>{run('digiLogEpoch=-1');await run('renderDigiApiLogs()');};
await refresh();
assert(!log().includes('QUEUED'));assert(!log().includes('RUNNING'),'Running API calls are not finished attempts');assert(log().includes('API_CLIENT'));assert(!log().includes('ROBOT'));
assert(log().includes('HTTP: 429'));assert(log().includes('<script>unsafe</script>'));
assert(log().includes('Motivo da interrupção: HTTP_429'));assert(log().includes('Etapa: autenticação'));assert.equal($('#settings-tab-digimais-api').hidden,false);
$('#digiApiLogSlot').value='1';await refresh();assert(!log().includes('API_CLIENT'));
$('#digiApiLogSlot').value='2';await refresh();assert(log().includes('API_CLIENT'));
run('authenticated=false;applyAccessUi()');assert.equal(log(),'');
assert.equal($('#settings-tab-digimais-api').hidden,true);
run("authenticated=true;currentAccess.role='partner';renderLogs()");assert.equal(log(),'');
console.log('PASS: API-only finished attempts, executor filter, literal response text, HTTP error, logout and admin restriction');
})().catch(e=>{console.error(e);process.exitCode=1});
