const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();t.ctx.document.createElement=()=>({hidden:false,innerHTML:'',className:''});t.get('#settings-robots').prepend=()=>{};t.get('#digiPilotMode').setAttribute=()=>{};
 vm.runInContext('function applyAccessUi(){};function switchSettings(){};function resetApiSettings(){};function renderMonitoring(){};function robotDuration(v){return String(v)};let monitoringSnapshot=null;',t.ctx);
 vm.runInContext(fs.readFileSync('dist/digimais-pilot.js','utf8'),t.ctx);
 vm.runInContext("authenticated=true;session={access_token:'fixture',expires_at:Date.now()/1000+3600};currentAccess={active:true,role:'partner'}",t.ctx);
 await vm.runInContext('loadDigiPilot()',t.ctx);assert.equal(t.calls.length,0);assert.equal(vm.runInContext('digiPilot.hidden',t.ctx),true);
 t.handler(async()=>response({mode:'api',paused:false,max_concurrency:12}));vm.runInContext("currentAccess.role='admin'",t.ctx);await vm.runInContext('loadDigiPilot()',t.ctx);
 assert.equal(vm.runInContext('digiPilot.hidden',t.ctx),false);assert.equal(t.get('#digiPilotMode').value,'1');assert.equal(t.get('#digiPilotMax').value,12);
 t.get('#digiPilotPaused').checked=true;t.get('#digiPilotMax').value=4;
 await t.get('#digiPilotForm').onsubmit({preventDefault(){}});
 assert.deepEqual(JSON.parse(t.calls.at(-1)[1].body),{p_mode:'api',p_paused:true,p_max:4});
 vm.runInContext('resetApiSettings()',t.ctx);assert.equal(vm.runInContext('digiPilot.hidden',t.ctx),true);
 assert.equal(vm.runInContext('digiPilotEpoch',t.ctx),-1);
 console.log('PASS: admin pilot visibility, load, save, pause and logout reset');
})().catch(e=>{console.error(e);process.exitCode=1});
