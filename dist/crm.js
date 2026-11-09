const crmPageSize = 25;
const crmMoney = new Intl.NumberFormat('pt-BR', {style:'currency', currency:'BRL'});
let crmPage = 0;
let crmQuery = '';
let crmListRequest = 0;
let crmHistoryRequest = 0;
let crmHistoryOffset = 0;
let crmClient = null;
let crmHistoryTrigger = null;

function crmRow(cells) {
  const row = document.createElement('tr');
  for (const value of cells) {
    const cell = row.insertCell();
    if (value instanceof HTMLElement) cell.append(value);
    else cell.textContent = value ?? '—';
  }
  return row;
}

function crmPath(view, params) {
  return '/rest/v1/' + view + '?' + new URLSearchParams(params);
}

async function loadCrmClients(page) {
  const request = ++crmListRequest;
  const params = {order:'ultima_atividade.desc,cpf.asc',limit:crmPageSize+1,offset:page*crmPageSize};
  const digitsOnly = crmQuery.replace(/\D/g, '');
  if (digitsOnly && /^[0-9.\s-]+$/.test(crmQuery)) params.cpf = 'ilike.*' + digitsOnly + '*';
  else if (crmQuery) params.nome = 'ilike.*' + crmQuery.replace(/[%_*\\]/g, '') + '*';
  $('#crmStatus').textContent = 'Carregando clientes…';
  $('#crmRows').replaceChildren();
  $('#crmPrevious').disabled = $('#crmNext').disabled = true;
  try {
    const clients = await sbRequest(crmPath('crm_clientes', params));
    if (request !== crmListRequest) return;
    crmPage = page;
    for (const client of clients.slice(0, crmPageSize)) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = 'Ver histórico';
      button.setAttribute('aria-label', 'Ver histórico de ' + (client.nome || formatCpf(client.cpf)));
      button.onclick = () => {
        crmClient = client;
        crmHistoryTrigger = button;
        crmHistoryOffset = 0;
        $('#crmOpportunityForm').reset();
        $('#crmOpportunityAgreement').replaceChildren(new Option('Sem convênio identificado', ''));
        $('#crmOpportunityStatus').textContent = '';
        $('#crmCreateOpportunity').disabled = false;
        $('#crmHistoryRows').replaceChildren();
        $('#crmHistoryTitle').textContent = 'Histórico · ' + (client.nome || formatCpf(client.cpf));
        $('#crmHistory').hidden = false;
        $('#crmClose').focus();
        loadCrmHistory();
        loadCrmLinks(client);
      };
      $('#crmRows').append(crmRow([client.nome, formatCpf(client.cpf), client.telefone, button]));
    }
    $('#crmStatus').textContent = clients.length ? 'Página ' + (page + 1) : 'Nenhum cliente encontrado.';
    $('#crmPrevious').disabled = page === 0;
    $('#crmNext').disabled = clients.length <= crmPageSize;
  } catch {
    if (request === crmListRequest) $('#crmStatus').textContent = 'Não foi possível carregar os clientes. Tente buscar novamente.';
  }
}

async function loadCrmLinks(client) {
  const list = $('#crmLinks');
  const status = $('#crmLinksStatus');
  list.replaceChildren();
  status.textContent = 'Carregando vínculos…';
  try {
    const links = await sbRequest(crmPath('crm_vinculos', {
      cpf:'eq.' + client.cpf, user_id:'eq.' + client.user_id,
      order:'confirmado_em.desc,convenio.asc,matricula.asc', limit:100
    }));
    if (crmClient !== client) return;
    for (const link of links) {
      const label = link.uf + ' · ' + link.convenio.toUpperCase();
      const item = document.createElement('li');
      item.textContent = [label, 'Matrícula ' + link.matricula, link.situacao_atual,
        'ConsigX', new Date(link.confirmado_em).toLocaleDateString('pt-BR')].filter(Boolean).join(' · ');
      list.append(item);
      const agreements = $('#crmOpportunityAgreement');
      if (!Array.from(agreements.options).some(option => option.value === link.convenio)) {
        agreements.add(new Option(label, link.convenio));
      }
    }
    status.textContent = links.length ? '' : 'Nenhum vínculo confirmado.';
  } catch {
    if (crmClient === client) status.textContent = 'Não foi possível carregar os vínculos.';
  }
}

