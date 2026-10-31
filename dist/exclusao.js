// Deletion is authorized in Supabase with owner-scoped RLS and cascading FKs.
let deletionBusy=false;
async function deleteConsultation(id){
 if(deletionBusy||!authenticated)return;
 const row=records.find(r=>r.id===id);if(!row)return;
 const running=row.status==='Processando'?' O atendimento já iniciado no banco pode continuar até encerrar.':'';
 if(!window.confirm(`Excluir a consulta de ${row.nome}? Seus resultados e simulações serão apagados definitivamente.${running}`))return;
 deletionBusy=true;const epoch=authEpoch;
 try{
 const deleted=await sbRequest('/rest/v1/consulta_jobs?id=eq.'+encodeURIComponent(id),{method:'DELETE',headers:{Prefer:'return=representation'}});
 if(epoch!==authEpoch)return;
 if(!deleted?.length)throw Error('Consulta não encontrada ou já excluída.');
 records=records.filter(r=>r.id!==id);
 if(typeof amigozCurrent!=='undefined'&&amigozCurrent?.job_id===id)resetAmigoz();
 render();toast('Consulta excluída.');await loadCloud();
 }catch(e){if(epoch===authEpoch)toast(e.message);}finally{deletionBusy=false;}
}
$('#deleteCampaign').onclick=async()=>{
 if(deletionBusy||!authenticated)return;
 const campaign=campaigns.find(c=>c.id===activeCampaign);if(!campaign)return;
 const rows=campaignRecords(campaign.id);
 const running=rows.some(r=>r.status==='Processando')?' O atendimento já iniciado no banco pode continuar até encerrar.':'';
 if(!window.confirm(`Excluir a campanha "${campaign.nome}" e todas as suas ${rows.length} consultas? Resultados e simulações serão apagados definitivamente.${running}`))return;
 deletionBusy=true;$('#deleteCampaign').disabled=true;const epoch=authEpoch;
 try{
 const deleted=await sbRequest('/rest/v1/consulta_lotes?id=eq.'+encodeURIComponent(campaign.id)+'&tipo=eq.campanha',{method:'DELETE',headers:{Prefer:'return=representation'}});
 if(epoch!==authEpoch)return;
 if(!deleted?.length)throw Error('Campanha não encontrada ou já excluída.');
 if(typeof amigozCurrent!=='undefined'&&rows.some(r=>r.id===amigozCurrent?.job_id))resetAmigoz();
 records=records.filter(r=>r.lote_id!==campaign.id);campaigns=campaigns.filter(c=>c.id!==campaign.id);activeCampaign=null;
 render();toast('Campanha e consultas excluídas.');await loadCloud();
 }catch(e){if(epoch===authEpoch)toast(e.message);}finally{deletionBusy=false;$('#deleteCampaign').disabled=false;}
};
for(const selector of ['#rows','#campaignRows']){
 const previous=$(selector).onclick;$(selector).onclick=e=>{const id=e.target.dataset.deleteJob;if(id)return deleteConsultation(id);if(previous)return previous(e);};
}
