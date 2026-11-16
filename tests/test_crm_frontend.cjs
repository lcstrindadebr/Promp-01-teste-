const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {setup}=require('./test_frontend.cjs');
// Real page in jsdom; data comes from `handler` through sbRequest, downloads land in `blobs`.
let handler=async()=>[],calls=[],blobs=[];
const t=setup(),ctx=t.ctx,run=code=>vm.runInContext(code,ctx),get=s=>t.get(s);
t.window.Blob=Blob; // Node's Blob has text(), used to read the generated files.
t.window.URL.createObjectURL=b=>{blobs.push(b);return 'blob:test';};t.window.URL.revokeObjectURL=()=>{};
t.window.HTMLAnchorElement.prototype.click=function(){};
t.window.__crmRequest=async(path,options)=>{calls.push({path,options});return handler(path,options);};
run("authenticated=true;authEpoch=1;currentPage='clients';session={access_token:'x',expires_at:Date.now()/1000+3600};sbRequest=(path,options)=>window.__crmRequest(path,options)");
run(fs.readFileSync('dist/crm.js','utf8'));run(fs.readFileSync('dist/crm-import.js','utf8'));
(async()=>{
 handler=async(path,options)=>path.includes('crm_filter_clients')?Array.from({length:26},(_,i)=>({cpf:String(i+1).padStart(11,'0'),nome:'Cliente teste'})):[];
 await vm.runInContext('loadCrmClients(0)',ctx);assert.equal(get('#crmRows').children.length,25);assert.equal(get('#crmNext').disabled,false);
 await vm.runInContext('loadCrmClients(1)',ctx);assert.equal(JSON.parse(calls.at(-1).options.body).p_after,'00000000025');
 // Every exported page is fetched, not just the visible 25 or first 500.
 let exported=0;handler=async(path,options)=>{if(!path.includes('crm_filter_clients'))return [];const after=JSON.parse(options.body).p_after;const start=Number(after||0);return Array.from({length:Math.min(500,1201-start)},(_,i)=>({cpf:String(start+i+1).padStart(11,'0'),nome:'=formula'}))};
 await get('#crmExport').onclick();const csv=await blobs[0].text();assert.equal(csv.trim().split('\r\n').length,1202);assert(csv.includes('000.000.012-01'));assert(csv.includes("'=formula"));
 // A failed page must not produce a silently truncated file.
 blobs=[];let count=0;handler=async()=>{if(++count===2)throw Error('network');return [{cpf:'00000000001'}]};await get('#crmExport').onclick();assert.equal(blobs.length,0);assert.match(get('#crmStatus').textContent,/Nenhum arquivo parcial/);
 // Failed moves leave stage unchanged; no success UI before server confirmation.
 run("crmBoardCards=new Map([['id',{id:'id',etapa:'novo',etapa_id:'stage-novo'}]]);crmBoardStages=new Map([['ganho',{id:'stage-ganho',codigo:'ganho'}]])");
 handler=async()=>{throw Error('network')};assert.equal(await vm.runInContext("crmMoveOpportunity('id','ganho',crmPipelineRequest)",ctx),false);
 assert.match(get('#crmPipelineStatus').textContent,/network/);assert.equal(run("crmBoardCards.get('id').etapa"),'novo','Stage unchanged after a failed move');
 // Stages come from the database (crm_kanban); the default account has seven.
 const stages=['novo','exportada','contato','proposta','negociacao','ganho','perdido'].map((codigo,i)=>({id:'stage-'+codigo,codigo,nome:codigo,posicao:i,total:0,cartoes:[],
  tipo:['ganho','perdido'].includes(codigo)?codigo:'aberta',destino_exportacao:codigo==='exportada'}));
 handler=async path=>path.includes('crm_kanban')?stages:[];await vm.runInContext('loadCrmPipeline(0)',ctx);assert.equal(get('#crmPipelineRows').children.length,7);
 assert.deepEqual(Array.from(get('#crmStageFilter').options).slice(1,3).map(option=>option.value),['novo','exportada']);
 const exportFile=()=>vm.runInContext("crmDownloadOpportunities({stage:'novo',uf:'SP',convenio:'amigoz_33',products:['saque']},$('#crmExportOpportunities'),$('#crmExportOpportunitiesStatus'))",ctx);
 let downloaded=false,moved=false;
 get('#crmPipelineRows').closest=()=>({});
 ctx.XLSX={utils:{aoa_to_sheet:rows=>rows,book_new:()=>({}),book_append_sheet:()=>{}},writeFile:()=>{downloaded=true;}};
 handler=async(path,options)=>{
   if(path.includes('crm_registrar_exportacao')){
     assert(downloaded);
     assert.deepEqual(JSON.parse(options.body).p_itens,[{id:'1',etapa:'novo'}]);moved=true;return 1;
   }
   if(!path.includes('crm_listar_exportacao'))return []; // client details, margins and agreements for the sheet
   const params=JSON.parse(options.body);
   assert.deepEqual(params.p_tipos,['saque']);assert.equal(params.p_uf,'SP');assert.equal(params.p_convenio,'amigoz_33');
   return params.p_after?[]:[{id:'1',cpf:'00000000001',etapa:'novo',produto:'saque'}];
 };
 await exportFile();assert(moved);
 assert.match(get('#crmExportOpportunitiesStatus').textContent,/1 movidas/);
 moved=false;ctx.XLSX.writeFile=()=>{throw Error('falha ao gerar');};
 await exportFile();assert.equal(moved,false);
 blobs=[];
 // Filter options are loaded from the account's data on the real page.
 get('#crmUF').add(new t.window.Option('SP','SP'));get('#crmAgreementFilter').add(new t.window.Option('Amigoz 33','amigoz_33'));
 get('#crmUF').value='SP';get('#crmAgreementFilter').value='amigoz_33';
 handler=async(path,options)=>{
  if(path.includes('crm_catalogo_importacao'))return [{uf:'SP',codigo:'amigoz_33',servicos:['amigoz_margem','amigoz_saque','digimais_saldo']}];
  if(path.includes('crm_margens_vinculo')) return [];
  if(path.includes('crm_vinculos')) return new URLSearchParams(path.split('?')[1]).get('offset')==='0'?[{cpf:'00000000001',matricula:'0007'}]:[];
  const params=JSON.parse(options.body);
  return params.p_after?[]:[{cpf:'00000000001',nome:'Teste',resumo_consultas:{
   margem_importada_amigoz_33:{data:'2026-11-10',dados:{margem_emprestimo:0}},
   amigoz_saque_amigoz_33:{dados:[{elegivel:'Sim',valor_saque_disponivel:250}]}
  }}];
 };
 vm.runInContext('crmImportCatalog=undefined',ctx);
 await get('#crmExportTemplate').onclick();
 const template=await blobs[0].text();
 // Header cells are quoted like the values (CSV injection safety).
 assert.match(template.split('\r\n')[0].replaceAll('"',''),/margem_emprestimo;margem_cartao;margem_beneficio;margem_consignado;instituicao;saque_amigoz_elegivel;saque_amigoz_valor;data_dados;uf;convenio/);
 assert(template.includes('"0007"') && template.includes('"0";"";"";"";"";"Sim";"250";"2026-11-10";"SP";"amigoz_33"'));
 const html=fs.readFileSync('dist/index.html','utf8');const nav=html.match(/<nav>(.*?)<\/nav>/s)[1];assert(!nav.includes('data-page="campaigns"'));assert(html.includes('data-consultation="campaigns"'));
 console.log('PASS: CRM cursor pagination, 1,201-row export, failed export, failed stage move, seven Kanban columns, unified navigation');
})().catch(e=>{console.error(e);process.exitCode=1});
