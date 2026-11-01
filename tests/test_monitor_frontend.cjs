const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();vm.runInContext(fs.readFileSync('dist/monitoramento.js','utf8'),t.ctx);
 await vm.runInContext('tickMonitoring()',t.ctx);assert.equal(t.calls.length,0);
 vm.runInContext("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600,user:{id:'u'}};currentPage='home'",t.ctx);await vm.runInContext('tickMonitoring()',t.ctx);assert.equal(t.calls.length,0);
 const data={updated_at:new Date().toISOString(),payload:{cpu_percent:25,cpu_count:2,memory:{percent:50,total:2147483648,used:1073741824,available:1073741824,swap_total:0,swap_used:0},disk:{percent:20,total:100,used:20},uptime_seconds:90000,worker:'active',robot_mode:'disabled'}};
 t.handler(async()=>response([data]));vm.runInContext("currentPage='settings'",t.ctx);await vm.runInContext('tickMonitoring()',t.ctx);
 assert.equal(t.get('#monitorStatus').textContent,'Atualizado');assert.equal(t.get('#monitorWorker').textContent,'Ativo');assert.equal(t.get('#monitorMode').textContent,'Consultas desativadas');assert(t.get('#monitorMetrics').innerHTML.includes('Não configurada'));
 vm.runInContext("monitoringSnapshot.updated_at='2020-01-01';renderMonitoring()",t.ctx);assert.equal(t.get('#monitorStatus').textContent,'Dados desatualizados');
 t.handler(async()=>response({},500));await vm.runInContext('tickMonitoring()',t.ctx);assert.equal(t.get('#monitorStatus').textContent,'Sem conexão');
 vm.runInContext('showLogin()',t.ctx);assert.equal(t.get('#monitorWorker').textContent,'—');
 console.log('PASS: authenticated settings-only monitoring, stale and error states, robot mode and logout');
})().catch(e=>{console.error(e);process.exitCode=1});
