// One server-side decimal engine supplies both the dialog and downloadable bases.
const amigozEstimateRates = [3, 3.25, 3.5, 3.75, 3.98, 4.5];
const amigozEstimateHeaders = [
  ...amigozEstimateRates.map(rate => 'Saque líquido estimado · '+rate.toFixed(2).replace('.', ',')+'% a.m.'),
  'Base da simulação', 'Margem agregada', 'Prazo da simulação', 'Situação da estimativa', 'Versão dos coeficientes'
];
let amigozContext = null;
let amigozSource = null;
const amigozControls = document.querySelector('.amigoz-controls');
amigozControls.classList.add('coefficient-controls');
amigozControls.innerHTML = `
 <div><label class="field" for="amigozAgreement">Convênio</label><select id="amigozAgreement"></select></div>
 <div><label class="field" for="amigozBaseMode">Base da simulação</label><select id="amigozBaseMode">
  <option value="original">Parcela atual</option><option value="aggregate">Parcela atual + margem consultada</option>
  <option value="margin">Margem consultada</option><option value="manual">Informar parcela total</option>
 </select></div>
 <div id="amigozMarginField" hidden><label class="field" for="amigozMarginSelect">Margem do cliente</label><select id="amigozMarginSelect"></select></div>
 <div id="amigozManualField" hidden><label class="field" for="amigozManualTotal">Parcela total desejada (R$)</label><input id="amigozManualTotal" type="number" min="0.01" step="0.01"></div>
 <div class="amigoz-update"><button id="amigozCoefficientCalculate" class="primary" type="button">Simular em 96 parcelas</button></div>
 <details class="amigoz-field-wide"><summary>Consultar ou atualizar margem pela API Amigoz</summary>
 <p id="amigozQueryMarginHint">Use o convênio selecionado para consultar a margem e salvar no histórico do cliente.</p>
 <label class="field" for="amigozQueryRegistration">Matrícula (opcional)</label><input id="amigozQueryRegistration" maxlength="256">
 <label class="field" for="amigozQueryPassword">Senha do servidor (se exigida pelo convênio)</label><input id="amigozQueryPassword" type="password" autocomplete="off" maxlength="256">
 <button id="amigozQueryMargin" type="button">Consultar margem do cliente</button>
 <p id="amigozQueryMarginStatus" role="status"></p>
 <details id="amigozMarginDiagnostic" hidden><summary>Log da consulta · administrador</summary>
 <pre class="log-code" tabindex="0"><code id="amigozMarginDiagnosticText"></code></pre></details></details>`;
document.querySelector('.amigoz-disclaimer').textContent = 'Simulação preliminar com coeficientes observados e IOF estimado. Valores sujeitos à confirmação no banco.';

