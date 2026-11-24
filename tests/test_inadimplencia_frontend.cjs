const fs=require('fs'),vm=require('vm'),assert=require('assert');
const {setup,response}=require('./test_frontend.cjs');
const tick=async(n=6)=>{for(let i=0;i<n;i++)await new Promise(setImmediate);};
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run(fs.readFileSync('dist/tjba.js','utf8'));run(fs.readFileSync('dist/exclusao.js','utf8'));
 run(fs.readFileSync('dist/workspace.js','utf8'));run(fs.readFileSync('dist/campaign-detail.js','utf8'));
 run(fs.readFileSync('dist/campaign-server.js','utf8'));
 // Database codes become the new labels; the agency shows under the status.
 const adm=run("normalizeCloudRow({id:'a',lote_id:'solo',nome:'Adm',cpf:'00000000191',status:'inadimplencia_administrativa',message:'Assessoria: MZ ASSESSORIA E COBRANÇA · (11)4293-0260',servico:'digimais_saldo_parcela',created_at:'2026-11-24T00:00:00Z'})");
 assert.equal(adm.status,'Inadimplência administrativa');
 run(`records=[normalizeCloudRow({id:'a',lote_id:'solo',nome:'Adm',cpf:'00000000191',status:'inadimplencia_administrativa',message:'Assessoria: MZ ASSESSORIA E COBRANÇA · (11)4293-0260',servico:'digimais_saldo_parcela',created_at:'2026-11-24T00:00:00Z'}),
  normalizeCloudRow({id:'j',lote_id:'solo',nome:'Jur',cpf:'00000000272',status:'inadimplencia_juridica',message:'Assessoria: PASQUALI JURIDICO · 0800 602 9934',servico:'digimais_saldo_parcela',created_at:'2026-11-24T00:00:00Z'}),
  normalizeCloudRow({id:'o',lote_id:'solo',nome:'Ok',cpf:'00000000353',status:'concluida',servico:'digimais_saldo_parcela',created_at:'2026-11-24T00:00:00Z'})];campaigns=[];navigate('home');render();`);
 assert.match(t.get('#rows').textContent,/Inadimplência administrativa/);
 assert.match(t.get('#rows').textContent,/MZ ASSESSORIA E COBRANÇA · \(11\)4293-0260/);
 assert.match(t.get('#rows').textContent,/Inadimplência jurídica/);
 // Filter: both kinds together, or one of them; the robot log counts them as finished.
 t.get('#filter').value='grupo:inadimplencia';t.get('#filter').onchange();
 assert.equal((t.get('#rows').innerHTML.match(/<tr>/g)||[]).length,2);
 t.get('#filter').value='Inadimplência jurídica';t.get('#filter').onchange();
 assert.equal((t.get('#rows').innerHTML.match(/<tr>/g)||[]).length,1);assert.match(t.get('#rows').textContent,/PASQUALI/);
 assert.equal(run("consultationWasPerformed({status:'Inadimplência administrativa'})"),true);

 // Campaign: two counters from the database, "Já vendeu" only for old records; filter goes to the database.
 run(`authenticated=true;session={access_token:'t',expires_at:Date.now()/1000+3600};
 campaigns=[{id:'c1',nome:'Lista',servico:'digimais_saldo_parcela',created_at:'2026-11-03',paused:false}];`);
 const calls=[];
 t.handler(async(url,options)=>{
  const u=String(url);
  if(u.endsWith('/rpc/painel_campanhas'))return response([{id:'c1',nome:'Lista',servico:'digimais_saldo_parcela',created_at:'2026-11-03',paused:false,contagens:{inadimplencia_administrativa:30,inadimplencia_juridica:2,concluida:5}}]);
  if(u.endsWith('/rpc/painel_campanha')){const b=JSON.parse(options.body);calls.push(b);
   return response({id:'c1',filtrados:0,resumo:{total:37,clients:5,inad_adm:30,inad_jur:2,sold:0,waiting:0,running:0},consultando:[],linhas:[]});}
  return response([]);
 });
 run("navigate('campaigns');activeCampaign='c1';renderCampaigns()");await tick();run('renderCampaigns()');
 assert.match(t.get('#cgResults').textContent,/Inadimplência administrativa\s*30/);
 assert.match(t.get('#cgResults').textContent,/Inadimplência jurídica\s*2/);
 assert.doesNotMatch(t.get('#cgResults').textContent,/Já vendeu/);
 t.get('#cgResults').querySelector('[data-campaign-filter="Inadimplência jurídica"]').click();await tick();
 assert.equal(calls.at(-1).p_filtro,'Inadimplência jurídica');
 // Report export has the new columns.
 run("download=(name,content)=>{window.__csv=content;}");t.get('#exportCampaignReport').onclick();
 assert.match(run('window.__csv'),/"inadimplencia_administrativa";"inadimplencia_juridica"/);
 assert.match(run('window.__csv'),/"0";"30";"2"/);
 console.log('inadimplencia frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});
