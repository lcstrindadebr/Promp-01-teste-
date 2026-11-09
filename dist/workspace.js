// Operations workspace: plain-language choices, stable campaign order, pause/resume.
let changingCampaign=false;
const campaignPageSize=50;
let campaignPage=1,campaignPageKey='';
function orderedClients(rows){return [...rows].sort((a,b)=>Number(a.queue_order??Number.MAX_SAFE_INTEGER)-Number(b.queue_order??Number.MAX_SAFE_INTEGER)||new Date(a.created_at||a.date)-new Date(b.created_at||b.date)||String(a.id).localeCompare(String(b.id)));}
const originalCampaignRecords=campaignRecords;
campaignRecords=function(id){return orderedClients(originalCampaignRecords(id));};
function campaignPhase(c,rows){return c.paused?'paused':rows.some(r=>['Aguardando','Processando'].includes(r.status))?'active':'done';}
function campaignPhaseLabel(c,rows){const running=rows.filter(r=>r.status==='Processando').length;return c.paused?(running?'Pausando · consultas em andamento terminando':'Pausada'):campaignPhase(c,rows)==='done'?'Finalizada':running?'Em andamento':'Na fila';}
function campaignEta(campaign, rows, pending, running, now=Date.now()){
 if(!pending)return rows.length?'Campanha finalizada.':'';
 if(campaign.paused)return 'Previsão suspensa enquanto a campanha estiver pausada.';
 if(!running)return 'Previsão disponível quando o processamento estiver em andamento.';
 // Use completions from this campaign only, including outcomes that need review.
 const windowMs=10*60_000;
 let count=0,first=now,last=0;
 for(const row of rows){
  if(row.status==='Aguardando'||row.status==='Processando')continue;
  const finished=Date.parse(row.consultado_em);
  if(!Number.isFinite(finished)||finished<now-windowMs||finished>now)continue;
  count++;
  first=Math.min(first,finished);
  last=Math.max(last,finished);
 }
 if(count<3||last-first<30_000||now-last>2*60_000){
  return 'Calculando previsão com as próximas consultas.';
 }
 const interval=(now-first)/(count-1);
 const minutes=Math.max(1,Math.ceil(pending*interval/60_000));
 const finish=new Date(now+minutes*60_000);
 const hours=Math.floor(minutes/60),remaining=minutes%60;
 const duration=hours?hours+' h'+(remaining?' '+remaining+' min':''):minutes+' min';
 const time=finish.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});
 const date=finish.toDateString()===new Date(now).toDateString()?'':finish.toLocaleDateString('pt-BR')+' às ';
 return 'Conclusão estimada em '+duration+' ('+date+time+').';
}
function queryDescription(c){return serviceLabel(c.servico)+(c.servico==='tjba_margem'?' · '+convenioLabel(c.convenio):'');}
function resultProgress(r){const p=Math.max(0,Math.min(100,Number(r.progress)||0));return ['Aguardando','Processando'].includes(r.status)?`<div class="progress-line"><progress max="100" value="${p}" aria-label="Progresso da consulta"></progress><small>${p}%</small></div>`:'';}
function resultActions(r){return `${['Erro','Revisão','Consulta interrompida'].includes(r.status)?`<button data-retry="${escapeHTML(r.id)}">Tentar novamente</button>`:''}${r.servico==='tjba_margem'?`<button data-tjba-history="${escapeHTML(r.id)}">Histórico</button>`:typeof amigozAction==='function'?amigozAction(r):''}<button class="danger" data-delete-job="${escapeHTML(r.id)}">Excluir</button>`;}
setTableHead=function(service,id){const columns=['Cliente','Resultado',...(service==='tjba_margem'?['Empréstimo','Cartão','Vínculo']:['Saldo devedor','Parcela','Consultado em']),'Ações'];$('#'+id).innerHTML='<tr>'+columns.map(x=>`<th>${x}</th>`).join('')+'</tr>';};
rowsHTML=function(rows){return rows.map(r=>{const margin=r.servico==='tjba_margem';return `<tr><td><strong>${escapeHTML(r.nome)}</strong><span class="cell-sub">${escapeHTML(formatCpf(r.cpf))}</span><span class="cell-sub">${escapeHTML(margin?convenioLabel(r.convenio):'Digi+')}</span></td><td><span class="pill ${r.status==='Concluída'?'ok':['Erro','Revisão','Consulta interrompida'].includes(r.status)?'err':r.status==='Processando'?'run':''}">${escapeHTML(statusLabel(r.status))}</span>${resultProgress(r)}${resultMessage(r)?`<small class="cell-sub">${escapeHTML(resultMessage(r))}</small>`:''}</td>${margin?`<td class="amount">${moneyTjba(r.emprestimo_disponivel)}</td><td class="amount">${moneyTjba(r.cartao_disponivel)}</td><td><strong>${escapeHTML(r.matricula||'—')}</strong><span class="cell-sub">${escapeHTML(r.situacao_atual||'—')}</span><span class="cell-sub">${escapeHTML(r.tipo_servidor||'')}</span></td>`:`<td class="amount">${moneyTjba(r.saldo)}</td><td class="amount">${moneyTjba(r.valorParcela)}<span class="cell-sub">${r.parcelas==null?'':escapeHTML(r.parcelas)+' parcelas'}</span></td><td>${r.consultado_em?new Date(r.consultado_em).toLocaleString('pt-BR'):'—'}</td>`}<td><details class="row-actions" data-actions="${escapeHTML(r.id)}" ${document.querySelector('[data-actions="'+r.id+'"]')?.open?'open':''}><summary>Ações</summary><div>${resultActions(r)}</div></details></td></tr>`;}).join('')||'<tr><td colspan="7" class="empty">Nenhum resultado com esses filtros.</td></tr>';};
const campaignGroups=[
 ['digimais_saldo_parcela','Digi+ · Saldo e parcela'],
 ['tjba_margem','ConsigX · Margem']
];
const campaignPhases=[['active','Em andamento'],['paused','Pausadas'],['done','Concluídas']];
function renderCampaignList(){
 const query=$('#campaignSearch').value.trim().toLowerCase();
 const phase=$('#campaignStatus').value;
 const service=$('#campaignServiceFilter').value;
 const groups=new Map();
 const list=[...campaigns].sort((a,b)=>new Date(a.created_at)-new Date(b.created_at)||a.id.localeCompare(b.id));
 for(const campaign of list){
  const type=campaign.servico||'digimais_saldo_parcela';
  if((service&&type!==service)||(query&&!campaign.nome.toLowerCase().includes(query)))continue;
  const rows=campaignRecords(campaign.id);
  const state=campaignPhase(campaign,rows);
  if(phase&&state!==phase)continue;
  const key=type+':'+state;
  if(!groups.has(key))groups.set(key,[]);
  const totals=campaignStats(rows);
  const processed=totals.total-totals.waiting;
  const pct=totals.total?Math.round(100*processed/totals.total):0;
  groups.get(key).push(`<button class="campaign-item ${activeCampaign===campaign.id?'selected':''}" data-campaign="${escapeHTML(campaign.id)}">
   <div class="campaign-card-top"><span>${escapeHTML(campaignPhaseLabel(campaign,rows))}</span><span>${pct}%</span></div>
   <b>${escapeHTML(campaign.nome)}</b><span class="campaign-service">${escapeHTML(queryDescription(campaign))}</span>
   <progress max="100" value="${pct}" aria-label="Progresso da campanha"></progress>
   <small>${processed} de ${totals.total} processados · ${totals.errors+totals.review+totals.interrupted} para revisar</small></button>`);
 }
 const sections=campaignGroups.map(([type,title])=>{
  const states=campaignPhases.map(([state,label])=>{
   const cards=groups.get(type+':'+state);
   return cards?`<div class="campaign-group-phase"><h4>${label} <span class="campaign-group-count">${cards.length}</span></h4>${cards.join('')}</div>`:'';
  }).join('');
  return states?`<section class="campaign-group"><h3>${title}</h3>${states}</section>`:'';
 }).join('');
 $('#campaignList').innerHTML=sections||'<p class="empty">Nenhuma campanha encontrada. Crie uma nova campanha ou ajuste os filtros.</p>';
}
const legacyCampaigns=renderCampaigns;
renderCampaigns=function(){
 legacyCampaigns(false);
 $('#retryCampaign').textContent='Repetir consultas com falha';
 renderCampaignList();
 const c=campaigns.find(c=>c.id===activeCampaign);if(!c)return;
 const rows=campaignRecords(c.id),n=campaignStats(rows),pct=n.total?Math.round(100*(n.total-n.waiting)/n.total):0;
 $('#campaignState').textContent=queryDescription(c)+' · '+campaignPhaseLabel(c,rows);
 $('#campaignProgress').innerHTML=`<div><strong>${pct}% processado</strong><span>${n.total-n.waiting} de ${n.total} clientes</span></div><progress max="100" value="${pct}" aria-label="Progresso total da campanha"></progress>`;
 const running=rows.filter(r=>r.status==='Processando');$('#campaignLive').textContent=c.auto_paused?'Pausa automática após 10 erros ou pedidos de revisão consecutivos. '+(running.length?'As consultas em andamento vão terminar. ':'')+'Retome a campanha após conferir o log.':running.length?running.map(r=>'Consultando: '+r.nome+' · '+r.cpf).join(' | '):c.paused?'Campanha pausada. Retome para continuar pelos clientes pendentes.':n.waiting?'Aguardando sua vez na fila. Campanhas anteriores são processadas primeiro.':'Processamento finalizado. Confira os resultados ou repita apenas erros e revisões.';
 const eta=campaignEta(c,rows,n.waiting,running.length);
 if($('#campaignEta').textContent!==eta)$('#campaignEta').textContent=eta;
 $('#pauseCampaign').disabled=changingCampaign||(!n.waiting&&!c.paused);$('#pauseCampaign').textContent=c.paused?'Retomar campanha':'Pausar campanha';
 const search=$('#campaignClientSearch').value.trim().toLowerCase(),filter=$('#campaignClientStatus').value;
 const key=JSON.stringify([c.id,search,filter]);
 if(key!==campaignPageKey){campaignPage=1;campaignPageKey=key;}
 const filtered=[];
 rows.forEach((row,index)=>{
  const matchesSearch=matchesLeadSearch(row,search);
  const matchesStatus=!filter||(filter==='attention'?['Erro','Revisão','Consulta interrompida'].includes(row.status):row.status===filter);
  if(matchesSearch&&matchesStatus)filtered.push({row,rank:index+1});
 });
 const pages=Math.max(1,Math.ceil(filtered.length/campaignPageSize));
 campaignPage=Math.max(1,Math.min(campaignPage,pages));
 const start=(campaignPage-1)*campaignPageSize;
 const visible=filtered.slice(start,start+campaignPageSize);
 $('#campaignPrevPage').disabled=campaignPage===1;
 $('#campaignNextPage').disabled=campaignPage===pages;
 const label=filtered.length?`Página ${campaignPage} de ${pages} · ${start+1}–${start+visible.length} de ${filtered.length}`:'Nenhum cliente encontrado';
 if($('#campaignPageStatus').textContent!==label)$('#campaignPageStatus').textContent=label;
 setTableHead(c.servico,'campaignHead');
 let index=0;
 $('#campaignRows').innerHTML=rowsHTML(visible.map(item=>item.row))
  .replace(/<button data-retry="[^"]+">Tentar novamente<\/button>/g,'<span class="cell-sub">Use “Repetir consultas com falha” da campanha.</span>')
  .replace(/<tr><td>/g,()=>'<tr><td><span class="row-number">'+visible[index++].rank+'</span>');
};
$('#campaignPrevPage').onclick=()=>{campaignPage--;renderCampaigns();};
$('#campaignNextPage').onclick=()=>{campaignPage++;renderCampaigns();};
$('#pauseCampaign').onclick=async()=>{const c=campaigns.find(c=>c.id===activeCampaign);if(!c||changingCampaign)return;changingCampaign=true;renderCampaigns();try{await sbRequest('/rest/v1/rpc/set_campaign_paused',{method:'POST',body:JSON.stringify({p_campaign_id:c.id,p_service:c.servico||'digimais_saldo_parcela',p_paused:!c.paused})});toast(c.paused?'Campanha retomada.':'Pausa solicitada. Consultas já iniciadas vão terminar.');await loadCloud();}catch(e){toast(e.message)}finally{changingCampaign=false;renderCampaigns();}};
for(const id of ['#campaignSearch','#campaignClientSearch'])$(id).oninput=renderCampaigns;
for(const id of ['#campaignStatus','#campaignServiceFilter','#campaignClientStatus'])$(id).onchange=renderCampaigns;
const oldNavigate=navigate;
navigate=function(page){oldNavigate(page);syncQueryContext();};
function syncQueryContext(){const context=$('#serviceContext');context.classList.toggle('hide',currentPage==='settings'||(currentPage==='campaigns'&&!$('#newCampaignPanel').open));}
$('#newCampaignPanel').ontoggle=syncQueryContext;
const originalServiceChange=$('#serviceSelect').onchange;
$('#serviceSelect').onchange=()=>{originalServiceChange();syncQueryContext();};
$('#convenioSelect').onchange=()=>{if(selectedService()==='tjba_margem'){$('#singleServiceLabel').textContent=queryDescription({servico:'tjba_margem',convenio:selectedConvenio()});updateServiceCopy();}};
// The selector affects new requests. Existing campaigns retain their saved service.
updateServiceCopy=function(){const margin=selectedService()==='tjba_margem';$('#serviceAvailability').textContent=margin&&selectedConvenio()!=='tjba'?'Em homologação':'Pronto para consultar';$('#singleDescription').textContent=margin?'Informe o CPF. Nome e telefone são opcionais.':'Informe nome, CPF e telefone com DDD.';$('#resultsDescription').textContent='Resultados das consultas individuais do tipo selecionado.';$('#resultsFootnote').textContent='— significa informação não retornada. Erros e revisões podem ser tratados em Ações.';};
updateServiceCopy();syncQueryContext();render();