function coefficientRequest(name, body) {
  return sbRequest('/rest/v1/rpc/'+name, {method:'POST', body:JSON.stringify(body)});
}
function setCoefficientBusy(busy) {
  for (const id of ['#amigozAgreement','#amigozBaseMode','#amigozMarginSelect','#amigozManualTotal','#amigozCoefficientCalculate','#amigozQueryMargin','#amigozQueryRegistration','#amigozQueryPassword']) $(id).disabled=busy;
}
function coefficientMarginFields() {
  const mode = $('#amigozBaseMode').value;
  $('#amigozMarginField').hidden = !['margin','aggregate'].includes(mode);
  $('#amigozManualField').hidden = mode !== 'manual';
  $('#amigozCards').innerHTML = '';
  $('#amigozStatus').textContent = 'Condições alteradas. Clique em Simular em 96 parcelas.';
}
function coefficientTablesValidated(result) {
 return result.tabelas.every(table=>table.regra_calculo==='limite_residual_v1');
}
function coefficientResultCards(result) {
 if(!coefficientTablesValidated(result))return '<p role="alert">Atualize o cálculo no banco com upgrade_amigoz_debt_cash.sql antes de simular. O cálculo antigo foi bloqueado.</p>';
 return result.tabelas.map(table => {
  const title={limite_insuficiente:'Limite insuficiente',pre_aprovada_sem_troco:'Pré-aprovada sem troco',pre_aprovada_com_troco:'Pré-aprovada com troco',quitacao_pendente:'Quitação pendente'}[table.situacao]||'Simulação indisponível';
  return `<article class="card amigoz-option">
    <div class="amigoz-option-top"><h4>${table.nome_tabela?escapeHTML(table.nome_tabela)+' · ':''}${Number(table.taxa).toFixed(2).replace('.',',')}% <small>a.m.</small></h4></div>
    <p class="amigoz-option-term">96 parcelas · simulação preliminar</p><p><strong>${title}</strong></p><dl>
    <div class="amigoz-troco"><dt>Troco estimado</dt><dd class="amigoz-cash">${table.troco==null?'Pendente':brl(table.troco)}</dd></div>
    <div class="amigoz-amount-row"><dt>Limite do cartão</dt><dd>${brl(table.limite)}</dd></div>
    <div class="amigoz-amount-row"><dt>Valor da quitação</dt><dd>${table.quitacao == null ? 'Não informado' : brl(table.quitacao)}</dd></div>
    <div class="amigoz-amount-row"><dt>Limite restante após quitação</dt><dd>${table.limite_restante==null?'Pendente':brl(table.limite_restante)}</dd></div>
    ${table.comissao!=null?`<div class="amigoz-commission"><dt>Comissão estimada (${Number(table.percentual).toLocaleString('pt-BR')}%)</dt><dd>${brl(table.comissao)}</dd></div>`:''}
    </dl><p>${escapeHTML(table.motivo||'')}</p></article>`;
 }).join('');
}
async function loadCoefficientContext() {
  if (!amigozSource) return;
  const generation = ++amigozGeneration;
  amigozCurrent = null;
  setCoefficientBusy(true);
  $('#amigozCards').innerHTML = '';
  try {
    const context = await coefficientRequest('amigoz_simulation_context', {
      p_cpf:amigozSource.cpf, p_convenio:amigozSource.convenio || '', p_job_id:amigozSource.job_id || null
    });
    if (generation !== amigozGeneration || !authenticated) return;
    amigozContext = context;
    const agreements = context.convenios || context.config.eligibilidade;
    const select = $('#amigozAgreement');
    select.replaceChildren(new Option('Selecione o convênio', ''));
    for (const agreement of agreements) {
      select.add(new Option(agreement.nome || agreement.convenio, agreement.convenio));
    }
    select.value = context.convenio_assumido ? '' : (context.convenio || '');
    if (select.selectedIndex < 0) select.value='';
    $('#amigozMarginSelect').replaceChildren(new Option('Selecione a margem e o vínculo', ''));
    const products = {beneficio:'Cartão benefício', consignado:'Cartão consignado', cartao:'Cartão', emprestimo:'Empréstimo'};
    for (const margin of context.margens.filter(margin => margin.elegivel)) {
      $('#amigozMarginSelect').add(new Option([
        products[margin.produto], brl(margin.valor), margin.convenio,
        margin.matricula ? 'Matrícula '+margin.matricula : 'Matrícula não informada', margin.instituicao,
        new Date(margin.observado_em).toLocaleString('pt-BR')
      ].join(' · '), margin.key));
    }
    $('#amigozQueryMarginHint').textContent=context.margens.some(m=>m.elegivel)?'Há margem registrada. Consulte novamente apenas se precisar atualizá-la.':'Não há margem elegível registrada. Consulte pela API Amigoz para comparar usando a margem disponível.';
    const original = context.fonte.parcela;
    $('#amigozBaseMode').value = amigozSource.margin ? 'margin' : original > 0 ? 'original' : 'margin';
    $('#amigozManualTotal').value = original || '';
    coefficientMarginFields();
    $('#amigozMarginInfo').textContent = 'Parcela atual '+(original == null ? 'não informada' : brl(original));
    $('#amigozStatus').textContent = !select.value ? 'Selecione o convênio do cliente.' : context.elegivel ? 'Selecione a base para simular.' : 'Este convênio ainda não tem tabela de simulação configurada.';
  } catch (error) {
    if (generation === amigozGeneration) $('#amigozStatus').textContent = error.message;
  } finally {
    if (generation === amigozGeneration) setCoefficientBusy(false);
  }
}
function clearAmigozMarginDiagnostic() {
 const panel=$('#amigozMarginDiagnostic');
 panel.open=false;
 panel.hidden=true;
 $('#amigozMarginDiagnosticText').textContent='';
}
async function openAmigozClient(cpf, convenio='', jobId=null, name='', margin=false) {
  clearAmigozMarginDiagnostic();
  $('#amigozQueryMarginStatus').textContent='';
  $('#amigozQueryRegistration').value='';$('#amigozQueryPassword').value='';
  amigozSource = {cpf:String(cpf).replace(/\D/g,''), convenio, job_id:jobId, margin};
  amigozReturnFocus = document.activeElement;
  $('#amigozPanel').hidden = false;
  $('#appShell').inert = true;
  $('#amigozClient').textContent = name || formatCpf(cpf);
  $('#amigozStale').hidden = true;
  $('#amigozCards').hidden = false;
  $('#amigozClose').focus();
  await loadCoefficientContext();
}
simulateAmigoz = async function(id) {
  const row = records.find(row => row.id === id);
  if (!row) return;
  await openAmigozClient(row.cpf, row.convenio || '', row.servico === 'tjba_margem' ? null : row.id, row.nome, row.servico === 'tjba_margem');
};
amigozAction = function(row) {
  if (['Aguardando','Processando'].includes(row.status)) return '';
  return `<button data-simulate="${escapeHTML(row.id)}">Simular Amigoz</button>`;
};
resetAmigoz = function() {
  clearAmigozMarginDiagnostic();
  amigozGeneration++;
  amigozCurrent = null;
  amigozContext = null;
  amigozSource = null;
  $('#amigozQueryPassword').value='';$('#amigozQueryRegistration').value='';$('#amigozQueryMarginStatus').textContent='';
  amigozBusy = false;
  $('#amigozPanel').hidden = true;
  $('#appShell').inert = false;
  $('#amigozCards').innerHTML = '';
};
const coefficientPreviousClose=closeAmigoz;
closeAmigoz=function(){
 clearAmigozMarginDiagnostic();
 amigozGeneration++;amigozSource=null;amigozBusy=false;
 $('#amigozQueryPassword').value='';
 coefficientPreviousClose();
};
$('#amigozClose').onclick=closeAmigoz;
$('#amigozQueryMargin').onclick=async()=>{
 if(!amigozSource||amigozBusy)return;
 const source=amigozSource,generation=amigozGeneration,epoch=authEpoch;
 const convenio=$('#amigozAgreement').value;
 clearAmigozMarginDiagnostic();
 if(!convenio){$('#amigozQueryMarginStatus').textContent='Selecione o convênio do cliente.';return;}
 const payload={cpf:source.cpf,convenio,matricula:$('#amigozQueryRegistration').value.trim(),senha:$('#amigozQueryPassword').value};
 $('#amigozQueryPassword').value='';
 amigozBusy=true;setCoefficientBusy(true);
 $('#amigozQueryMarginStatus').textContent='Consultando margem pela API Amigoz…';
 $('#amigozCards').innerHTML='';amigozCurrent=null;
 try{
  if(typeof window.consultarMargemAmigozSimulador!=='function')throw Error('Integração Amigoz indisponível. Recarregue o painel.');
  const result=await window.consultarMargemAmigozSimulador(payload);
  if(epoch!==authEpoch||generation!==amigozGeneration||source!==amigozSource||!authenticated)return;
  const diagnostic=result.diagnostico_admin?.margem;
  if(diagnostic&&amigozIsAdmin()){
   $('#amigozMarginDiagnosticText').textContent=[[diagnostic.http_status && `HTTP ${diagnostic.http_status}`,diagnostic.rota,diagnostic.codigo].filter(Boolean).join(' · '),
    `Convênio ${convenio}`,result.consulta_id&&`Consulta ${result.consulta_id}`,'',diagnostic.resposta].filter(x=>x!==false&&x!=null).join('\n');
   $('#amigozMarginDiagnostic').hidden=false;
   $('#amigozMarginDiagnostic').open=true;
  }
  if(result.salvo_no_historico===false){$('#amigozQueryMarginStatus').textContent='Consulta realizada, mas não foi salva no banco. Não repita; confira o histórico e o diagnóstico.';return;}
  if(result.margem?.status!=='respondido')throw Error('Não foi possível consultar a margem. Confira o convênio e os dados informados.');
  await loadCoefficientContext();
  if(epoch!==authEpoch||source!==amigozSource||!authenticated)return;
  $('#amigozQueryMarginStatus').textContent=amigozContext?.margens.some(m=>m.elegivel)
   ?'Margem atualizada. Selecione a base e o vínculo para recalcular a comparação.'
   :'Consulta finalizada, mas nenhuma margem elegível foi registrada para este convênio. Confira o cadastro e o retorno da API.';
 }catch(error){if(epoch===authEpoch&&generation===amigozGeneration)$('#amigozQueryMarginStatus').textContent='Não foi possível consultar a margem. Confira o convênio e os dados informados.';}
 finally{payload.senha='';if(epoch===authEpoch&&source===amigozSource){amigozBusy=false;setCoefficientBusy(false);}}
};
$('#amigozAgreement').onchange = async () => {
  if (!amigozSource) return;
  clearAmigozMarginDiagnostic();
  $('#amigozQueryMarginStatus').textContent='';
  amigozSource.convenio = $('#amigozAgreement').value;
  await loadCoefficientContext();
};
for (const id of ['#amigozBaseMode','#amigozMarginSelect','#amigozManualTotal']) $(id).oninput = coefficientMarginFields;
$('#amigozCoefficientCalculate').onclick = async () => {
  if (!amigozSource || amigozBusy) return;
  const generation = amigozGeneration;
  const agreement = $('#amigozAgreement').value;
  if (!agreement) {$('#amigozStatus').textContent = 'Selecione o convênio.';return;}
  if(!amigozContext?.elegivel){$('#amigozStatus').textContent='Este convênio ainda não tem tabela de simulação configurada.';return;}
  amigozBusy = true;
  setCoefficientBusy(true);
  $('#amigozStatus').textContent = 'Calculando as tabelas…';
  $('#amigozCards').innerHTML = '';
  try {
    const result = await coefficientRequest('amigoz_simular_coeficientes', {p_input:{
      cpf:amigozSource.cpf, convenio:agreement, job_id:amigozSource.job_id,
      mode:$('#amigozBaseMode').value, margin_key:$('#amigozMarginSelect').value,
      manual:$('#amigozManualTotal').value === '' ? null : Number($('#amigozManualTotal').value), prazo:96
    }});
    if (generation !== amigozGeneration || !authenticated) return;
    amigozCurrent = result;
    $('#amigozCards').innerHTML = coefficientResultCards(result);
    $('#amigozStatus').textContent = coefficientTablesValidated(result)?result.motivo:'Atualização do cálculo no banco necessária. Simulação antiga bloqueada.';
    if (result.base != null) $('#amigozMarginInfo').textContent = 'Base utilizada '+brl(result.base)+
      ' · Margem agregada '+brl(result.margem_adicional)+' · Tabela versão '+result.version_id;
  } catch (error) {
    if (generation === amigozGeneration) $('#amigozStatus').textContent = error.message;
  } finally {
    if (generation === amigozGeneration) {amigozBusy=false;setCoefficientBusy(false);}
  }
};

