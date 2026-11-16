// All financial calculations run in Supabase, using the saved job and commissions.
let amigozReturnFocus=null;
let amigozCurrent=null,amigozBusy=false,amigozGeneration=0,amigozDirty=false;
const amigozRates=[3,3.25,3.5,3.75,3.98,4.5];
const brl=v=>Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
function amigozAction(r){
 if(r.servico==='tjba_margem')return '';
 const valid=r.saldo>0&&r.valorParcela>0&&!['Aguardando','Processando','Não é cliente'].includes(r.status);
 return valid?`<button data-simulate="${escapeHTML(r.id)}">Simular Amigoz</button>`:'<small class="muted">Simulação: aguarde saldo e parcela válidos.</small>';
}
function resetAmigoz(){amigozGeneration++;amigozCurrent=null;amigozDirty=false;$('#amigozPrazo').value=96;$('#amigozAlterarParcela').checked=false;$('#amigozNovaParcela').value='';$('#amigozNovaParcela').disabled=true;$('#amigozMarginInfo').textContent='';amigozBusy=false;$('#amigozPanel').hidden=true;$('#appShell').inert=false;$('#amigozCards').innerHTML='';}
function refreshAmigoz(){
 if(!amigozCurrent)return;
 const r=records.find(r=>r.id===amigozCurrent.job_id);
 const stale=!r||r.saldo!==Number(amigozCurrent.saldo)||r.valorParcela!==Number(amigozCurrent.parcela)||['Aguardando','Processando','Não é cliente'].includes(r.status);
 $('#amigozStale').hidden=!stale&&!amigozDirty;$('#amigozStale').textContent=stale?'Dados da consulta alterados. Recalcule.':'Condições alteradas. Recalcule para atualizar os valores.';$('#amigozCards').hidden=stale;
 $('#amigozRecalculate').disabled=amigozBusy||!r||!(r.saldo>0&&r.valorParcela>0)||['Aguardando','Processando','Não é cliente'].includes(r.status);
}
async function simulateAmigoz(id){
 if(amigozBusy)return;const same=amigozCurrent?.job_id===id;let conditions;try{conditions=readAmigozConditions();}catch(error){toast(error.message);return;}if(!same){$('#amigozPrazo').value=96;$('#amigozAlterarParcela').checked=false;$('#amigozNovaParcela').disabled=true;$('#amigozNovaParcela').value=records.find(r=>r.id===id)?.valorParcela||'';}if($('#amigozAlterarParcela').checked){const chosen=Number($('#amigozNovaParcela').value);if(!Number.isFinite(chosen)||chosen<=0){toast('Informe uma parcela total positiva.');return;}conditions._parcela_simulada=chosen;}const prazo=Number($('#amigozPrazo').value||96);if(!Number.isInteger(prazo)||prazo<1||prazo>600){toast('Use um prazo inteiro entre 1 e 600 meses.');return;}amigozBusy=true;const generation=amigozGeneration;
 if($('#amigozPanel').hidden){amigozReturnFocus=document.activeElement;$('#amigozPanel').hidden=false;$('#amigozPanel').scrollTop=0;$('#appShell').inert=true;$('#amigozClose').focus?.();}$('#amigozCards').innerHTML='';$('#amigozCards').setAttribute?.('aria-busy','true');$('#amigozStatus').textContent='Calculando as sete tabelas…';$('#amigozRecalculate').textContent='Calculando…';$('#amigozRecalculate').disabled=true;
 try{
 const result=await sbRequest('/rest/v1/rpc/simular_amigoz_price',{method:'POST',body:JSON.stringify({p_job_id:id,p_prazo:prazo,p_condicoes:conditions})});
 if(generation!==amigozGeneration||!authenticated)return;
 amigozCurrent=result;$('#amigozMarginInfo').textContent='Parcela original: '+brl(result.parcela)+' · Parcela simulada: '+brl(result.parcela_simulada??result.parcela)+' · Margem adicional necessária: '+brl(result.margem_adicional??0);
 $('#amigozClient').textContent=records.find(r=>r.id===id)?.nome||'Cliente';
 amigozDirty=false;$('#amigozCards').innerHTML=renderAmigozTables(result.tabelas);
 $('#amigozStatus').textContent='Simulação atualizada. Compare as opções abaixo.';
 }catch(e){if(generation===amigozGeneration){amigozCurrent=null;$('#amigozStatus').textContent=e.message;}}
 finally{if(generation===amigozGeneration){amigozBusy=false;$('#amigozCards').setAttribute?.('aria-busy','false');$('#amigozRecalculate').textContent='Recalcular simulação';refreshAmigoz();}}
}
function rateKey(rate){return String(Number(rate)).replace('.','_');}
function readAmigozConditions(){
 return Object.fromEntries(amigozRates.map(rate=>[String(rate),{encargos_modo:'sem_encargos'}]));
}
function renderAmigozTables(tables){
 const candidates=tables.filter(t=>!t.insuficiente&&t.troco!=null&&Number.isFinite(Number(t.troco)));
 const best=candidates.length?Math.max(...candidates.map(t=>Number(t.troco))):null;
 return tables.map(t=>renderAmigozTable(t,best!==null&&!t.insuficiente&&t.troco!=null&&Number(t.troco)===best)).join('');
}
function renderAmigozTable(t,best=false){
 const available=!t.insuficiente&&t.troco!=null;
 return `<article class="card amigoz-option${best?' amigoz-best':''}"><div class="amigoz-option-top"><h4>${Number(t.taxa).toFixed(2).replace('.',',')}% <small>a.m.</small></h4>${best?'<span class="amigoz-best-label">Maior troco</span>':''}</div><p class="amigoz-option-term">${escapeHTML(t.prazo||$('#amigozPrazo').value||96)} parcelas · estimativa antes dos encargos</p><dl><div class="amigoz-troco"><dt>Troco estimado</dt><dd class="amigoz-cash${available?'':' amigoz-unavailable'}">${t.insuficiente?'Limite insuficiente':t.troco==null?'Não disponível':brl(t.troco)}</dd>${t.insuficiente?'<p>O limite desta tabela não cobre a quitação.</p>':''}</div><div class="amigoz-amount-row"><dt>Limite estimado</dt><dd>${t.limite==null?'Não disponível':brl(t.limite)}</dd></div><div class="amigoz-amount-row"><dt>Valor de quitação</dt><dd>${brl(t.quitacao)}</dd></div>${t.percentual!=null&&t.comissao!=null?`<div class="amigoz-commission"><dt>Comissão estimada do vendedor (${Number(t.percentual).toLocaleString('pt-BR')}%)</dt><dd>${brl(t.comissao)}</dd></div>`:''}</dl></article>`;
}
function closeAmigoz(){$('#amigozPanel').hidden=true;$('#appShell').inert=false;amigozReturnFocus?.focus?.();}
$('#amigozClose').onclick=closeAmigoz;
$('#amigozPanel').onkeydown=e=>{
 if(e.key==='Escape'){e.preventDefault();closeAmigoz();return;}
 if(e.key!=='Tab')return;
 const controls=[...$('#amigozPanel').querySelectorAll('button:not(:disabled),input:not(:disabled)')],first=controls[0],last=controls.at(-1);
 if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}
 else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}
};
$('#amigozRecalculate').onclick=()=>{if(amigozCurrent)simulateAmigoz(amigozCurrent.job_id);};
for(const selector of ['#rows','#campaignRows']){
 const previous=$(selector).onclick;$(selector).onclick=e=>{const id=e.target.dataset.simulate;if(id){simulateAmigoz(id);return;}if(previous)return previous(e);};
}

$('#amigozCards').oninput=()=>{amigozDirty=true;refreshAmigoz();};$('#amigozCards').onchange=$('#amigozCards').oninput;$('#amigozPrazo').oninput=$('#amigozCards').oninput;

$('#amigozAlterarParcela').onchange=()=>{$('#amigozNovaParcela').disabled=!$('#amigozAlterarParcela').checked;amigozDirty=true;refreshAmigoz();};$('#amigozNovaParcela').oninput=()=>{amigozDirty=true;refreshAmigoz();};
