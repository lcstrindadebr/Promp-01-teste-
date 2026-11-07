const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();vm.runInContext(fs.readFileSync('dist/tjba.js','utf8'),t.ctx);
 const source=fs.readFileSync('dist/workspace.js','utf8').split('// Reuse the existing inputs')[0];vm.runInContext(source,t.ctx);
 const order=vm.runInContext("orderedClients([{id:'a',queue_order:12},{id:'z',queue_order:2},{id:'b',queue_order:8}]).map(r=>r.id).join(',')",t.ctx);assert.equal(order,'z,b,a');
 assert.equal(vm.runInContext("campaignPhaseLabel({paused:true},[{status:'Processando'}])",t.ctx),'Pausando · consultas em andamento terminando');
 assert.equal(vm.runInContext("campaignPhaseLabel({paused:true},[{status:'Aguardando'}])",t.ctx),'Pausada');
 vm.runInContext("campaigns=[{id:'d',nome:'DIGI',servico:'digimais_saldo_parcela',created_at:'2026-11-03'},{id:'t',nome:'MARGEM',servico:'tjba_margem',created_at:'2026-11-04',paused:true}];records=[];renderCampaigns()",t.ctx);
 assert(t.get('#campaignList').innerHTML.includes('DIGI'));assert(t.get('#campaignList').innerHTML.includes('MARGEM'));
 t.get('#campaignStatus').value='paused';vm.runInContext('renderCampaigns()',t.ctx);assert(!t.get('#campaignList').innerHTML.includes('DIGI'));assert(t.get('#campaignList').innerHTML.includes('MARGEM'));
 vm.runInContext("authenticated=true;session={access_token:'test',expires_at:Date.now()/1000+3600,user:{id:'owner'}};activeCampaign='d'",t.ctx);let payload;
 t.handler(async(u,o)=>{if(u.includes('set_campaign_paused')){payload=JSON.parse(o.body);return response(null)}return response([])});
 await t.get('#pauseCampaign').onclick();assert.deepEqual(payload,{p_campaign_id:'d',p_service:'digimais_saldo_parcela',p_paused:true});
 vm.runInContext("campaigns=[{id:'d',nome:'DIGI',servico:'digimais_saldo_parcela',created_at:'2026-11-03'}];activeCampaign='d';records=Array.from({length:121},(_,i)=>({id:'row'+i,lote_id:'d',queue_order:i,nome:'Registro '+i,cpf:String(i),status:i===120?'Erro':'Concluída'}));renderCampaigns()",t.ctx);
 assert.equal((t.get('#campaignRows').innerHTML.match(/<tr>/g)||[]).length,50);
 t.get('#campaignNextPage').onclick();t.get('#campaignNextPage').onclick();
 assert.equal((t.get('#campaignRows').innerHTML.match(/<tr>/g)||[]).length,21);
 assert(t.get('#campaignRows').innerHTML.includes('Registro 120'));
 assert(t.get('#campaignNextPage').disabled);
 t.get('#campaignClientStatus').value='attention';t.get('#campaignClientStatus').onchange();
 assert.equal((t.get('#campaignRows').innerHTML.match(/<tr>/g)||[]).length,1);
 assert(t.get('#campaignPrevPage').disabled);
 assert.equal(fs.readFileSync('dist/modelo-tjba.csv','utf8').replace(/^\uFEFF/,'').trim().split(/\r?\n/)[0],'cpf');
 assert.equal(fs.readFileSync('dist/modelo-importacao.csv','utf8').replace(/^\uFEFF/,'').trim().split(/\r?\n/)[0],'nome;cpf;telefone');
 const eta=vm.runInContext(`(()=>{
  const now=Date.parse('2026-11-07T20:00:00Z');
  const rows=[120,90,60,30].map(seconds=>({status:'Concluída',consultado_em:new Date(now-seconds*1000).toISOString()}));
  return [
   campaignEta({},rows,6,1,now),
   campaignEta({paused:true},rows,6,1,now),
   campaignEta({},rows,6,0,now),
   campaignEta({},rows.slice(0,2),6,1,now),
   campaignEta({},rows,6,1,now+180000),
   campaignEta({},rows,0,0,now)
  ];
 })()`,t.ctx);
 assert.match(eta[0],/Conclusão estimada em 4 min/);
 assert.match(eta[1],/pausada/);
 assert.match(eta[2],/processamento estiver em andamento/);
 assert.match(eta[3],/Calculando/);
 assert.match(eta[4],/Calculando/);
 assert.match(eta[5],/finalizada/);
 console.log('PASS: stable row order, all-service campaign list, pause states, status filters and owner-scoped pause request');
})().catch(e=>{console.error(e);process.exit(1)});
