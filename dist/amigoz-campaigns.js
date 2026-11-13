async function refreshAmigozCampaignList(){
 const section=$('#amigozCampaigns'), list=$('#amigozCampaignRows'), epoch=authEpoch;
 if(!section||!authenticated||currentPage!=='campaigns')return;
 try{
  const rows=await crmRpc('crm_listar_campanhas_amigoz',{});
  if(epoch!==authEpoch||currentPage!=='campaigns')return;
  list.replaceChildren(...(rows.length?rows.map(row=>crmElement('li','',row.nome+' · '+row.leads+' leads · '+row.pendentes+' pendentes · '+row.concluidas+' concluídos · '+row.atencao+' com falha ou em revisão')):[crmElement('li','','Nenhuma campanha Amigoz encontrada.')]));
 }catch(error){if(epoch===authEpoch)list.textContent=error.message;}
}
const amigozCampaignSection=document.createElement('section');
amigozCampaignSection.className='card';
amigozCampaignSection.id='amigozCampaigns';
amigozCampaignSection.innerHTML='<div class="heading"><h2>Campanhas Amigoz</h2><div class="actions"><button type="button" id="createAmigozCampaign" class="primary">Nova campanha Amigoz</button><button type="button" id="refreshAmigozCampaigns">Atualizar</button></div></div><ul id="amigozCampaignRows"></ul>';
$('#campaignDetail').before(amigozCampaignSection);
$('#createAmigozCampaign').onclick=()=>crmOpenClientImport(true);
$('#refreshAmigozCampaigns').onclick=refreshAmigozCampaignList;
const navigateBeforeAmigozCampaigns=navigate;
navigate=function(page){
 navigateBeforeAmigozCampaigns(page);
 if(currentPage==='campaigns')refreshAmigozCampaignList();
 else $('#amigozCampaignRows').replaceChildren();
};
