let amigozCampaignRows=[],amigozCampaignEpoch=-1;
const campaignFeedback=document.createElement('p');
campaignFeedback.className='muted';
campaignFeedback.setAttribute('role','status');
$('#campaignList').before(campaignFeedback);

function amigozCampaignCards(groups,{query,phase,service}){
 if(amigozCampaignEpoch!==authEpoch||(service&&service!=='amigoz'))return;
 for(const row of amigozCampaignRows){
  const state=row.pendentes?'active':'done';
  if((phase&&phase!==state)||(query&&!row.nome.toLowerCase().includes(query)))continue;
  const key='amigoz:'+state;
  if(!groups.has(key))groups.set(key,[]);
  const processed=row.leads-row.pendentes;
  const pct=row.leads?Math.round(100*processed/row.leads):0;
  const label=row.pendentes?'Em andamento':row.atencao?'Finalizada com falhas':'Concluída';
  groups.get(key).push(`<article class="campaign-item">
   <div class="campaign-card-top"><span>${label}</span><span>${pct}%</span></div>
   <b>${escapeHTML(row.nome)}</b><span class="campaign-service">Amigoz</span>
   <progress max="100" value="${pct}" aria-label="Progresso da campanha"></progress>
   <small>${processed} de ${row.leads} leads processados · ${row.concluidas} concluídos · ${row.atencao} para revisar</small>
  </article>`);
 }
}

async function refreshAmigozCampaignList(){
 if(!authenticated||currentPage!=='campaigns')return;
 const epoch=authEpoch;
 campaignFeedback.textContent='Carregando campanhas Amigoz…';
 try{
  const rows=await crmRpc('crm_listar_campanhas_amigoz',{});
  if(epoch!==authEpoch||currentPage!=='campaigns')return;
  amigozCampaignRows=rows;amigozCampaignEpoch=epoch;
  campaignFeedback.textContent='';
  renderCampaignList();
 }catch(error){
  if(epoch===authEpoch&&currentPage==='campaigns')campaignFeedback.textContent='Amigoz: '+error.message;
 }
}

$('#campaignServiceFilter').add(new Option('Amigoz','amigoz'));
const newCampaign=document.createElement('button');
newCampaign.type='button';newCampaign.className='primary';newCampaign.textContent='Nova campanha';
const choices=document.createElement('div');
choices.className='actions';choices.hidden=true;
for(const [label,service] of [['Digi+','digimais_saldo_parcela'],['ConsigX','tjba_margem'],['Amigoz','amigoz']]){
 const choice=document.createElement('button');
 choice.type='button';choice.textContent=label;
 choice.onclick=()=>{
  choices.hidden=true;newCampaign.setAttribute('aria-expanded','false');
  if(service==='amigoz'){crmOpenClientImport(true);return;}
  const select=$('#serviceSelect');
  select.value=service;select.onchange?.();
  const panel=$('#newCampaignPanel');
  panel.open=true;panel.scrollIntoView({block:'nearest'});
 };
 choices.append(choice);
}
newCampaign.setAttribute('aria-expanded','false');
newCampaign.onclick=()=>{
 for(const [index,choice] of [...choices.children].entries()){
  const service=['digimais_saldo_parcela','tjba_margem','amigoz'][index];
  choice.hidden=service==='amigoz'
   ?!(currentAccess?.active&&(currentAccess.role==='admin'||(currentAccess.allow_amigoz&&!currentAccess.trial_expired)))
   :![...$('#serviceSelect').options].some(option=>option.value===service&&!option.disabled);
 }
 choices.hidden=!choices.hidden;
 newCampaign.setAttribute('aria-expanded',String(!choices.hidden));
};
$('#refreshCampaigns').before(newCampaign,choices);
const navigateBeforeAmigozCampaigns=navigate;
navigate=function(page){
 navigateBeforeAmigozCampaigns(page);
 if(currentPage==='campaigns')refreshAmigozCampaignList();
 else{amigozCampaignRows=[];amigozCampaignEpoch=-1;campaignFeedback.textContent='';choices.hidden=true;newCampaign.setAttribute('aria-expanded','false');}
};
