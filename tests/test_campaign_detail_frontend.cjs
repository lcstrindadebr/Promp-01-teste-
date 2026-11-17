const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/tjba.js','utf8'));run(fs.readFileSync('dist/exclusao.js','utf8'));
 run(fs.readFileSync('dist/workspace.js','utf8'));run(fs.readFileSync('dist/campaign-detail.js','utf8'));
 const doc=t.window.document;
 // Layout: pause in the header, retry inside "Precisam de atenção", delete in its own area at the end.
 assert.ok(doc.querySelector('.campaign-head-actions #pauseCampaign'));
 assert.ok(doc.querySelector('.campaign-group-card.attention #retryCampaign'));
 assert.ok(doc.querySelector('.campaign-danger #deleteCampaign'));
 assert.equal(doc.querySelector('#campaignDetail').lastElementChild.className,'campaign-danger');
 assert.ok(doc.querySelector('.campaign-progress-block #campaignEta'));

 run(`authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600};
 campaigns=[{id:'c1',nome:'Lista SP',servico:'digimais_saldo_parcela',created_at:'2026-11-03',paused:false}];activeCampaign='c1';
 records=[...Array(5)].map((_,i)=>({id:'p'+i,lote_id:'c1',status:'Processando',nome:'Cliente '+i,cpf:String(i),servico:'digimais_saldo_parcela',date:'2026-11-03'}))
  .concat([{id:'e1',lote_id:'c1',status:'Erro',nome:'Falhou',cpf:'9',servico:'digimais_saldo_parcela',date:'2026-11-03'},
   {id:'ok',lote_id:'c1',status:'Concluída',saldo:10,nome:'Ok',cpf:'8',servico:'digimais_saldo_parcela',date:'2026-11-03'}]);
 navigate('campaigns');renderCampaigns();`);
 assert.match(t.get('#cgAttention').textContent,/Erros\s*1/);
 assert.ok(doc.querySelector('.campaign-group-card.attention').classList.contains('has-items'));
 assert.equal(t.get('#retryCampaign').textContent,'Repetir a consulta com falha');
 assert.match(t.get('#cgProgress').textContent,/Solicitadas\s*7/);
 assert.match(t.get('#campaignLive').textContent,/Consultando 5 clientes agora: Cliente 0, Cliente 1, Cliente 2 e mais 2\./);
 assert.match(t.get('#campaignDangerText').textContent,/as 7 consultas/);
 // A problem counter filters the client list.
 doc.querySelector('#cgAttention [data-campaign-filter="attention"]').click();
 assert.equal(t.get('#campaignClientStatus').value,'attention');
 assert.match(t.get('#campaignRows').textContent,/Falhou/);assert.doesNotMatch(t.get('#campaignRows').textContent,/Cliente 0/);
 // Zero counters are not clickable.
 assert.equal(doc.querySelector('#cgAttention [data-campaign-filter="Consulta interrompida"]').disabled,true);

 // Deleting the campaign requires typing EXCLUIR.
 let deleted=false;t.handler(async(url,options)=>{if(options?.method==='DELETE'){deleted=true;return response([{id:'c1'}]);}return response([]);});
 t.get('#deleteCampaign').click();
 await new Promise(r=>setTimeout(r,0));
 const dialog=doc.querySelector('dialog.confirm-dialog'),yes=dialog.querySelector('[data-answer="yes"]'),input=dialog.querySelector('#confirmDialogTyped');
 assert.equal(yes.disabled,true);
 input.value='excluir';input.dispatchEvent(new t.window.Event('input'));assert.equal(yes.disabled,true);
 input.value='EXCLUIR';input.dispatchEvent(new t.window.Event('input'));assert.equal(yes.disabled,false);
 yes.click();
 for(let i=0;i<5&&!deleted;i++)await new Promise(r=>setTimeout(r,0));
 assert.equal(deleted,true,'Campaign deleted after typing EXCLUIR');
 console.log('campaign detail frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});
