// All financial calculations run in Supabase, using the saved job and commissions.
let amigozCurrent=null,amigozBusy=false,amigozGeneration=0;
const amigozRates=[3,3.25,3.5,3.75,3.98,4.5,4.8];
const brl=v=>Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
function amigozAction(r){
 const valid=r.saldo>0&&r.valorParcela>0&&!['Aguardando','Processando','Não é cliente'].includes(r.status);
 return valid?`<button data-simulate="${escapeHTML(r.id)}">Simular Amigoz</button>`:'<small class="muted">Simulação: aguarde saldo e parcela válidos.</small>';
}
function resetAmigoz(){amigozGeneration++;amigozCurrent=null;amigozBusy=false;$('#amigozPanel').hidden=true;$('#amigozCards').innerHTML='';$('#amigozSettingsStatus').textContent='';for(const rate of amigozRates)$('#commission-'+String(rate).replace('.','_')).value='';}
function refreshAmigoz(){
 if(!amigozCurrent)return;
 const r=records.find(r=>r.id===amigozCurrent.job_id);
 const stale=!r||r.saldo!==Number(amigozCurrent.saldo)||r.valorParcela!==Number(amigozCurrent.parcela)||['Aguardando','Processando','Não é cliente'].includes(r.status);
 $('#amigozStale').hidden=!stale;$('#amigozCards').hidden=stale;
 $('#amigozRecalculate').disabled=amigozBusy||!r||!(r.saldo>0&&r.valorParcela>0)||['Aguardando','Processando','Não é cliente'].includes(r.status);
}
async function simulateAmigoz(id){
 if(amigozBusy)return;amigozBusy=true;const generation=amigozGeneration;
 $('#amigozPanel').hidden=false;$('#amigozCards').innerHTML='';$('#amigozStatus').textContent='Calculando…';$('#amigozRecalculate').disabled=true;
 try{
 const result=await sbRequest('/rest/v1/rpc/simular_amigoz',{method:'POST',body:JSON.stringify({p_job_id:id})});
 if(generation!==amigozGeneration||!authenticated)return;
 amigozCurrent=result;
 $('#amigozClient').textContent=records.find(r=>r.id===id)?.nome||'Cliente';
 $('#amigozCards').innerHTML=result.tabelas.map(t=>`<article class="card"><h2>Tabela ${Number(t.taxa).toFixed(2).replace('.',',')}%</h2><p class="muted">Estimativa teórica</p><dl><dt>Limite</dt><dd>Não disponível</dd><dt>Troco</dt><dd class="amigoz-cash">${t.insuficiente?'Disponibilidade estimada insuficiente':brl(t.troco)}</dd><dt>Valor de quitação</dt><dd>${brl(t.quitacao)}</dd>${t.percentual!=null?`<dt>Comissão do vendedor (${Number(t.percentual).toLocaleString('pt-BR')}%)</dt><dd>${t.comissao==null?'Não disponível':brl(t.comissao)}</dd>`:''}</dl></article>`).join('');
 $('#amigozStatus').textContent='Simulação salva. Valores estimados, sujeitos à confirmação bancária.';
 }catch(e){if(generation===amigozGeneration){amigozCurrent=null;$('#amigozStatus').textContent=e.message;}}
 finally{if(generation===amigozGeneration){amigozBusy=false;refreshAmigoz();}}
}
async function loadAmigozSettings(){
 const epoch=authEpoch;$('#saveAmigoz').disabled=true;
 try{const rows=await sbRequest('/rest/v1/amigoz_comissoes?select=taxa,percentual');if(epoch!==authEpoch)return;
 for(const rate of amigozRates)$('#commission-'+String(rate).replace('.','_')).value=rows.find(r=>Number(r.taxa)===rate)?.percentual??'';
 $('#amigozSettingsStatus').textContent='Percentuais salvos por conta. Deixe vazio para ocultar a comissão.';$('#saveAmigoz').disabled=false;
 }catch(e){if(epoch===authEpoch)$('#amigozSettingsStatus').textContent='Não foi possível carregar os percentuais: '+e.message;}
}
$('#amigozCommissions').innerHTML=amigozRates.map(rate=>`<div><label class="field" for="commission-${String(rate).replace('.','_')}">Tabela ${rate.toFixed(2).replace('.',',')}% · comissão (%)</label><input id="commission-${String(rate).replace('.','_')}" type="number" min="0" max="100" step="0.0001" placeholder="Não configurada"></div>`).join('');
$('#amigozSettings').onsubmit=async e=>{
 e.preventDefault();const epoch=authEpoch;$('#saveAmigoz').disabled=true;
 try{const rows=amigozRates.map(taxa=>{const value=$('#commission-'+String(taxa).replace('.','_')).value.trim(),percentual=value===''?null:Number(value.replace(',','.'));if(percentual!==null&&(!Number.isFinite(percentual)||percentual<0||percentual>100))throw Error('Use percentuais entre 0 e 100.');return {user_id:session.user.id,taxa,percentual};});
 await sbRequest('/rest/v1/amigoz_comissoes?on_conflict=user_id,taxa',{method:'POST',headers:{Prefer:'resolution=merge-duplicates'},body:JSON.stringify(rows)});
 if(epoch!==authEpoch)return;$('#amigozSettingsStatus').textContent='Comissões salvas.';
 if(amigozCurrent)await simulateAmigoz(amigozCurrent.job_id);
 }catch(e){if(epoch===authEpoch)$('#amigozSettingsStatus').textContent=e.message;}finally{if(epoch===authEpoch)$('#saveAmigoz').disabled=false;}
};
$('#amigozClose').onclick=()=>{$('#amigozPanel').hidden=true;};
$('#amigozRecalculate').onclick=()=>{if(amigozCurrent)simulateAmigoz(amigozCurrent.job_id);};
for(const selector of ['#rows','#campaignRows']){
 const previous=$(selector).onclick;$(selector).onclick=e=>{const id=e.target.dataset.simulate;if(id){simulateAmigoz(id);return;}if(previous)return previous(e);};
}
