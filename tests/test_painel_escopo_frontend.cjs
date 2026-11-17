const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
const tick=async(n=6)=>{for(let i=0;i<n;i++)await new Promise(setImmediate);};
(async()=>{
 // 1. Sync asks only for campaigns and individual consultations; falls back to everything without the scope.
 {
  const t=setup();const run=code=>vm.runInContext(code,t.ctx);
  run("authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600,user:{id:'u'}};");
  const bodies=[];let scoped=true;
  t.handler(async(url,options)=>{
   if(String(url).endsWith('/rpc/painel_consultas_sync')){
    const body=JSON.parse(options.body);bodies.push(body);
    if(body.p_escopo&&!scoped)return response({code:'PGRST202',message:'Could not find the function'},404);
    return response({snapshot:'1:1:',next:null,rows:[]});
   }
   return response([]);
  });
  await run('syncCloudPages(authEpoch)');
  assert.equal(bodies[0].p_escopo,'avulsas');
  assert.equal(run('cloudSyncedScope'),'avulsas');
  // Older database: the scoped call is refused once, then everything is synced without it.
  run('cloudSnapshot=null;cloudScopeOff=false;cloudSyncedScope=null');scoped=false;bodies.length=0;
  await run('syncCloudPages(authEpoch)');
  assert.equal(bodies.length,2);assert.equal(bodies[0].p_escopo,'avulsas');assert.equal('p_escopo' in bodies[1],false);
  assert.equal(run('cloudScope()'),'tudo');assert.equal(run('cloudSyncedScope'),'tudo');
  // Missing campaign functions also mean syncing everything, starting over.
  run("cloudScopeOff=false;var serverCampaignsOff=true;cloudSyncedScope='avulsas';cloudSnapshot='1:1:'");bodies.length=0;scoped=true;
  await run('syncCloudPages(authEpoch)');
  assert.equal(bodies[0].p_since,null,'Scope change restarts from scratch');assert.equal('p_escopo' in bodies[0],false);
 }

 // 2. Campaign rows, export and logs come from the database.
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/tjba.js','utf8'));run(fs.readFileSync('dist/exclusao.js','utf8'));
 run(fs.readFileSync('dist/workspace.js','utf8'));run(fs.readFileSync('dist/campaign-detail.js','utf8'));
 run(fs.readFileSync('dist/campaign-server.js','utf8'));
 run("function renderDigiApiLogs(){};");run(fs.readFileSync('dist/log-server.js','utf8'));
 run(`authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600};currentAccess={role:'admin',active:true};
 campaigns=[{id:'c1',nome:'Lista SP',servico:'digimais_saldo_parcela',created_at:'2026-11-03',paused:false}];records=[];`);
 const total=450,pages=[],logCalls=[];
 const job=i=>({id:'j'+i,lote_id:'c1',nome:'Cliente '+i,cpf:String(10000000000+i),telefone:'11999999999',status:'concluida',
  saldo_liquidacao:100+i,created_at:'2026-11-03',servico:'digimais_saldo_parcela',robot_slot:1+i%2});
 t.handler(async(url,options)=>{
  const u=String(url),b=options?.body?JSON.parse(options.body):{};
  if(u.endsWith('/rpc/painel_campanhas'))return response([{id:'c1',nome:'Lista SP',servico:'digimais_saldo_parcela',created_at:'2026-11-03',paused:false,contagens:{concluida:total}}]);
  if(u.endsWith('/rpc/painel_campanha')){
   pages.push(b);const start=(b.p_pagina-1)*b.p_tamanho,count=Math.max(0,Math.min(b.p_tamanho,total-start));
   return response({id:'c1',filtrados:total,resumo:{total,clients:total,waiting:0,running:0},consultando:[],
    linhas:Array.from({length:count},(_,i)=>({posicao:start+i+1,dados:job(start+i+1)}))});
  }
  if(u.endsWith('/rpc/painel_log_consultas')){logCalls.push(b);
   return response(b.p_modo==='robo'?[{...job(1),status:'erro',message:'Falha do banco',consultado_em:'2026-11-03T10:00:00Z'}]
    :[{...job(2),execution_mode:'api',api_slot:3,api_handoff:{api_slot:3,date:'2026-11-03T11:00:00Z',message:'Encaminhada'}}]);}
  return response([]);
 });
 run("navigate('campaigns');activeCampaign='c1';renderCampaigns()");await tick();
 // A row of the open page is found for actions even though it is not among the loaded records.
 assert.equal(run("findRecord('j3')?.nome"),'Cliente 3');
 assert.equal(run("findRecord('j999')"),undefined);

 // Export: the whole campaign, in parts of 200, in order.
 let csv='';run("download=(name,content)=>{window.__csv=content;}");
 pages.length=0;await t.get('#exportCampaign').onclick();csv=run('window.__csv');
 assert.deepEqual(pages.map(p=>[p.p_pagina,p.p_tamanho]),[[1,200],[2,200],[3,200]]);
 assert.equal(csv.split('\r\n').length,total+1,'Header plus every client');
 assert.match(csv,/Cliente 450/);

 // Report export uses the database numbers.
 run("window.__csv=''");t.get('#exportCampaignReport').onclick();
 assert.match(run('window.__csv'),/"Lista SP";"450"/);

 // Robot log from the database, filtered by robot.
 run("navigate('settings');$('#consultationLogPanel').open=true;$('#consultationLogRobot').value='2';renderLogs()");await tick();
 assert.deepEqual(logCalls.at(-1),{p_modo:'robo',p_slot:'2',p_limite:500});
 run('renderLogs()');assert.match(t.get('#consultationLogs').textContent,/Falha do banco/);
 // API log source.
 run("serverApiLogRows('')");await tick();
 assert.equal(logCalls.at(-1).p_modo,'api');assert.equal(run("serverApiLogRows('')[0].api_handoff.api_slot"),3);
 // Unchanged rows keep the same object between refreshes (details cached per row are not fetched again).
 run("window.__firstLogRow=serverLogState().robo.rows[0];serverLogs.robo.at=0;consultationLogRecords()");await tick();
 assert.equal(run("serverLogState().robo.rows[0]===window.__firstLogRow"),true);
 console.log('painel escopo frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});