// Reuse the existing inputs and handlers inside a three-step campaign flow.
const creationPanel=$('#newCampaignPanel'),creationContent=creationPanel.querySelector(':scope > div');
const contextAnchor=document.createElement('div');$('#serviceContext').before(contextAnchor);
const originalCreationNodes=[...creationContent.childNodes];
creationContent.innerHTML='<div class="wizard-steps" aria-label="Etapas da campanha"><button type="button" data-step="1">1 <span>Consulta</span></button><button type="button" data-step="2">2 <span>Planilha</span></button><button type="button" data-step="3">3 <span>Conferir</span></button></div><div id="campaignStep1" class="wizard-stage"><h3>O que você quer consultar nesta lista?</h3><p>A escolha fica salva na campanha.</p></div><div id="campaignStep2" class="wizard-stage" hidden><h3>Nomeie a campanha e envie os clientes</h3></div><div id="campaignStep3" class="wizard-stage" hidden><h3>Confira antes de iniciar</h3><div id="campaignConfirmation"></div></div><div class="wizard-navigation"><button id="wizardBack" type="button">Voltar</button><button id="wizardNext" type="button" class="primary">Continuar →</button></div>';
for(const node of originalCreationNodes){const lastStep=['import','importStatus','preview'].includes(node.id);$('#campaignStep'+(lastStep?'3':'2')).appendChild(node);}
let creationStep=1;
function drawCreationStep(){
 for(let i=1;i<=3;i++)$('#campaignStep'+i).hidden=i!==creationStep;
 creationContent.querySelectorAll('[data-step]').forEach(b=>{b.classList.toggle('current',Number(b.dataset.step)===creationStep);b.disabled=Number(b.dataset.step)>creationStep;b.setAttribute('aria-current',Number(b.dataset.step)===creationStep?'step':'false');});
 $('#wizardBack').hidden=creationStep===1;$('#wizardNext').hidden=creationStep===3;
 if(creationStep===3)$('#campaignConfirmation').innerHTML=`<div class="confirmation-title"><strong>${escapeHTML($('#campaignName').value)}</strong><span>${escapeHTML(queryDescription({servico:selectedService(),convenio:selectedConvenio()}))}</span></div><div class="confirmation-count">${pending.length}<small>clientes válidos na fila</small></div><p>Os clientes começam na ordem da planilha. Você pode pausar e retomar pelo painel da campanha.</p><p class="muted">${pending.slice(0,4).map(r=>escapeHTML(r.nome)+' · '+escapeHTML(formatCpf(r.cpf))).join('<br>')}</p>`;
}
function moveQueryContext(){if(currentPage==='campaigns')$('#campaignStep1').appendChild($('#serviceContext'));else if(currentPage==='home'&&$('#individualServiceContext'))$('#individualServiceContext').appendChild($('#serviceContext'));else contextAnchor.after($('#serviceContext'));syncQueryContext();}
const workspaceNavigate=navigate;navigate=function(page){workspaceNavigate(page);moveQueryContext();};
creationPanel.ontoggle=()=>{if(!creationPanel.open){creationStep=1;drawCreationStep();}moveQueryContext();};
$('#wizardNext').onclick=()=>{if(creationStep===2){if(!$('#campaignName').value.trim()){toast('Dê um nome para a campanha.');$('#campaignName').focus();return;}const quotaError=typeof campaignImportError==='function'?campaignImportError(pending.length):'';if(readingImport||!pending.length||importError||quotaError){toast(quotaError||importError||'Envie uma planilha válida antes de continuar.');return;}}creationStep=Math.min(3,creationStep+1);drawCreationStep();};
$('#wizardBack').onclick=()=>{creationStep=Math.max(1,creationStep-1);drawCreationStep();};
creationContent.querySelectorAll('[data-step]').forEach(b=>b.onclick=()=>{creationStep=Number(b.dataset.step);drawCreationStep();});
drawCreationStep();moveQueryContext();

const workspaceShowLogin=showLogin;
showLogin=function(message=''){creationStep=1;$('#campaignConfirmation').innerHTML='';for(const id of ['#campaignSearch','#campaignStatus','#campaignServiceFilter','#campaignClientSearch','#campaignClientStatus'])$(id).value='';drawCreationStep();workspaceShowLogin(message);};
const workspaceServiceChange=$('#serviceSelect').onchange;
function simplifyMarginForm(){const margin=selectedService()==='tjba_margem';$('#nameLabel').hidden=margin;$('#nome').hidden=margin;$('#phoneLabel').parentElement.hidden=margin;$('#importHint').textContent=margin?'Preencha apenas a coluna cpf. Substitua a linha de exemplo e preserve os zeros à esquerda. As margens serão preenchidas pelo robô.':'Preencha nome, cpf e telefone. Substitua a linha de exemplo; mantenha CPF e telefone como texto. O robô preenche saldo e parcela.';}
$('#serviceSelect').onchange=()=>{workspaceServiceChange();simplifyMarginForm();};
simplifyMarginForm();