async function loadCrmHistory() {
  const request = ++crmHistoryRequest;
  const params = {cpf:'eq.'+crmClient.cpf,user_id:'eq.'+crmClient.user_id,
    order:'created_at.desc,id.desc',limit:crmPageSize+1,offset:crmHistoryOffset};
  const more = $('#crmMoreHistory');
  more.disabled = true;
  $('#crmHistoryStatus').textContent = 'Carregando consultas…';
  try {
    const rows = await sbRequest(crmPath('crm_consultas', params));
    if (request !== crmHistoryRequest) return;
    const money = value => value == null ? null : crmMoney.format(value);
    for (const row of rows.slice(0, crmPageSize)) {
      const agreements = $('#crmOpportunityAgreement');
      if (row.convenio && !Array.from(agreements.options).some(option => option.value === row.convenio)) {
        agreements.add(new Option(row.convenio.toUpperCase(), row.convenio));
      }
      const service = row.convenio ? 'ConsigX · ' + row.convenio.toUpperCase() : 'Digi+';
      $('#crmHistoryRows').append(crmRow([service, statusNames[row.status] || row.status,
        row.matricula, row.situacao_atual, money(row.emprestimo_disponivel),
        money(row.cartao_disponivel), money(row.saldo_liquidacao), money(row.valor_parcela),
        new Date(row.consultado_em || row.created_at).toLocaleString('pt-BR')]));
    }
    crmHistoryOffset += Math.min(crmPageSize, rows.length);
    more.hidden = rows.length <= crmPageSize;
    $('#crmHistoryStatus').textContent = crmHistoryOffset + ' consulta(s) exibida(s).';
  } catch {
    if (request !== crmHistoryRequest) return;
    more.hidden = false;
    $('#crmHistoryStatus').textContent = 'Não foi possível carregar o histórico. Tente novamente.';
  } finally {
    if (request === crmHistoryRequest) more.disabled = false;
  }
}

function closeCrmHistory(restoreFocus = false) {
  crmHistoryRequest++;
  $('#crmHistory').hidden = true;
  $('#crmLinks').replaceChildren();
  $('#crmMoreHistory').hidden = true;
  $('#crmHistoryRows').replaceChildren();
  if (restoreFocus) crmHistoryTrigger?.focus();
  crmClient = crmHistoryTrigger = null;
}

function syncCrmPage(page) {
  crmPipelineRequest++;
  $('#crmPipelineRows').replaceChildren();
  if (page === 'opportunities') loadCrmPipeline(0);
  if (!authenticated) $('#crmStageFilter').value = '';
  if (page === 'clients') {
    loadCrmClients(crmPage);
    return;
  }
  crmListRequest++;
  closeCrmHistory();
  $('#crmRows').replaceChildren();
  if (!authenticated) {
    crmQuery = $('#crmQuery').value = '';
    crmPage = 0;
  }
}

$('#crmSearch').onsubmit = event => {
  event.preventDefault();
  closeCrmHistory();
  crmQuery = $('#crmQuery').value.trim();
  loadCrmClients(0);
};
$('#crmPrevious').onclick = () => { closeCrmHistory(); loadCrmClients(crmPage - 1); };
$('#crmNext').onclick = () => { closeCrmHistory(); loadCrmClients(crmPage + 1); };
$('#crmClose').onclick = () => closeCrmHistory(true);
$('#crmMoreHistory').onclick = loadCrmHistory;

const crmStages = {
  novo:'Novo', contato:'Em contato', simulacao:'Simulação enviada',
  negociacao:'Em negociação', ganho:'Ganho', perdido:'Perdido'
};
const crmProducts = {margem:'Margem',saque:'Saque complementar',recompra:'Compra de dívida'};
let crmPipelineRequest = 0;
let crmPipelinePage = 0;

