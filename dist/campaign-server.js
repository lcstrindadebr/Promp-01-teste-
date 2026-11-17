// Campanhas paginadas no servidor (Fase 2c, etapa 2).
// A lista de campanhas vem com os totais prontos (public.painel_campanhas) e o detalhe traz só a página de
// clientes aberta, já buscada, filtrada e ordenada no banco (public.painel_campanha), com os números da
// campanha, o ritmo para a previsão e quem está sendo consultado agora.
// Enquanto as funções não existirem no banco, workspace.js segue usando as consultas carregadas.
let serverCampaignList=null,serverCampaignListAt=0,serverCampaignListBusy=false;
let serverCampaignDetail=null,serverCampaignDetailAt=0,serverCampaignDetailBusy='';
let serverCampaignsOff=false,serverCampaignEpoch=-1;

function serverCampaignsReady(){return !serverCampaignsOff&&serverCampaignEpoch===authEpoch;}
// Função ausente no banco (painel atualizado antes da migração): PostgREST responde PGRST202.
function serverCampaignMissing(error){return error?.status===404&&error?.code==='PGRST202';}
// campaignPhase/campaignPhaseLabel só perguntam se há consulta na fila ou em andamento.
function serverPhaseRows(waiting,running){
 const rows=[];if(running)rows.push({status:'Processando'});if(waiting>running)rows.push({status:'Aguardando'});return rows;
}
function serverSummaryFromList(entry){
 const k=entry.contagens||{},g=s=>Number(k[s]||0);
 const total=Object.values(k).reduce((sum,n)=>sum+Number(n||0),0),running=g('processando'),waiting=g('aguardando')+running;
 return {n:{total,clients:g('concluida'),nonclients:g('nao_cliente')+g('nao_localizado')+g('nao_encontrado'),errors:g('erro'),
   sold:g('ja_vendeu'),review:g('revisao'),interrupted:g('interrompida'),waiting},
  runningCount:running,running:[],phaseRows:serverPhaseRows(waiting,running),pace:{count:0,first:Date.now(),last:0,total},rows:null};
}
function serverSummaryFromDetail(data){
 const r=data.resumo||{},n=key=>Number(r[key]||0),now=Date.now();
 return {n:{total:n('total'),clients:n('clients'),nonclients:n('nonclients'),errors:n('errors'),sold:n('sold'),review:n('review'),
   interrupted:n('interrupted'),waiting:n('waiting')},
  runningCount:n('running'),running:data.consultando||[],phaseRows:serverPhaseRows(n('waiting'),n('running')),
  pace:{count:n('pace_count'),first:Date.parse(r.pace_first)||now,last:Date.parse(r.pace_last)||0,total:n('total')},rows:null};
}
function serverCampaignSummary(c){
 if(!serverCampaignsReady())return null;
 // O detalhe da campanha aberta tem os números exatos; as demais usam a lista.
 if(serverCampaignDetail?.id===c.id)return serverSummaryFromDetail(serverCampaignDetail.data);
 const entry=serverCampaignList?.find(x=>x.id===c.id);
 return entry?serverSummaryFromList(entry):null;
}
function serverCampaignClientPage(c,search,filter,page){
 if(serverCampaignsOff)return null;
 const key=JSON.stringify([c.id,search,filter,page]);
 const current=serverCampaignDetail&&serverCampaignEpoch===authEpoch?serverCampaignDetail:null;
 if(current?.key!==key)loadServerCampaignDetail(c,search,filter,page,key);
 if(current?.key===key)return {items:current.items,total:current.total};
 // Ainda sem resposta do banco nesta sessão: as consultas carregadas servem enquanto isso.
 if(!serverCampaignsReady())return null;
 // Outra página ou filtro da mesma campanha: mantém a tabela anterior até chegar a nova.
 if(current?.id===c.id)return {items:current.items,total:current.total};
 return {items:[],total:0,loading:true};
}
async function loadServerCampaignDetail(c,search,filter,page,key){
 if(serverCampaignDetailBusy===key||!authenticated)return;
 serverCampaignDetailBusy=key;const epoch=authEpoch;
 try{
  const data=await sbRequest('/rest/v1/rpc/painel_campanha',{method:'POST',body:JSON.stringify({
   p_id:c.id,p_busca:search,p_filtro:filter,p_pagina:page,p_tamanho:campaignPageSize})});
  if(epoch!==authEpoch)return;
  serverCampaignEpoch=epoch;serverCampaignDetailAt=Date.now();
  serverCampaignDetail={key,id:c.id,data,total:Number(data.filtrados||0),
   items:(data.linhas||[]).map(x=>({row:normalizeCloudRow(x.dados),rank:Number(x.posicao)}))};
  if(currentPage==='campaigns')renderCampaigns();
 }catch(error){
  if(serverCampaignMissing(error))serverCampaignsOff=true;
 }finally{if(serverCampaignDetailBusy===key)serverCampaignDetailBusy='';}
}
async function refreshServerCampaigns(force){
 if(!authenticated||serverCampaignsOff)return;
 const now=Date.now();
 if(!serverCampaignListBusy&&(force||!serverCampaignsReady()||now-serverCampaignListAt>=5000)){
  serverCampaignListBusy=true;const epoch=authEpoch;
  try{
   const list=await sbRequest('/rest/v1/rpc/painel_campanhas',{method:'POST',body:'{}'});
   if(epoch!==authEpoch)return;
   serverCampaignList=list;serverCampaignEpoch=epoch;serverCampaignListAt=Date.now();
   if(currentPage==='campaigns')renderCampaigns();
  }catch(error){if(serverCampaignMissing(error))serverCampaignsOff=true;}
  finally{serverCampaignListBusy=false;}
 }
 // A página aberta também se atualiza, no mesmo ritmo.
 const open=serverCampaignDetail;
 if(open&&serverCampaignsReady()&&open.id===activeCampaign&&(force||Date.now()-serverCampaignDetailAt>=5000)){
  const [id,search,filter,page]=JSON.parse(open.key),c=campaigns.find(x=>x.id===id);
  if(c)loadServerCampaignDetail(c,search,filter,page,open.key);
 }
}
function serverCampaignsVisible(){return document.visibilityState!=='hidden'&&currentPage==='campaigns';}
const serverCampaignBaseRender=render;
render=function(){serverCampaignBaseRender();if(serverCampaignsVisible())refreshServerCampaigns();};
const serverCampaignBaseNavigate=navigate;
navigate=function(...args){serverCampaignBaseNavigate(...args);if(serverCampaignsVisible())refreshServerCampaigns(true);};
document.addEventListener('visibilitychange',()=>{if(serverCampaignsVisible())refreshServerCampaigns();});
setInterval(()=>{if(serverCampaignsVisible())refreshServerCampaigns();},15000);
// Pausar, retomar, repetir e excluir mudam os números na hora: busca de novo logo depois.
for(const id of ['#pauseCampaign','#retryCampaign','#deleteCampaign','#refreshCampaigns']){
 $(id)?.addEventListener('click',()=>setTimeout(()=>refreshServerCampaigns(true),1500));
}
window.serverCampaignState=()=>({ready:serverCampaignsReady(),off:serverCampaignsOff,list:serverCampaignList,detail:serverCampaignDetail});
