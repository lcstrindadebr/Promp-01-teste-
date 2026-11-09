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
        $('#crmHistoryRows').replaceChildren();
        $('#crmHistoryTitle').textContent = 'Histórico · ' + (client.nome || formatCpf(client.cpf));
        $('#crmHistory').hidden = false;
        $('#crmClose').focus();
        loadCrmHistory();
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
  $('#crmMoreHistory').hidden = true;
  $('#crmHistoryRows').replaceChildren();
  if (restoreFocus) crmHistoryTrigger?.focus();
  crmClient = crmHistoryTrigger = null;
}

function syncCrmPage(page) {
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