function crmStageOptions(select, value, includeAll = false) {
  if (includeAll) select.add(new Option('Todas', ''));
  for (const [key,label] of Object.entries(crmStages)) select.add(new Option(label, key));
  select.value = value;
}

async function loadCrmPipeline(page) {
  const request = ++crmPipelineRequest;
  const params = {order:'created_at.desc,id.desc',limit:crmPageSize+1,offset:page*crmPageSize};
  const stageFilter = $('#crmStageFilter').value;
  if (stageFilter) params.etapa = 'eq.' + stageFilter;
  const status = $('#crmPipelineStatus');
  const table = $('#crmPipelineRows');
  table.replaceChildren();
  $('#crmPipelinePrevious').disabled = $('#crmPipelineNext').disabled = true;
  status.textContent = 'Carregando oportunidades…';
  try {
    const rows = await sbRequest(crmPath('crm_oportunidades', params));
    if (request !== crmPipelineRequest) return;
    crmPipelinePage = page;
    for (const row of rows.slice(0, crmPageSize)) {
      const identity = (row.nome || formatCpf(row.cpf)) + (row.convenio ? ' · ' + row.convenio.toUpperCase() : '');
      const stage = document.createElement('select');
      crmStageOptions(stage, row.etapa);
      stage.setAttribute('aria-label','Etapa de ' + identity);
      const action = document.createElement('input');
      action.maxLength = 500;
      action.value = row.proxima_acao || '';
      action.setAttribute('aria-label','Próxima ação de ' + identity);
      const save = document.createElement('button');
      save.type = 'button';
      save.textContent = 'Salvar';
      save.onclick = async () => {
        save.disabled = true;
        try {
          const updated = await sbRequest(crmPath('crm_oportunidades', {id:'eq.' + row.id}), {
            method:'PATCH', headers:{Prefer:'return=representation'},
            body:JSON.stringify({etapa:stage.value,proxima_acao:action.value.trim() || null})
          });
          if (request !== crmPipelineRequest) return;
          if (!updated?.length) throw Error();
          if (stageFilter && stage.value !== stageFilter) loadCrmPipeline(0);
          else status.textContent = 'Oportunidade atualizada.';
        } catch {
          if (request === crmPipelineRequest) status.textContent = 'Não foi possível atualizar a oportunidade.';
        } finally {
          save.disabled = false;
        }
      };
      table.append(crmRow([identity,crmProducts[row.produto],stage,action,save]));
    }
    status.textContent = rows.length ? 'Página ' + (page+1) : 'Nenhuma oportunidade nesta etapa.';
    $('#crmPipelinePrevious').disabled = page === 0;
    $('#crmPipelineNext').disabled = rows.length <= crmPageSize;
  } catch {
    if (request === crmPipelineRequest) status.textContent = 'Não foi possível carregar as oportunidades.';
  }
}

crmStageOptions($('#crmStageFilter'), '', true);
$('#crmStageFilter').onchange = () => loadCrmPipeline(0);
$('#crmPipelinePrevious').onclick = () => loadCrmPipeline(crmPipelinePage-1);
$('#crmPipelineNext').onclick = () => loadCrmPipeline(crmPipelinePage+1);
$('#crmOpportunityForm').onsubmit = async event => {
  event.preventDefault();
  if (!crmClient) return;
  const client = crmClient;
  const button = $('#crmCreateOpportunity');
  const status = $('#crmOpportunityStatus');
  button.disabled = true;
  status.textContent = 'Criando oportunidade…';
  try {
    await sbRequest('/rest/v1/crm_oportunidades', {
      method:'POST', headers:{Prefer:'return=minimal'},
      body:JSON.stringify({cpf:client.cpf,nome:client.nome,produto:$('#crmProduct').value,
        convenio:$('#crmOpportunityAgreement').value})
    });
    if (crmClient === client) status.textContent = 'Oportunidade criada. Veja na aba Oportunidades.';
  } catch (error) {
    if (crmClient === client) status.textContent = error.status === 409
      ? 'Já existe uma oportunidade aberta para este produto e vínculo.'
      : 'Não foi possível criar a oportunidade.';
  } finally {
    if (crmClient === client) button.disabled = false;
  }
};
