const {setup,response}=require('./test_frontend.cjs');
const assert=require('assert'),vm=require('vm');
(async()=>{
 const t=setup();
 let jobs=[{id:'individual',nome:'Individual somente',cpf:'00123456789',status:'concluida',created_at:'2026-10-31',saldo_liquidacao:100,valor_parcela:10},
 ...['concluida','nao_cliente','erro','revisao','processando'].map((status,i)=>({id:'job'+i,lote_id:'campaign',nome:'Campanha '+i,cpf:'0000000000'+i,status,created_at:'2026-10-31',saldo_liquidacao:status==='concluida'?100:null,valor_parcela:null}))];
 let lots=[{id:'campaign',nome:'Campanha teste',tipo:'campanha',created_at:'2026-10-31'}];let creates=[];
 t.handler(async(u,o)=>{
  if(u.includes('/token?'))return response({access_token:'test',refresh_token:'test',expires_in:3600,user:{id:'owner',email:'test@example.com'}});
  if(u.includes('/rpc/create_consulta_campaign')){const data=JSON.parse(o.body);creates.push(data);return response('campaign')}
  if(u.includes('/rpc/retry_consulta_campaign')){let n=0;jobs.forEach(j=>{if(j.lote_id==='campaign'&&['erro','revisao'].includes(j.status)){j.status='aguardando';n++}});return response(n)}
  if(u.includes('/consulta_jobs?'))return response(jobs);
  if(u.includes('/consulta_lotes?'))return response(lots);
  return response([]);
 });
 await t.get('#login').onsubmit({preventDefault(){}});await new Promise(setImmediate);
 assert(t.get('#rows').innerHTML.includes('Individual somente'));assert(!t.get('#rows').innerHTML.includes('Campanha 0'));
 assert.equal(t.get('#total').textContent,1);assert(t.get('#campaignList').innerHTML.includes('5 consultas'));
 vm.runInContext("activeCampaign='campaign';renderCampaigns()",t.ctx);
 const n=JSON.parse(vm.runInContext('JSON.stringify(campaignStats(campaignRecords(activeCampaign)))',t.ctx));
 assert.deepEqual(n,{total:5,clients:1,nonclients:1,errors:1,review:1,waiting:1});
 assert.equal(t.get('#retryCampaign').disabled,false);
 vm.runInContext("download=(name,content)=>{window.lastDownload={name,content}}",t.ctx);
 t.get('#exportCampaign').onclick();assert(!t.ctx.window.lastDownload.content.includes('Individual somente'));assert(t.ctx.window.lastDownload.content.includes('Campanha 0'));
 t.get('#export').onclick();assert(t.ctx.window.lastDownload.content.includes('Individual somente'));assert(!t.ctx.window.lastDownload.content.includes('Campanha 0'));
 await t.get('#retryCampaign').onclick();assert.equal(jobs.length,6);assert.equal(jobs[1].status,'concluida');assert.equal(jobs[2].status,'nao_cliente');assert.equal(jobs[5].status,'processando');assert.equal(t.get('#retryCampaign').disabled,true);
 const file={size:100,text:async()=> 'nome;cpf;telefone\nTESTE;00123456789;11999999999\nDUPLICADO;00123456789;11999999999'};
 await t.get('#file').onchange({target:{files:[file]}});assert.equal(vm.runInContext('pending.length',t.ctx),1);assert(t.get('#preview').textContent.includes('1 inválidos'));
 await t.get('#import').onclick();assert.equal(creates.length,0,'Campaign name must be required');
 t.get('#campaignName').value='Campanha de um cliente';await t.get('#import').onclick();
 assert.equal(creates.length,1);assert.equal(creates[0].p_nome,'Campanha de um cliente');assert.equal(creates[0].p_items.length,1);assert.equal(creates[0].p_items[0].cpf,'00123456789');
 // Pagination must not silently truncate reports at the API's first 1000 rows.
 t.handler(async u=>response(u.includes('offset=1000')?[{id:'last'}]:Array.from({length:1000},(_,i)=>({id:'page'+i}))));
 assert.equal((await vm.runInContext("fetchAll('/rest/v1/consulta_jobs?select=*')",t.ctx)).length,1001);
 await t.get('#logout').onclick();assert.equal(vm.runInContext('campaigns.length',t.ctx),0);assert(!t.get('#campaignList').innerHTML.includes('Campanha teste'));
 console.log('PASS: separate tabs/data/exports, exact campaign totals, named one-row campaigns, retry scope, duplicate CPF, pagination and logout');
})().catch(e=>{console.error(e);process.exitCode=1});
