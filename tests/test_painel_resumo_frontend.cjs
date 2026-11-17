const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup}=require('./test_frontend.cjs');
const json=(data,status=200)=>({ok:status<400,status,json:async()=>data,text:async()=>JSON.stringify(data)});
const tick=()=>new Promise(setImmediate);
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/dashboard.js','utf8'));
 run(fs.readFileSync('dist/painel-resumo.js','utf8'));
 const now=new Date().toISOString();
 // Only one record is loaded in the browser; the database knows about many more.
 run(`currentAccess={role:'partner',active:true,daily_limit:null,remaining:null,services:[{id:'digimais_saldo_parcela',enabled:true,allow_individual:true,allow_campaign:true}]};
 campaigns=[{id:'c1',nome:'Servidores SP',servico:'digimais_saldo_parcela',created_at:'${now}',paused:false}];
 records=[{id:'r1',lote_id:'c1',status:'Aguardando',servico:'digimais_saldo_parcela',nome:'A',cpf:'1',date:'${now}'}];
 authenticated=true;session={access_token:'fixture',expires_at:Date.now()/1000+3600};`);

 // Before the migration the function does not exist: the panel keeps counting locally, and stops asking.
 let calls=0;
 t.handler(async url=>{if(String(url).includes('painel_resumo')){calls++;return json({message:'not found'},404);}return json([]);});
 run("navigate('dashboard')");await tick();await tick();
 assert.equal(calls,1);assert.equal(t.get('#dashQueue').textContent,'1','Local count while the function is missing');
 assert.equal(run('painelResumoState().off'),true);
 run("navigate('home');navigate('dashboard')");await tick();
 assert.equal(calls,1,'No more calls after a 404');

 // With the function: numbers come from the database.
 run('painelResumoOff=false');
 const resumo={contagens:[
   {servico:'digimais_saldo_parcela',tipo:'campanha',status:'aguardando',n:4000},
   {servico:'digimais_saldo_parcela',tipo:'campanha',status:'processando',n:25},
   {servico:'digimais_saldo_parcela',tipo:'campanha',status:'nao_cliente',n:9000},
   {servico:'digimais_saldo_parcela',tipo:'individual',status:'concluida',n:12},
   {servico:'digimais_saldo_parcela',tipo:'individual',status:'erro',n:2},
   {servico:'digimais_saldo_parcela',tipo:'individual',status:'aguardando',n:1},
   {servico:'tjba_margem',tipo:'individual',status:'concluida',n:7},
   {servico:'tjba_margem',tipo:'campanha',status:'revisao',n:30}],
  campanhas_ativas:[{id:'c1',nome:'Servidores SP',servico:'digimais_saldo_parcela',paused:false,created_at:now,total:13025,pendentes:4025}],
  concluidas_hoje:{digimais_saldo_parcela:300,tjba_margem:5},
  atencao:[{id:'far',lote_id:'solo',nome:'Fora da lista',cpf:'00000000191',servico:'digimais_saldo_parcela',status:'erro',data:now}]};
 calls=0;
 t.handler(async url=>{if(String(url).includes('painel_resumo')){calls++;return json(resumo);}return json([]);});
 run("navigate('dashboard')");await tick();await tick();
 assert.equal(calls,1);
 assert.equal(t.get('#dashQueue').textContent,'4.026','Campaigns and individual');assert.match(t.get('#dashQueueSub').textContent,/25 consultando/);
 assert.equal(t.get('#dashAttention').textContent,'32');
 assert.equal(t.get('#dashToday').textContent,'305');
 assert.match(t.get('#dashCampaignList').textContent,/9.000 de 13.025/);
 assert.match(t.get('#dashAttentionList').textContent,/Fora da lista/);

 // Throttled: a sync right after does not ask again.
 run('render()');await tick();assert.equal(calls,1,'At most one call every 5 seconds');

 // An attention item that is not loaded in the browser still opens the filtered list.
 t.get('[data-dashboard-record="far"]').click();await tick();
 assert.equal(run('currentPage'),'home');assert.equal(t.get('#filter').value,'Erro');assert.equal(t.get('#search').value,'00000000191');

 // Individual counters: only individual consultations of the chosen service.
 run('render()');
 assert.equal(t.get('#total').textContent,'15');assert.equal(t.get('#waiting').textContent,'1');
 assert.equal(t.get('#done').textContent,'12');assert.equal(t.get('#errors').textContent,'2');

 // Another login: the previous account's numbers are not reused.
 run('authEpoch++;render()');
 assert.equal(run('painelResumoState().ready'),false);
 console.log('painel resumo frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});
