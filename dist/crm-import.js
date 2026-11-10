const crmStates = {
  AC:'Acre', AL:'Alagoas', AP:'Amapá', AM:'Amazonas', BA:'Bahia', CE:'Ceará',
  DF:'Distrito Federal', ES:'Espírito Santo', GO:'Goiás', MA:'Maranhão',
  MT:'Mato Grosso', MS:'Mato Grosso do Sul', MG:'Minas Gerais', PA:'Pará',
  PB:'Paraíba', PR:'Paraná', PE:'Pernambuco', PI:'Piauí', RJ:'Rio de Janeiro',
  RN:'Rio Grande do Norte', RS:'Rio Grande do Sul', RO:'Rondônia', RR:'Roraima',
  SC:'Santa Catarina', SP:'São Paulo', SE:'Sergipe', TO:'Tocantins'
};

async function crmReadClientFile(file, uf, convenio, convenioNome = convenio) {
  if (!/\.(csv|tsv|xlsx|xls)$/i.test(file.name)) throw Error('Envie um arquivo CSV, TSV, XLSX ou XLS.');
  if (file.size > 2_000_000) throw Error('O arquivo deve ter até 2 MB.');
  let rows;
  if (/\.xlsx?$/i.test(file.name)) {
    const book = XLSX.read(await file.arrayBuffer(), {type:'array', sheetRows:10002, cellFormula:false, cellHTML:false});
    const sheet = book.Sheets[book.SheetNames[0]];
    if (!sheet) throw Error('A planilha está vazia.');
    rows = XLSX.utils.sheet_to_json(sheet, {header:1, raw:true, defval:'', blankrows:false});
    const range = sheet['!fullref'] || sheet['!ref'];
    if (range && XLSX.utils.decode_range(range).e.r > 10000) throw Error('Envie até 10.000 clientes por arquivo.');
  } else {
    const data = (await file.text()).replace(/^\uFEFF/,'').replace(/^sep=[;,]\r?\n/i,'');
    if (data.includes('\uFFFD')) throw Error('Salve o CSV com codificação UTF-8.');
    rows = csvParse(data);
  }
  if (rows.length < 2 || rows.length > 10001) throw Error('O arquivo deve ter um cabeçalho e entre 1 e 10.000 clientes.');
  const headers = rows.shift().map(value => importHeader(String(value)));
  if (!headers.includes('cpf') || new Set(headers).size !== headers.length) throw Error('Inclua uma coluna CPF e use cabeçalhos únicos.');
  const normalize = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
  const seen = new Set();
  return rows.map((row, index) => {
    const entry = Object.fromEntries(headers.map((key, i) => [key, String(row[i] ?? '').trim()]));
    const invalid = message => { throw Error('Registro ' + (index + 1) + ': ' + message); };
    for (const state of [entry.uf, entry.estado].filter(Boolean)) {
      if (![normalize(uf),normalize(crmStates[uf])].includes(normalize(state))) invalid('estado diferente do selecionado.');
    }
    for (const agreement of [entry.convenio, entry['orgao convenio']].filter(Boolean)) {
      if (![normalize(convenio),normalize(convenioNome)].includes(normalize(agreement))) invalid('convênio diferente do selecionado.');
    }
    const rawCpf = entry.cpf;
    const cpf = typeof row[headers.indexOf('cpf')] === 'number' && /^\d{1,11}$/.test(rawCpf)
      ? rawCpf.padStart(11,'0') : rawCpf.replace(/[.\-]/g,'');
    const telefone = (entry.telefone || '').replace(/[()\s+.-]/g,'');
    if (!/^\d{11}$/.test(cpf) || cpf === '00000000000') invalid('CPF inválido. Use 11 dígitos.');
    if (seen.has(cpf)) invalid('CPF repetido na planilha.');
    if ((entry.nome || '').length > 160 || (telefone && !/^\d{10,13}$/.test(telefone))) invalid('nome ou telefone inválido.');
    seen.add(cpf);
    return {cpf, nome:entry.nome || null, telefone:telefone || null};
  });
}

const crmPlannedServices = {
  consigx_margem:'Margem · ConsigX',
  amigoz_margem:'Margem · Amigoz',
  amigoz_saque:'Saque complementar · Amigoz',
  digimais_saldo:'Saldo e parcela · Digi+'
};

