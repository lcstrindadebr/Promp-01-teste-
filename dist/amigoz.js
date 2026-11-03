// All financial calculations run in Supabase, using the saved job and commissions.
let amigozCurrent=null,amigozBusy=false,amigozGeneration=0,amigozDirty=false;
const amigozRates=[3,3.25,3.5,3.75,3.98,4.5,4.8];
const brl=v=>Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
function amigozAction(r){
 if(r.servico==='tjba_margem')return '';
 const valid=r.saldo>0&&r.valorParcela>0&&!['Aguardando','Processando','Não é cliente'].includes(r.status);
 return valid?`<button data-simulate="${escapeHTML(r.id)}">Simular Amigoz</button>`:'<small class="muted">Simulação: aguarde saldo e parcela válidos.</small>';
}
function resetAmigoz(){amigozGeneration++;amigozCurrent=null;amigozDirty=false;$('#amigozPrazo').value=96;$('#amigozAlterarParcela').checked=false;$('#amigozNovaParcela').value='';$('#amigozNovaParcela').disabled=true;$('#amigozMarginInfo').textContent='';amigozBusy=false;$('#amigozPanel').hidden=true;$('#amigozCards').innerHTML='';$('#amigozSettingsStatus').textContent='';for(const rate of amigozRates)$('#commission-'+String(rate).replace('.','_')).value='';}
function refreshAmigoz(){
 if(!amigozCurrent)return;
 const r=records.find(r=>r.id===amigozCurrent.job_id);
 const stale=!r||r.saldo!==Number(amigozCurrent.saldo)||r.valorParcela!==Number(amigozCurrent.parcela)||['Aguardando','Processando','Não é cliente'].includes(r.status);
 $('#amigozStale').hidden=!stale&&!amigozDirty;$('#amigozStale').textContent=stale?'Dados da consulta alterados. Recalcule.':'Condições alteradas. Recalcule para atualizar os valores.';$('#amigozCards').hidden=stale;
 $('#amigozRecalculate').disabled=amigozBusy||!r||!(r.saldo>0&&r.valorParcela>0)||['Aguardando','Processando','Não é cliente'].includes(r.status);
}
async function simulateAmigoz(id){
 if(amigozBusy)return;const same=amigozCurrent?.job_id===id;let conditions;try{conditions=readAmigozConditions();}catch(error){toast(error.message);return;}if(!same){$('#amigozPrazo').value=96;$('#amigozAlterarParcela').checked=false;$('#amigozNovaParcela').disabled=true;$('#amigozNovaParcela').value=records.find(r=>r.id===id)?.valorParcela||'';}if($('#amigozAlterarParcela').checked){const chosen=Number($('#amigozNovaParcela').value);if(!Number.isFinite(chosen)||chosen<=0){toast('Informe uma parcela total positiva.');return;}conditions._parcela_simulada=chosen;}const prazo=Number($('#amigozPrazo').value||96);if(!Number.isInteger(prazo)||prazo<1||prazo>600){toast('Use um prazo inteiro entre 1 e 600 meses.');return;}amigozBusy=true;const generation=amigozGeneration;
 $('#amigozPanel').hidden=false;$('#amigozCards').innerHTML='';$('#amigozStatus').textContent='Calculando…';$('#amigozRecalculate').disabled=true;
 try{
 const result=await sbRequest('/rest/v1/rpc/simular_amigoz_price',{method:'POST',body:JSON.stringify({p_job_id:id,p_prazo:prazo,p_condicoes:conditions})});
 if(generation!==amigozGeneration||!authenticated)return;
 amigozCurrent=result;$('#amigozMarginInfo').textContent='Parcela original: '+brl(result.parcela)+' · Parcela simulada: '+brl(result.parcela_simulada??result.parcela)+' · Margem adicional necessária: '+brl(result.margem_adicional??0);
 $('#amigozClient').textContent=records.find(r=>r.id===id)?.nome||'Cliente';
 amigozDirty=false;$('#amigozCards').innerHTML=result.tabelas.map(renderAmigozTable).join('');
 $('#amigozStatus').textContent='Estimativas salvas com juros mensais, parcela e prazo. IOF, seguros, despesas e teto pré-aprovado não entram no cálculo. Valores sujeitos à confirmação do banco.';
 }catch(e){if(generation===amigozGeneration){amigozCurrent=null;$('#amigozStatus').textContent=e.message;}}
 finally{if(generation===amigozGeneration){amigozBusy=false;refreshAmigoz();}}
}
function rateKey(rate){return String(Number(rate)).replace('.','_');}
function readAmigozConditions(){
 return Object.fromEntries(amigozRates.map(rate=>[String(rate),{encargos_modo:'sem_encargos'}]));
}
function renderAmigozTable(t){
 return `<article class="card"><h2>Tabela ${Number(t.taxa).toFixed(2).replace('.',',')}% a.m.</h2><p class="muted">${escapeHTML(t.prazo||$('#amigozPrazo').value||96)} parcelas · estimativa antes dos encargos</p><dl><dt>Limite estimado</dt><dd>${t.limite==null?'Não disponível':brl(t.limite)}</dd><dt>Valor de quitação</dt><dd>${brl(t.quitacao)}</dd><dt>Troco estimado</dt><dd class="amigoz-cash">${t.insuficiente?'Limite insuficiente para quitação':t.troco==null?'Não disponível':brl(t.troco)}</dd>${t.percentual!=null&&t.comissao!=null?`<dt>Comissão estimada do vendedor (${Number(t.percentual).toLocaleString('pt-BR')}%)</dt><dd>${brl(t.comissao)}</dd>`:''}</dl></article>`;
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

$('#amigozCards').oninput=()=>{amigozDirty=true;refreshAmigoz();};$('#amigozCards').onchange=$('#amigozCards').oninput;$('#amigozPrazo').oninput=$('#amigozCards').oninput;

$('#amigozAlterarParcela').onchange=()=>{$('#amigozNovaParcela').disabled=!$('#amigozAlterarParcela').checked;amigozDirty=true;refreshAmigoz();};$('#amigozNovaParcela').oninput=()=>{amigozDirty=true;refreshAmigoz();};
