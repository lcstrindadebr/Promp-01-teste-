// Detalhe da campanha (Fase 3): progresso e previsão no topo, contadores agrupados pelo que
// pedem do operador e a exclusão separada das ações do dia a dia.
// Reaproveita os botões e cálculos existentes; aqui só se reorganiza a apresentação.
(function(){
 const detail=$('#campaignDetail');if(!detail)return;
 const heading=detail.querySelector('.heading'),report=$('#campaignReport');
 detail.classList.add('campaign-detail-v3');

 // Ações do dia a dia ficam no cabeçalho; a exclusão vai para o fim, em área própria.
 const actions=document.createElement('div');actions.className='campaign-head-actions';
 actions.append($('#pauseCampaign'));heading.append(actions);
 const progressBlock=document.createElement('div');progressBlock.className='campaign-progress-block';
 $('#campaignProgress').before(progressBlock);progressBlock.append($('#campaignProgress'),$('#campaignEta'),$('#campaignLive'));

 const groups=document.createElement('div');groups.className='campaign-groups';groups.id='campaignGroups';
 groups.innerHTML=`<section class="campaign-group-card" aria-labelledby="cgResultsTitle"><h3 id="cgResultsTitle">Resultados</h3><div class="campaign-group-stats" id="cgResults"></div></section>
<section class="campaign-group-card attention" aria-labelledby="cgAttentionTitle"><h3 id="cgAttentionTitle">Precisam de atenção</h3><div class="campaign-group-stats" id="cgAttention"></div><div class="campaign-group-action"></div></section>
<section class="campaign-group-card" aria-labelledby="cgProgressTitle"><h3 id="cgProgressTitle">Andamento</h3><div class="campaign-group-stats" id="cgProgress"></div></section>`;
 report.before(groups);report.hidden=true;
 groups.querySelector('.campaign-group-action').append($('#retryCampaign'));

 const danger=document.createElement('section');danger.className='campaign-danger';danger.setAttribute('aria-labelledby','campaignDangerTitle');
 danger.innerHTML='<div><h3 id="campaignDangerTitle">Excluir campanha</h3><p id="campaignDangerText">Apaga a campanha e todas as consultas e resultados dela. Não há como recuperar.</p></div>';
 danger.append($('#deleteCampaign'));detail.append(danger);

 const fmt=new Intl.NumberFormat('pt-BR');
 const stat=(label,value,filter)=>filter==null
  ?`<div class="campaign-group-stat"><span>${label}</span><strong>${fmt.format(value)}</strong></div>`
  :`<button type="button" class="campaign-group-stat" data-campaign-filter="${filter}" ${value?'':'disabled'}><span>${label}</span><strong>${fmt.format(value)}</strong></button>`;

 groups.addEventListener('click',e=>{
  const b=e.target.closest('[data-campaign-filter]');if(!b)return;
  $('#campaignClientStatus').value=b.dataset.campaignFilter;$('#campaignClientSearch').value='';
  $('#campaignClientStatus').dispatchEvent(new Event('change'));
  detail.querySelector('.tablecard')?.scrollIntoView({block:'start'});
 });

 const baseRender=renderCampaigns;
 renderCampaigns=function(...args){
  baseRender(...args);
  const c=campaigns.find(c=>c.id===activeCampaign);if(!c)return;
  const summary=campaignSummary(c),n=summary.n,tjba=c.servico==='tjba_margem',problems=n.errors+n.review+n.interrupted;
  $('#cgResults').innerHTML=stat(tjba?'CPFs localizados':'Clientes identificados',n.clients,'Concluída')
   +stat(tjba?'Não encontrados':'Não são clientes',n.nonclients,null)+(tjba?'':stat('Já vendeu',n.sold,null));
  $('#cgAttention').innerHTML=stat('Erros',n.errors,'attention')+stat('Em revisão',n.review,'attention')+(tjba?'':stat('Interrompidas',n.interrupted,'Consulta interrompida'));
  groups.querySelector('.attention').classList.toggle('has-items',problems>0);
  // Pelos números do banco: as consultas da campanha não ficam todas no navegador.
  $('#retryCampaign').disabled=retryingCampaign||!problems;
  $('#retryCampaign').textContent=problems===1?'Repetir a consulta com falha':problems?`Repetir as ${fmt.format(problems)} consultas com falha`:'Nada para repetir';
  $('#cgProgress').innerHTML=stat('Solicitadas',n.total,null)+stat('Na fila ou consultando',n.waiting,'Aguardando');
  $('#campaignDangerText').textContent=`Apaga a campanha e as ${fmt.format(n.total)} consultas e resultados dela. Não há como recuperar.`;
  // Com muitas consultas ao mesmo tempo (a API Digi+ roda até 100), mostra quantas e os primeiros nomes.
  const running=summary.running,runningCount=summary.runningCount;
  if(runningCount>3&&!c.auto_paused&&!c.paused){
   const names=running.slice(0,3).map(r=>r.nome||r.cpf).join(', ');
   $('#campaignLive').textContent=`Consultando ${fmt.format(runningCount)} clientes agora: ${names} e mais ${fmt.format(runningCount-3)}.`;
  }
 };
 // Os filtros da lista guardavam a versão anterior; passam a usar esta.
 for(const id of ['#campaignStatus','#campaignServiceFilter','#campaignClientStatus'])if($(id))$(id).onchange=()=>renderCampaigns();
})();