async function amigozExportEstimates(inputs) {
  const epoch = authEpoch;
  const rows = [];
  for (let start=0; start<inputs.length; start+=100) {
    const results = await coefficientRequest('amigoz_exportar_estimativas', {p_items:inputs.slice(start,start+100)});
    if (epoch !== authEpoch || !authenticated) throw Error('Sessão encerrada.');
    if(results.some(result=>!coefficientTablesValidated(result)))throw Error('Atualize o cálculo Amigoz no banco antes de exportar estimativas.');
    for (const result of results) rows.push([
      ...amigozEstimateRates.map(rate => result.tabelas.find(table => Number(table.taxa) === rate)?.troco ?? ''),
      result.base ?? '', result.margem_adicional ?? '', result.prazo ?? '', result.motivo || '', result.version_id ?? ''
    ]);
  }
  return rows;
}
async function amigozAppendExport(rows, inputs) {
  const values = await amigozExportEstimates(inputs);
  return [rows[0].concat(amigozEstimateHeaders), ...rows.slice(1).map((row,index) => row.concat(values[index]))];
}

const coefficientExportResults = exportResults;
exportResults = async function(items, filename='consultas.csv') {
  try {await coefficientExportResults(items,filename);}
  catch (error) {toast('Não foi possível exportar as estimativas. '+error.message);}
};

