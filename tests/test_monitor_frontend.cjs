const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();vm.runInContext(fs.readFileSync('dist/monitoramento.js','utf8'),t.ctx);
 await vm.runInContext('tickMonitoring()',t.ctx);assert.equal(t.calls.length,0);
 vm.runInContext("authenticated=true;session={access_token:'x',expires_at:Date.now()/1000+3600,user:{id:'u'}};currentPage='home'",t.ctx);await vm.runInContext('tickMonitoring()',t.ctx);assert.equal(t.calls.length,0);
 const data={updated_at:new Date().toISOString(),payload:{cpu_percent:25,cpu_count:2,memory:{percent:50,total:2147483648,used:1073741824,available:1073741824,swap_total:0,swap_used:0},disk:{percent:20,total:100,used:20},uptime_seconds:90000,worker:'active',robot_mode:'disabled'}};
 t.handler(async()=>response([data]));vm.runInContext("currentPage='settings'",t.ctx);await vm.runInContext('tickMonitoring()',t.ctx);
 assert.equal(t.get('#monitorStatus').textContent,'Atualizado');assert.equal(t.get('#monitorWorker').textContent,'Ativo');assert.equal(t.get('#monitorMode').textContent,'Consultas desativadas');assert(t.get('#monitorMetrics').innerHTML.includes('Não configurada'));
 data.payload.robot_mode='live';data.payload.robots={updated_at:new Date().toISOString(),started_at:new Date().toISOString(),slots:[{id:'principal',service:'digimais',state:'consulting',progress:35,elapsed_seconds:45,last_activity:new Date().toISOString(),finished_last_hour:10,conclusive_last_hour:8,errors_last_hour:1,review_last_hour:1,average_seconds:30},{id:'digimais-2',service:'digimais',state:'saving',progress:100,elapsed_seconds:40,last_activity:new Date().toISOString(),finished_last_hour:2,conclusive_last_hour:2,errors_last_hour:0,review_last_hour:0,average_seconds:60}]};
 await vm.runInContext('tickMonitoring()',t.ctx);assert(t.get('#robotsCards').innerHTML.includes('Consultando'));assert(t.get('#robotsCards').innerHTML.includes('Salvando resultado'));assert(t.get('#robotsStats').innerHTML.includes('83,3%'));assert(t.get('#robotsStats').innerHTML.includes('35s'));
 data.payload.robots.updated_at='2020-01-01';await vm.runInContext('tickMonitoring()',t.ctx);assert.equal(t.get('#robotsStatus').textContent,'Sem comunicação');assert(!t.get('#robotsCards').innerHTML.includes('>Consultando<'));
 vm.runInContext("monitoringSnapshot.updated_at='2020-01-01';renderMonitoring()",t.ctx);assert.equal(t.get('#monitorStatus').textContent,'Dados desatualizados');
 t.handler(async()=>response({},500));await vm.runInContext('tickMonitoring()',t.ctx);assert.equal(t.get('#monitorStatus').textContent,'Sem conexão');
 vm.runInContext('showLogin()',t.ctx);assert.equal(t.get('#monitorWorker').textContent,'—');assert(!t.get('#robotsCards').innerHTML.includes('Executor 1'));
 console.log('PASS: authenticated settings-only monitoring, stale and error states, robot mode and logout');
})().catch(e=>{console.error(e);process.exitCode=1});
