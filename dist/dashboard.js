// Início: o que está acontecendo agora e o que precisa de atenção, com atalhos para agir.
// Lê os mesmos dados já carregados pelo painel (records, campaigns, currentAccess); não faz consultas próprias.
const dashboardAttention=['Erro','Revisão','Consulta interrompida'];
const dashboardQueue=['Aguardando','Processando'];
let dashboardTimer=0,dashboardLastRender=0;

const dashboardSection=document.createElement('section');
dashboardSection.id='dashboard';dashboardSection.className='hide';dashboardSection.setAttribute('aria-labelledby','dashboardTitle');
dashboardSection.innerHTML=`<header class="dashboard-header"><div><h1 id="dashboardTitle">Início</h1><p id="dashboardDate"></p></div>
<div class="dashboard-actions"><button type="button" class="primary" data-dashboard-go="individual">Nova consulta individual</button><button type="button" data-dashboard-go="campaign">Nova campanha</button><button type="button" data-dashboard-go="clients">Importar clientes</button></div></header>
<div id="dashboardQuota" class="dashboard-quota" hidden></div>
<div class="dashboard-tiles" role="list">
 <button type="button" class="dashboard-tile" role="listitem" data-dashboard-tile="queue"><span>Na fila agora</span><strong id="dashQueue">0</strong><small id="dashQueueSub">Nenhuma consulta aguardando</small></button>
 <button type="button" class="dashboard-tile attention" role="listitem" data-dashboard-tile="attention"><span>Precisam de atenção</span><strong id="dashAttention">0</strong><small>Erro, revisão ou interrompida</small></button>
 <button type="button" class="dashboard-tile" role="listitem" data-dashboard-tile="today"><span>Concluídas hoje</span><strong id="dashToday">0</strong><small id="dashTodaySub">Com resultado disponível</small></button>
 <button type="button" class="dashboard-tile" role="listitem" data-dashboard-tile="campaigns"><span>Campanhas em andamento</span><strong id="dashCampaigns">0</strong><small id="dashCampaignsSub">Nenhuma consultando agora</small></button>
</div>
<div class="dashboard-panels">
 <section class="card dashboard-panel" aria-labelledby="dashCampaignsTitle"><div class="heading"><h2 id="dashCampaignsTitle">Campanhas em andamento</h2><button type="button" class="link-button" data-dashboard-go="campaigns">Ver todas</button></div><div id="dashCampaignList"></div></section>
 <section class="card dashboard-panel" id="dashAttentionPanel" aria-labelledby="dashAttentionTitle"><div class="heading"><h2 id="dashAttentionTitle">Precisam de atenção</h2></div><div id="dashAttentionList"></div></section>
</div>`;
$('#home').before(dashboardSection);

const dashboardNav=document.createElement('button');
dashboardNav.type='button';dashboardNav.dataset.page='dashboard';dashboardNav.title='Início';dashboardNav.setAttribute('aria-label','Início');
dashboardNav.innerHTML='<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M3 11l9-7 9 7 M5 10v10h5v-6h4v6h5V10"/></svg><span>Início</span>';
dashboardNav.onclick=()=>navigate('dashboard');
document.querySelector('aside nav').prepend(dashboardNav);

