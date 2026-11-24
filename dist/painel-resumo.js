// Contadores prontos do banco (Fase 2c, etapa 1): o Início e o resumo da consulta individual leem
// public.painel_resumo(), que devolve poucas linhas já contadas, em vez de percorrer todas as consultas.
// Enquanto a função não existir no banco (painel atualizado antes da migração), tudo segue contado no
// navegador, como antes.
let painelResumo=null,painelResumoEpoch=-1,painelResumoAt=0,painelResumoBusy=false,painelResumoOff=false;
const painelResumoAttention=['erro','revisao','interrompida'],painelResumoQueue=['aguardando','processando'];
let painelResumoItems=new Map();

function painelResumoReady(){return !!painelResumo&&painelResumoEpoch===authEpoch;}
function painelResumoVisible(){return document.visibilityState!=='hidden'&&(currentPage==='dashboard'||currentPage==='home');}
async function refreshPainelResumo(force){
 if(!authenticated||painelResumoOff||painelResumoBusy)return;
 if(!force&&painelResumoReady()&&Date.now()-painelResumoAt<5000)return;
 painelResumoBusy=true;const epoch=authEpoch;
 try{
  const data=await sbRequest('/rest/v1/rpc/painel_resumo',{method:'POST',body:'{}'});
  if(epoch!==authEpoch)return;
  painelResumo=data;painelResumoEpoch=epoch;painelResumoAt=Date.now();
  renderDashboard();renderIndividualCounters();
 }catch(e){
  // 404: a função ainda não está no banco. Outros erros: tenta de novo na próxima atualização.
  if(e?.status===404)painelResumoOff=true;
 }finally{painelResumoBusy=false;}
}
function painelResumoSum(filter){
 return (painelResumo?.contagens||[]).filter(filter).reduce((total,c)=>total+Number(c.n||0),0);
}

// Início
const painelResumoLocalSummary=dashboardSummary;
dashboardSummary=function(){
 if(!painelResumoReady())return painelResumoLocalSummary();
 const s=painelResumo;
 const attention=(s.atencao||[]).map(r=>({id:r.id,lote_id:r.lote_id,nome:r.nome,cpf:r.cpf,servico:r.servico,
  status:statusNames[r.status]||r.status,date:r.data}));
 painelResumoItems=new Map(attention.map(r=>[r.id,r]));
 return {
  queue:painelResumoSum(c=>painelResumoQueue.includes(c.status)),
  running:painelResumoSum(c=>c.status==='processando'),
  attentionCount:painelResumoSum(c=>painelResumoAttention.includes(c.status)),
  attention,
  doneToday:Object.values(s.concluidas_hoje||{}).reduce((total,n)=>total+Number(n||0),0),
  active:(s.campanhas_ativas||[]).map(c=>({c:{id:c.id,nome:c.nome,servico:c.servico,paused:!!c.paused,created_at:c.created_at},
   n:{total:Number(c.total||0),pending:Number(c.pendentes||0)}}))
 };
};
// Um item da lista de atenção pode não estar entre as consultas carregadas no navegador.
const painelResumoOpenRecord=openRecordFromDashboard;
openRecordFromDashboard=function(id){
 if(records.some(r=>r.id===id))return painelResumoOpenRecord(id);
 const r=painelResumoItems.get(id);if(!r)return;
 if(campaigns.some(c=>c.id===r.lote_id))return openCampaignFromDashboard(r.lote_id);
 chooseService(r.servico);navigate('home');
 $('#filter').value=r.status;$('#search').value=r.cpf||'';$('#filter').onchange?.();
 $('#results').scrollIntoView({block:'start'});
};

// Consulta individual: Total, Na fila, Concluídas e Precisam de atenção do serviço escolhido.
function renderIndividualCounters(){
 if(!painelResumoReady())return;
 let service;try{service=selectedService();}catch{return;}
 const mine=c=>c.tipo==='individual'&&c.servico===service;
 $('#total').textContent=painelResumoSum(mine);
 $('#waiting').textContent=painelResumoSum(c=>mine(c)&&painelResumoQueue.includes(c.status));
 $('#done').textContent=painelResumoSum(c=>mine(c)&&c.status==='concluida');
 $('#errors').textContent=painelResumoSum(c=>mine(c)&&painelResumoAttention.includes(c.status));
}

// O painel chama render() a cada sincronização: os números vêm junto, no máximo a cada 5 segundos.
const painelResumoBaseRender=render;
render=function(){painelResumoBaseRender();renderIndividualCounters();if(painelResumoVisible())refreshPainelResumo();};
const painelResumoBaseNavigate=navigate;
navigate=function(...args){painelResumoBaseNavigate(...args);if(painelResumoVisible())refreshPainelResumo(true);};
document.addEventListener('visibilitychange',()=>{if(painelResumoVisible())refreshPainelResumo();});
setInterval(()=>{if(painelResumoVisible())refreshPainelResumo();},15000);
window.painelResumoState=()=>({ready:painelResumoReady(),off:painelResumoOff,data:painelResumo});

// Início: clientes cadastrados e oportunidades do CRM (public.painel_crm_totais).
// Contar a base inteira custa mais que os contadores da fila, então busca ao abrir o Início e no máximo a cada minuto.
let crmTotais=null,crmTotaisEpoch=-1,crmTotaisAt=0,crmTotaisBusy=false,crmTotaisOff=false;
function crmTotaisVisible(){return document.visibilityState!=='hidden'&&currentPage==='dashboard';}
async function refreshCrmTotais(force){
 if(!authenticated||crmTotaisOff||crmTotaisBusy)return;
 if(!force&&crmTotaisEpoch===authEpoch&&Date.now()-crmTotaisAt<60000)return;
 crmTotaisBusy=true;const epoch=authEpoch;
 try{
  const data=await sbRequest('/rest/v1/rpc/painel_crm_totais',{method:'POST',body:'{}'});
  if(epoch!==authEpoch)return;
  crmTotais=data;crmTotaisEpoch=epoch;crmTotaisAt=Date.now();renderCrmTotais();
 }catch(e){if(e?.status===404&&epoch===authEpoch){crmTotaisOff=true;renderCrmTotais();}}
 finally{crmTotaisBusy=false;}
}
function renderCrmTotais(){
 const ready=!!crmTotais&&crmTotaisEpoch===authEpoch,o=ready?crmTotais.oportunidades||{}:{},f=n=>dashboardNumber.format(Number(n||0));
 $('[data-dashboard-tile="clients"]').hidden=$('[data-dashboard-tile="opportunities"]').hidden=crmTotaisOff;
 $('#dashClients').textContent=ready?f(crmTotais.clientes):'—';
 $('#dashOpportunities').textContent=ready?f(o.abertas):'—';
 $('#dashOpportunitiesSub').textContent=ready?`${f(o.ganhas)} ganha${Number(o.ganhas)===1?'':'s'} · ${f(o.total)} no total`:'No funil do CRM';
}
{
 const baseRender=render;
 render=function(){baseRender();if(crmTotaisVisible())refreshCrmTotais();};
 const baseNavigate=navigate;
 navigate=function(...args){baseNavigate(...args);if(crmTotaisVisible())refreshCrmTotais(true);};
 document.addEventListener('visibilitychange',()=>{if(crmTotaisVisible())refreshCrmTotais();});
 setInterval(()=>{if(crmTotaisVisible())refreshCrmTotais();},60000);
}
