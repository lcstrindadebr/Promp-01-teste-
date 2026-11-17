const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run('function loadAmigozTables(){};function tickMonitoring(){};function loadApiTokens(){};function loadApiDocs(){};');
 run(fs.readFileSync('dist/settings.js','utf8'));run(fs.readFileSync('dist/dashboard.js','utf8'));
 let calls=0;const health={gerado_em:new Date().toISOString(),manutencao_ate:null,servicos:[
  {servico:'digimais_saldo_parcela',na_fila:120,consultando:0,espera_minutos:42,concluidas_hora:0,falhas_hora:0,ultima_conclusao:new Date(Date.now()-50*60000).toISOString(),parada:true},
  {servico:'tjba_margem',na_fila:0,consultando:2,espera_minutos:null,concluidas_hora:18,falhas_hora:1,ultima_conclusao:new Date().toISOString(),parada:false}]};
 t.handler(async url=>{if(String(url).includes('admin_queue_health')){calls++;return response(health);}return response([]);});
 run("authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600};currentAccess={role:'partner',active:true,services:[]};");
 run(fs.readFileSync('dist/queue-health.js','utf8'));
 await new Promise(r=>setTimeout(r,0));
 assert.equal(calls,0,'Partners never ask for queue health');
 assert.equal(t.window.document.querySelector('.queue-health').hidden,true);
 // ApoiarCred team on Início: the stalled queue shows as an alert.
 run("currentAccess={role:'admin',active:true,services:[]};navigate('dashboard');");
 for(let i=0;i<5;i++)await new Promise(r=>setTimeout(r,0));
 assert.equal(calls,1);
 const banner=t.window.document.querySelector('.queue-stalled-banner');
 assert.equal(banner.hidden,false);assert.match(banner.textContent,/Digi\+ · Saldo e parcela: 120 esperando/);
 assert.doesNotMatch(banner.textContent,/ConsigX/,'Moving service is not in the alert');
 // The card in Robôs shows both services and the status.
 banner.querySelector('[data-queue-open]').click();
 for(let i=0;i<5;i++)await new Promise(r=>setTimeout(r,0));
 assert.equal(run('currentPage'),'settings');assert.equal(t.get('#settings-robots').hidden,false);
 assert.equal(t.get('#queueHealthStatus').textContent,'Fila parada');
 assert.equal(t.get('#queueHealthRows').rows.length,2);
 assert.match(t.get('#queueHealthRows').textContent,/42 min/);
 console.log('queue health frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});