const dashboardNumber=new Intl.NumberFormat('pt-BR');
function dashboardDay(value){const d=new Date(value);return isNaN(d)?'':d.toLocaleDateString('sv-SE',{timeZone:'America/Sao_Paulo'});}
// Um único passe pelos registros: contadores, campanhas e lista de atenção.
function dashboardSummary(){
 const today=dashboardDay(Date.now()),byCampaign=new Map(),campaignIds=new Set(campaigns.map(c=>c.id)),attention=[];
 let queue=0,running=0,attentionCount=0,doneToday=0;
 for(const r of records){
  const inQueue=dashboardQueue.includes(r.status);
  if(inQueue){queue++;if(r.status==='Processando')running++;}
  if(dashboardAttention.includes(r.status)){attentionCount++;attention.push(r);}
  if(r.status==='Concluída'&&dashboardDay(r.date)===today)doneToday++;
  if(campaignIds.has(r.lote_id)){
   let n=byCampaign.get(r.lote_id);if(!n){n={total:0,pending:0};byCampaign.set(r.lote_id,n);}
   n.total++;if(inQueue)n.pending++;
  }
 }
 attention.sort((a,b)=>new Date(b.date)-new Date(a.date));
 const active=campaigns.map(c=>({c,n:byCampaign.get(c.id)||{total:0,pending:0}})).filter(x=>x.n.pending>0)
  .sort((a,b)=>Number(a.c.paused)-Number(b.c.paused)||new Date(b.c.created_at)-new Date(a.c.created_at));
 return {queue,running,attentionCount,attention:attention.slice(0,6),doneToday,active};
}
function renderDashboard(){
 if(currentPage!=='dashboard')return;
 dashboardLastRender=Date.now();
 const s=dashboardSummary();
 const day=new Date().toLocaleDateString('pt-BR',{weekday:'long',day:'numeric',month:'long',timeZone:'America/Sao_Paulo'});
 $('#dashboardDate').textContent=day.charAt(0).toUpperCase()+day.slice(1);
 $('#dashQueue').textContent=dashboardNumber.format(s.queue);
 $('#dashQueueSub').textContent=s.queue?`${dashboardNumber.format(s.running)} consultando agora`:'Nenhuma consulta aguardando';
 $('#dashAttention').textContent=dashboardNumber.format(s.attentionCount);
 $('[data-dashboard-tile="attention"]').classList.toggle('has-items',s.attentionCount>0);
 $('#dashToday').textContent=dashboardNumber.format(s.doneToday);
 $('#dashCampaigns').textContent=dashboardNumber.format(s.active.length);
 $('#dashCampaignsSub').textContent=s.active.length?`${dashboardNumber.format(s.active.filter(x=>x.c.paused).length)} pausada(s)`:'Nenhuma consultando agora';
 const a=currentAccess,quota=$('#dashboardQuota');
 quota.hidden=!a||a.role==='admin';
 if(!quota.hidden){
  if(a.trial_expired)quota.innerHTML='<strong>Período de teste encerrado.</strong> O histórico continua disponível; novas consultas dependem de renovação.';
  else if(a.daily_limit==null)quota.innerHTML='<strong>Consultas ilimitadas hoje.</strong> Campanhas e consultas individuais usam a mesma cota da empresa.';
  else{
   const used=Math.max(0,a.daily_limit-(a.remaining??0)),pct=a.daily_limit?Math.min(100,Math.round(used/a.daily_limit*100)):100;
   quota.innerHTML=`<div><strong>${dashboardNumber.format(a.remaining??0)} de ${dashboardNumber.format(a.daily_limit)} consultas disponíveis hoje</strong><small>A cota é da empresa e renova à meia-noite, no horário de Brasília.</small></div><progress max="100" value="${pct}" aria-label="Cota usada hoje: ${pct}%"></progress>`;
  }
 }
 $('#dashCampaignList').innerHTML=s.active.slice(0,5).map(({c,n})=>{
  const done=n.total-n.pending,pct=n.total?Math.round(done/n.total*100):0;
  return `<button type="button" class="dashboard-row" data-dashboard-campaign="${escapeHTML(c.id)}"><span class="dashboard-row-main"><b>${escapeHTML(c.nome)}</b><small>${escapeHTML(serviceLabel(c.servico))}${c.paused?' · Pausada':''}</small></span><span class="dashboard-row-progress"><progress max="100" value="${pct}" aria-label="${pct}% concluído"></progress><small>${dashboardNumber.format(done)} de ${dashboardNumber.format(n.total)}</small></span></button>`;
 }).join('')||'<p class="muted">Nenhuma campanha consultando agora. Use "Nova campanha" para enviar uma lista.</p>';
 $('#dashAttentionList').innerHTML=s.attention.map(r=>`<button type="button" class="dashboard-row" data-dashboard-record="${escapeHTML(r.id)}"><span class="dashboard-row-main"><b>${escapeHTML(r.nome||r.cpf)}</b><small>${escapeHTML(serviceLabel(r.servico))} · ${escapeHTML(new Date(r.date).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'}))}</small></span><span class="pill err">${escapeHTML(statusLabel(r.status))}</span></button>`).join('')
  ||'<p class="muted">Nada pendente. Consultas com erro ou em revisão aparecem aqui.</p>';
}
// O painel chama render() a cada sincronização; o Início acompanha sem recalcular a cada evento.
function scheduleDashboard(){
 if(currentPage!=='dashboard'||dashboardTimer)return;
 const wait=Math.max(0,1500-(Date.now()-dashboardLastRender));
 dashboardTimer=setTimeout(()=>{dashboardTimer=0;renderDashboard();},wait);
}
function chooseService(id){
 const select=$('#serviceSelect'),value=id||'digimais_saldo_parcela';
 if(select.value!==value&&[...select.options].some(o=>o.value===value&&!o.disabled)){select.value=value;select.onchange?.();}
}
function openCampaignFromDashboard(id){
 const c=campaigns.find(c=>c.id===id);if(!c)return;
 chooseService(c.servico);activeCampaign=id;navigate('campaigns');render();
 $('#campaignDetail')?.scrollIntoView({block:'start'});
}
function openRecordFromDashboard(id){
 const r=records.find(r=>r.id===id);if(!r)return;
 if(campaigns.some(c=>c.id===r.lote_id))return openCampaignFromDashboard(r.lote_id);
 chooseService(r.servico);navigate('home');
 $('#filter').value=r.status;$('#search').value=r.cpf||'';$('#filter').onchange?.();
 $('#results').scrollIntoView({block:'start'});
}
dashboardSection.addEventListener('click',e=>{
 const target=e.target.closest('[data-dashboard-go],[data-dashboard-tile],[data-dashboard-campaign],[data-dashboard-record]');if(!target)return;
 const go=target.dataset.dashboardGo,tile=target.dataset.dashboardTile;
 if(target.dataset.dashboardCampaign)return openCampaignFromDashboard(target.dataset.dashboardCampaign);
 if(target.dataset.dashboardRecord)return openRecordFromDashboard(target.dataset.dashboardRecord);
 if(go==='individual'){navigate('home');$('#nome').focus();return;}
 if(go==='campaign'){navigate('campaigns');const panel=$('#newCampaignPanel');if(panel){panel.open=true;panel.scrollIntoView({block:'start'});}return;}
 if(go==='campaigns'||tile==='campaigns'){navigate('campaigns');return;}
 if(go==='clients'){navigate('clients');return;}
 if(tile==='attention'){$('#dashAttentionPanel').scrollIntoView({block:'start'});return;}
 if(tile==='queue'||tile==='today'){
  navigate('home');$('#search').value='';$('#filter').value=tile==='queue'?'grupo:fila':'Concluída';$('#filter').onchange?.();
  $('#results').scrollIntoView({block:'start'});
 }
});