async function crmOpenClientImport() {
  const epoch = authEpoch;
  const {dialog, form} = crmDialog('Importar base de clientes');
  dialog.classList.add('crm-import-dialog');
  const heading = dialog.querySelector('h2');
  heading.id = 'crmImportTitle';
  dialog.setAttribute('aria-labelledby', heading.id);
  form.innerHTML = `
    <p class="crm-import-intro">Escolha o convênio e marque as consultas que pretende fazer depois. A importação apenas cadastra a base.</p>
    <ol class="crm-import-steps" aria-label="Etapas da importação">
      <li>Estado</li><li>Convênio</li><li>Consultas e planilha</li>
    </ol>
    <div class="crm-import-fields">
      <label>Estado<select name="uf" required><option value="">Selecione o estado</option></select></label>
      <label hidden>Convênio<select name="convenio" required disabled></select></label>
      <fieldset class="crm-import-services" hidden>
        <legend>Consultas previstas</legend>
        <small>Marque uma ou mais opções ou deixe todas desmarcadas.</small>
        <div data-services></div>
      </fieldset>
      <div class="crm-import-file" hidden>
        <label>Planilha de clientes<input name="arquivo" type="file" accept=".csv,.tsv,.xlsx,.xls" required disabled></label>
        <small>CPF obrigatório. Nome e telefone são opcionais. Até 2 MB e 10.000 clientes.</small>
        <a href="modelo-clientes.csv" download>Baixar modelo de cadastro</a>
      </div>
    </div>
    <p role="status" class="crm-import-status"></p>
    <footer><button type="button" data-cancel>Cancelar</button><button type="submit" class="primary" disabled>Importar clientes</button></footer>`;
  const uf = form.elements.uf, convenio = form.elements.convenio;
  const serviceGroup = form.querySelector('fieldset');
  const serviceList = form.querySelector('[data-services]');
  const file = form.elements.arquivo, submit = form.querySelector('[type=submit]');
  const status = form.querySelector('[role=status]'), steps = form.querySelectorAll('li');
  let rows = [], generation = 0, saving = false;
  const cancel = form.querySelector('[data-cancel]');
  const close = dialog.querySelector('header button');
  cancel.onclick = () => dialog.close();
  let catalog = [];
  uf.disabled = true;
  status.textContent = 'Carregando convênios cadastrados…';
  try {
    catalog = await crmGetImportCatalog();
    if (!dialog.open || authEpoch !== epoch) return;
    const states = [...new Set(catalog.map(row => row.uf))];
    states.sort((a,b) => (crmStates[a] || a).localeCompare(crmStates[b] || b,'pt-BR'));
    for (const code of states) uf.add(new Option((crmStates[code] || code) + ' (' + code + ')', code));
    uf.disabled = false;
    status.textContent = '';
  } catch {
    status.textContent = 'Não foi possível carregar os convênios. Feche e tente novamente.';
    return;
  }
  const selectedAgreement = () => catalog.find(row => row.uf === uf.value && row.codigo === convenio.value);
  function refresh() {
    convenio.disabled = saving || !uf.value;
    convenio.parentElement.hidden = !uf.value;
    serviceGroup.disabled = saving;
    serviceGroup.hidden = !selectedAgreement();
    file.disabled = saving || !selectedAgreement();
    file.closest('.crm-import-file').hidden = !selectedAgreement();
    submit.disabled = saving || file.disabled || !rows.length;
    const step = !uf.value ? 0 : !convenio.value.trim() ? 1 : 2;
    steps.forEach((item, index) => {
      if (index === step) item.setAttribute('aria-current','step');
      else item.removeAttribute('aria-current');
    });
  }
  function resetFile() {
    generation++;
    file.value = '';
    rows = [];
    status.textContent = '';
    refresh();
  }
  uf.onchange = () => {
    convenio.replaceChildren(new Option('Selecione o convênio',''));
    for (const row of catalog.filter(row => row.uf === uf.value)) {
      convenio.add(new Option(row.nome,row.codigo));
    }
    serviceList.replaceChildren();
    resetFile();
  };
  convenio.onchange = () => {
    serviceList.replaceChildren();
    for (const service of selectedAgreement()?.servicos || []) {
      const label = document.createElement('label');
      const checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      checkbox.value = service;
      label.append(checkbox, crmPlannedServices[service] || service);
      serviceList.append(label);
    }
    resetFile();
  };
  file.onchange = async () => {
    const request = ++generation;
    rows = [];
    refresh();
    if (!file.files.length) { status.textContent = ''; return; }
    status.textContent = 'Validando a planilha…';
    try {
      const parsed = await crmReadClientFile(file.files[0], uf.value, convenio.value, selectedAgreement().nome);
      if (request !== generation) return;
      rows = parsed;
      status.textContent = rows.length.toLocaleString('pt-BR') + ' clientes prontos para cadastrar.';
    } catch (error) {
      if (request === generation) status.textContent = error.message;
    } finally {
      if (request === generation) refresh();
    }
  };
  dialog.addEventListener('cancel', event => { if (saving) event.preventDefault(); });
  form.onsubmit = async event => {
    event.preventDefault();
    if (saving || !rows.length || !authenticated || authEpoch !== epoch) return;
    saving = uf.disabled = cancel.disabled = close.disabled = true;
    refresh();
    status.textContent = 'Salvando cadastros…';
    try {
      const count = await crmRpc('crm_import_catalog_clients', {
        p_uf:uf.value, p_convenio:convenio.value, p_rows:rows,
        p_servicos:[...serviceList.querySelectorAll('input:checked')].map(input => input.value)
      });
      if (authEpoch !== epoch) return;
      dialog.close();
      closeCrmHistory();
      $('#crmSearch').reset();
      crmFilters = {p_query:'',p_uf:'',p_convenio:'',p_servico:''};
      crmCursors = [''];
      await Promise.all([loadCrmClients(0),loadCrmFilterOptions()]);
      if (currentPage === 'clients' && authEpoch === epoch) toast(count + ' clientes cadastrados ou atualizados.');
    } catch (error) {
      if (authEpoch === epoch) status.textContent = error.message || 'Não foi possível importar a base.';
    } finally {
      saving = uf.disabled = cancel.disabled = close.disabled = false;
      refresh();
    }
  };
  refresh();
  uf.focus();
}