let amigozFreshnessCheck = false;
let amigozFreshnessAt = 0;
refreshAmigoz = async function() {
  if (!amigozCurrent?.tabelas?.length || !amigozSource || $('#amigozPanel').hidden || amigozFreshnessCheck || Date.now()-amigozFreshnessAt<15000) return;
  amigozFreshnessCheck = true;
  amigozFreshnessAt = Date.now();
  const generation = amigozGeneration;
  try {
    const current = await coefficientRequest('amigoz_simulation_context', {
      p_cpf:amigozSource.cpf,p_convenio:amigozCurrent.convenio,p_job_id:amigozSource.job_id
    });
    if (generation !== amigozGeneration || !amigozCurrent) return;
    const selected = amigozCurrent.margem_selecionada;
    const margin = selected && current.margens.find(item=>item.key===selected.key);
    const stale = current.version_id!==amigozCurrent.version_id || !current.elegivel ||
      JSON.stringify(current.fonte)!==JSON.stringify(amigozCurrent.fonte) ||
      (selected && (!margin || !margin.elegivel || margin.valor!==selected.valor || margin.observado_em!==selected.observado_em));
    if (stale) {
      $('#amigozCards').innerHTML = '';
      $('#amigozStatus').textContent = 'Dados atualizados. Recalcule para conferir os novos valores.';
    }
  } catch {
    if (generation===amigozGeneration) $('#amigozStatus').textContent='Não foi possível confirmar a atualização dos dados. Recalcule antes de usar os valores.';
  } finally {amigozFreshnessCheck=false;}
};
setInterval(refreshAmigoz,15000);

$('#amigozPanel').onkeydown = event => {
  if(event.key==='Escape') {event.preventDefault();closeAmigoz();return;}
  if(event.key!=='Tab') return;
  const controls=[...$('#amigozPanel').querySelectorAll('button:not(:disabled), input:not(:disabled), select:not(:disabled)')].filter(element=>element.offsetParent!==null);
  const first=controls[0], last=controls.at(-1);
  if(event.shiftKey && document.activeElement===first) {event.preventDefault();last?.focus();}
  else if(!event.shiftKey && document.activeElement===last) {event.preventDefault();first?.focus();}
};

function amigozCsvCells(row) {
  const first = row.length - amigozEstimateHeaders.length;
  return row.map((value,index) => index>=first && index<first+8 && typeof value==='number'
    ? value.toFixed(2).replace('.',',') : value);
}

if(authenticated && currentAccess) applyAccessUi();