const dashboardBaseNavigate=navigate;
navigate=function(page){
 dashboardBaseNavigate(page);
 const on=page==='dashboard';
 dashboardSection.classList.toggle('hide',!on);
 dashboardNav.classList.toggle('active',on);
 // A cota já aparece no Início; o aviso do topo some aqui para não repetir.
 document.body.classList.toggle('on-dashboard',on);
 if(on){$('#pageBreadcrumb').textContent='Início';renderDashboard();}
};
const dashboardBaseRender=render;
render=function(){dashboardBaseRender();scheduleDashboard();};
// O painel abre no Início.
navigate('dashboard');

// Consulta individual: os contadores filtram a lista abaixo.
document.querySelector('.consultation-summary')?.addEventListener('click',e=>{
 const button=e.target.closest('[data-stat-filter]');if(!button)return;
 $('#filter').value=button.dataset.statFilter;$('#search').value='';$('#filter').onchange?.();
 $('#results').scrollIntoView({block:'start'});
});
function syncStatFilters(){
 const value=$('#filter').value;
 document.querySelectorAll('[data-stat-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.statFilter===value)));
}
const dashboardFilterChange=$('#filter').onchange;
$('#filter').onchange=()=>{dashboardFilterChange?.();syncStatFilters();};
syncStatFilters();
