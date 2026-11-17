const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
const tick=async(n=4)=>{for(let i=0;i<n;i++)await new Promise(setImmediate);};
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/tjba.js','utf8'));run(fs.readFileSync('dist/exclusao.js','utf8'));
 run(fs.readFileSync('dist/workspace.js','utf8'));run(fs.readFileSync('dist/campaign-detail.js','utf8'));
 run(fs.readFileSync('dist/campaign-server.js','utf8'));
 // The browser only has 2 of the campaign's clients; the database has 10.442.
 run(`authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600};
 campaigns=[{id:'c1',nome:'Lista SP',servico:'digimais_saldo_parcela',created_at:'2026-11-03',paused:false},
  {id:'c2',nome:'Antiga',servico:'digimais_saldo_parcela',created_at:'2026-10-01',paused:false}];
 records=[{id:'a',lote_id:'c1',status:'Concluída',nome:'Local A',cpf:'1',servico:'digimais_saldo_parcela',date:'2026-11-03'},
  {id:'b',lote_id:'c1',status:'Aguardando',nome:'Local B',cpf:'2',servico:'digimais_saldo_parcela',date:'2026-11-03'}];`);

 // Before the migration: functions missing (PGRST202) → local counting, no more calls.
 let calls=[];
 t.handler(async(url,options)=>{
  if(String(url).includes('painel_campanha')){calls.push([String(url),options.body]);return response({code:'PGRST202',message:'not found'},404);}
  return response([]);
 });
 run("navigate('campaigns');activeCampaign='c1';renderCampaigns()");await tick();
 assert.equal(run('serverCampaignState().off'),true);
 assert.match(t.get('#campaignRows').textContent,/Local A/);
 const before=calls.length;run('render()');await tick();assert.equal(calls.length,before,'No calls after PGRST202');

 // With the functions.
 run('serverCampaignsOff=false;serverCampaignEpoch=-1;serverCampaignDetail=null;serverCampaignList=null');
 const now=Date.now();
 const list=[{id:'c1',nome:'Lista SP',servico:'digimais_saldo_parcela',created_at:'2026-11-03',paused:false,
   contagens:{aguardando:4000,processando:42,nao_cliente:6000,concluida:380,erro:12,revisao:8}},
  {id:'c2',nome:'Antiga',servico:'digimais_saldo_parcela',created_at:'2026-10-01',paused:false,contagens:{concluida:10}}];
 const page=(n,filter)=>({id:'c1',origem:'consulta_jobs',filtrados:filter?20:10442,pagina:n,tamanho:50,
  resumo:{total:10442,clients:380,nonclients:6000,errors:12,sold:0,review:8,interrupted:0,waiting:4042,running:42,
   pace_count:30,pace_first:new Date(now-300000).toISOString(),pace_last:new Date(now-5000).toISOString()},
  consultando:[{nome:'Ana',cpf:'1'},{nome:'Bia',cpf:'2'},{nome:'Caio',cpf:'3'}],
  linhas:Array.from({length:filter?20:50},(_,i)=>({posicao:(n-1)*50+i+1,dados:{id:'s'+n+'-'+i,lote_id:'c1',nome:(filter?'Falha ':'Servidor ')+((n-1)*50+i+1),
   cpf:String(10000000000+i),telefone:'11999999999',status:filter?'erro':'nao_cliente',created_at:'2026-11-03',servico:'digimais_saldo_parcela'}}))});
 calls=[];
 t.handler(async(url,options)=>{
  const u=String(url);
  if(u.endsWith('/rpc/painel_campanhas')){calls.push(['list']);return response(list);}
  if(u.endsWith('/rpc/painel_campanha')){const b=JSON.parse(options.body);calls.push(['page',b]);return response(page(b.p_pagina,b.p_filtro));}
  return response([]);
 });
 run("navigate('dashboard');navigate('campaigns')");await tick();
 run('renderCampaigns()');await tick();
 const pageCall=calls.find(c=>c[0]==='page');
 assert.deepEqual(pageCall[1],{p_id:'c1',p_busca:'',p_filtro:'',p_pagina:1,p_tamanho:50});
 // List cards use the database totals.
 assert.match(t.get('#campaignList').textContent,/6\.400 de 10\.442 processados|6400 de 10442 processados/);
 assert.match(t.get('#campaignList').textContent,/20 para revisar/);
 // Detail: exact numbers, running names, ETA from the database pace, 50 rows with their positions.
 assert.match(t.get('#cgProgress').textContent,/Solicitadas\s*10\.442/);
 assert.match(t.get('#campaignLive').textContent,/Consultando 42 clientes agora: Ana, Bia, Caio e mais 39\./);
 assert.match(t.get('#campaignEta').textContent,/Conclusão estimada/);
 assert.equal((t.get('#campaignRows').innerHTML.match(/<tr>/g)||[]).length,50);
 assert.match(t.get('#campaignRows').innerHTML,/>Servidor 1</);assert.doesNotMatch(t.get('#campaignRows').textContent,/Local A/);
 assert.match(t.get('#campaignPageStatus').textContent,/Página 1 de 209 · 1–50 de 10442/);

 // Next page asks the database for page 2, keeping the old rows until it arrives.
 t.get('#campaignNextPage').onclick();
 assert.match(t.get('#campaignRows').innerHTML,/>Servidor 1</,'Old page stays while loading');
 await tick();
 assert.equal(calls.filter(c=>c[0]==='page').at(-1)[1].p_pagina,2);
 assert.match(t.get('#campaignRows').innerHTML,/>Servidor 51</);
 // Filter goes to the database and starts again at page 1.
 t.get('#campaignClientStatus').value='attention';t.get('#campaignClientStatus').onchange();await tick();
 const filtered=calls.filter(c=>c[0]==='page').at(-1)[1];
 assert.equal(filtered.p_filtro,'attention');assert.equal(filtered.p_pagina,1);
 assert.match(t.get('#campaignRows').innerHTML,/>Falha 1</);
 assert.match(t.get('#campaignPageStatus').textContent,/de 20$/);

 // Another account: nothing from the previous one is reused.
 run('authEpoch++');assert.equal(run('serverCampaignState().ready'),false);
 console.log('campaign server frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});
