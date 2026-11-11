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
 <div class="amigoz-update"><button id="amigozCoefficientCalculate" class="primary" type="button">Simular em 96 parcelas</button></div>`;
document.querySelector('.amigoz-disclaimer').textContent = 'Simulação preliminar com coeficientes observados e IOF estimado. Valores sujeitos à confirmação no banco.';

function coefficientRequest(name, body) {
  return sbRequest('/rest/v1/rpc/'+name, {method:'POST', body:JSON.stringify(body)});
}
function setCoefficientBusy(busy) {
  for (const id of ['#amigozAgreement','#amigozBaseMode','#amigozMarginSelect','#amigozManualTotal','#amigozCoefficientCalculate']) $(id).disabled=busy;
}
function coefficientMarginFields() {
  const mode = $('#amigozBaseMode').value;
  $('#amigozMarginField').hidden = !['margin','aggregate'].includes(mode);
  $('#amigozManualField').hidden = mode !== 'manual';
  $('#amigozCards').innerHTML = '';
  $('#amigozStatus').textContent = 'Condições alteradas. Clique em Simular em 96 parcelas.';
}
function coefficientResultCards(result) {
  return result.tabelas.map(table => `<article class="card amigoz-option">
    <div class="amigoz-option-top"><h4>${Number(table.taxa).toFixed(2).replace('.',',')}% <small>a.m.</small></h4></div>
    <p class="amigoz-option-term">96 parcelas · simulação preliminar</p><dl>
    <div class="amigoz-troco"><dt>Troco estimado</dt><dd class="amigoz-cash">${brl(table.troco)}</dd></div>
    <div class="amigoz-amount-row"><dt>Limite do cartão</dt><dd>${brl(table.limite)}</dd></div>
    <div class="amigoz-amount-row"><dt>Valor da quitação</dt><dd>${table.quitacao == null ? 'Não informado' : brl(table.quitacao)}</dd></div>
    </dl></article>`).join('');
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
    const agreements = context.config.eligibilidade;
    $('#amigozAgreement').replaceChildren(new Option('Selecione o convênio', ''));
    for (const agreement of agreements) {
      const label = agreement.nome || (agreement.convenio==='amigoz_23' ? 'Governo de São Paulo' : agreement.convenio);
      $('#amigozAgreement').add(new Option(label, agreement.convenio));
    }
    $('#amigozAgreement').value = context.convenio || '';
    $('#amigozMarginSelect').replaceChildren(new Option('Selecione a margem e o vínculo', ''));
    const products = {beneficio:'Cartão benefício', consignado:'Cartão consignado', cartao:'Cartão', emprestimo:'Empréstimo'};
    for (const margin of context.margens.filter(margin => margin.elegivel)) {
      $('#amigozMarginSelect').add(new Option([
        products[margin.produto], brl(margin.valor), margin.convenio,
        margin.matricula ? 'Matrícula '+margin.matricula : 'Matrícula não informada', margin.instituicao,
        new Date(margin.observado_em).toLocaleString('pt-BR')
      ].join(' · '), margin.key));
    }
    const original = context.fonte.parcela;
    $('#amigozBaseMode').value = amigozSource.margin ? 'margin' : original > 0 ? 'original' : 'margin';
    $('#amigozManualTotal').value = original || '';
    coefficientMarginFields();
    $('#amigozMarginInfo').textContent = 'Parcela atual '+(original == null ? 'não informada' : brl(original))+
      (context.convenio_assumido ? ' · Convênio padrão Governo de São Paulo. Confirme antes de simular.' : '');
    $('#amigozStatus').textContent = context.elegivel ? 'Selecione a base para simular.' : 'Escolha um convênio com produto Amigoz habilitado.';
  } catch (error) {
    if (generation === amigozGeneration) $('#amigozStatus').textContent = error.message;
  } finally {
    if (generation === amigozGeneration) setCoefficientBusy(false);
  }
}
async function openAmigozClient(cpf, convenio='', jobId=null, name='', margin=false) {
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
  amigozGeneration++;
  amigozCurrent = null;
  amigozContext = null;
  amigozSource = null;
  amigozBusy = false;
  $('#amigozPanel').hidden = true;
  $('#appShell').inert = false;
  $('#amigozCards').innerHTML = '';
  modelAdmin.hidden = true;
  $('#amigozModelJSON').value = '';
  $('#amigozSaveModel').disabled = true;
  for(const rate of amigozRates) $('#commission-'+String(rate).replace('.','_')).value='';
};
$('#amigozAgreement').onchange = async () => {
  if (!amigozSource) return;
  amigozSource.convenio = $('#amigozAgreement').value;
  await loadCoefficientContext();
};
for (const id of ['#amigozBaseMode','#amigozMarginSelect','#amigozManualTotal']) $(id).oninput = coefficientMarginFields;
$('#amigozCoefficientCalculate').onclick = async () => {
  if (!amigozSource || amigozBusy) return;
  const generation = amigozGeneration;
  const agreement = $('#amigozAgreement').value;
  if (!agreement) {$('#amigozStatus').textContent = 'Selecione o convênio.';return;}
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
    $('#amigozStatus').textContent = result.motivo;
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

const modelAdmin = document.createElement('section');
modelAdmin.className = 'card';modelAdmin.hidden = true;
modelAdmin.innerHTML = `<h2>Coeficientes da simulação Amigoz</h2><p>Configuração técnica dos coeficientes observados, IOF histórico e elegibilidade por convênio. Cada gravação cria uma versão.</p><button type="button" id="amigozLoadModel">Carregar configuração atual</button><label class="field" for="amigozModelJSON">Tabela e regras de elegibilidade</label><textarea id="amigozModelJSON" rows="18" style="width:100%;font-family:monospace" spellcheck="false"></textarea><button type="button" id="amigozSaveModel" disabled>Salvar nova versão</button><p id="amigozModelStatus" role="status"></p>`;
$('#settings-commissions').appendChild(modelAdmin);
const coefficientAccess = applyAccessUi;
applyAccessUi = function() {
  coefficientAccess();
  modelAdmin.hidden = !(authenticated && currentAccess?.active && currentAccess.role === 'admin');
};
$('#amigozLoadModel').onclick = async () => {
  const epoch=authEpoch;
  try {
    const [row] = await sbRequest('/rest/v1/amigoz_model_versions?order=id.desc&limit=1');
    if (epoch !== authEpoch) return;
    $('#amigozModelJSON').value = JSON.stringify(row.config,null,2);
    $('#amigozModelStatus').textContent = 'Versão '+row.id;
    $('#amigozSaveModel').disabled = false;
  } catch (error) {if(epoch===authEpoch) $('#amigozModelStatus').textContent=error.message;}
};
$('#amigozSaveModel').onclick = async () => {
  const epoch=authEpoch;
  $('#amigozSaveModel').disabled=true;
  try {
    const version=await coefficientRequest('amigoz_save_model',{p_config:JSON.parse($('#amigozModelJSON').value)});
    if(epoch===authEpoch) $('#amigozModelStatus').textContent='Versão '+version+' salva.';
  } catch(error) {if(epoch===authEpoch) $('#amigozModelStatus').textContent=error.message;}
  finally {if(epoch===authEpoch) $('#amigozSaveModel').disabled=false;}
};

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