let crmImportCatalog;
async function crmGetImportCatalog() {
  if (!crmImportCatalog) {
    crmImportCatalog = await sbRequest(crmPath('crm_catalogo_importacao', {order:'nome.asc'}));
  }
  return crmImportCatalog;
}

$('#crmImportClients').onclick = crmOpenClientImport;

function crmAddPlannedActions(item, client, agreement, planned) {
  const buttons = crmElement('div','crm-planned-actions');
  const add = (label, handler) => {
    const button = crmElement('button','',label);
    button.type = 'button';
    button.onclick = handler;
    buttons.append(button);
  };
  const canOpen = service => currentAccess?.active && !currentAccess.trial_expired &&
    (currentAccess.role === 'admin' || accessRule(service)?.allow_individual && accessRule(service)?.enabled);
  const amigozMargin = planned.includes('amigoz_margem');
  const amigozSaque = planned.includes('amigoz_saque');
  if ((amigozMargin || amigozSaque) && amigozCanConsult()) {
    add('Preparar consulta Amigoz', async () => {
      const epoch = authEpoch;
      navigate('home');
      await amigozPicker.onchange({target:{value:'amigoz'}});
      if (epoch !== authEpoch || currentPage !== 'home' || !amigozCanConsult()) return;
      $('#amigozState').value = agreement.uf;
      $('#amigozState').onchange();
      $('#amigozConvenio').value = agreement.codigo.slice('amigoz_'.length);
      $('#amigozMode').value = amigozMargin && amigozSaque ? 'ambos' : amigozMargin ? 'margem' : 'saque';
      $('#amigozConvenio').onchange();
      $('#amigozConsultCpf').value = formatCpf(client.cpf);
      $('#amigozConsultCpf').focus();
    });
  }
  const prepareStandard = (service, label) => {
    if (!canOpen(service)) return;
    add(label, () => {
      navigate('home');
      amigozPicker.onchange({target:{value:service}});
      if (service === 'tjba_margem') {
        $('#convenioSelect').value = agreement.codigo;
        $('#convenioSelect').onchange();
      }
      $('#nome').value = client.nome || '';
      $('#cpf').value = formatCpf(client.cpf);
      $('#telefone').value = client.telefone || '';
      $('#cpf').focus();
    });
  };
  if (planned.includes('consigx_margem')) prepareStandard('tjba_margem','Preparar margem ConsigX');
  if (planned.includes('digimais_saldo')) prepareStandard('digimais_saldo_parcela','Preparar saldo Digi+');
  if (buttons.children.length) item.append(buttons);
}
