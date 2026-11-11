const crmStates = {
  AC:'Acre', AL:'Alagoas', AP:'Amapá', AM:'Amazonas', BA:'Bahia', CE:'Ceará',
  DF:'Distrito Federal', ES:'Espírito Santo', GO:'Goiás', MA:'Maranhão',
  MT:'Mato Grosso', MS:'Mato Grosso do Sul', MG:'Minas Gerais', PA:'Pará',
  PB:'Paraíba', PR:'Paraná', PE:'Pernambuco', PI:'Piauí', RJ:'Rio de Janeiro',
  RN:'Rio Grande do Norte', RS:'Rio Grande do Sul', RO:'Rondônia', RR:'Roraima',
  SC:'Santa Catarina', SP:'São Paulo', SE:'Sergipe', TO:'Tocantins'
};

async function crmReadClientFile(file, uf, convenio, convenioNome = convenio, services = null) {
  if (!/\.(csv|tsv|xlsx|xls)$/i.test(file.name)) throw Error('Envie um arquivo CSV, TSV, XLSX ou XLS.');
  if (file.size > 2_000_000) throw Error('O arquivo deve ter até 2 MB.');
  let rows, date1904 = false;
  if (/\.xlsx?$/i.test(file.name)) {
    const book = XLSX.read(await file.arrayBuffer(), {type:'array', sheetRows:10002, cellFormula:false, cellHTML:false});
    date1904 = Boolean(book.Workbook?.WBProps?.date1904);
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
    const birth = entry['data nascimento'] || entry['data de nascimento'] || entry['data nasc'] || entry.nascimento;
    let dataNascimento;
    if (birth) {
      const br = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(birth);
      dataNascimento = br ? br[3]+'-'+br[2]+'-'+br[1] : birth;
      const birthColumn = headers.findIndex(key => ['data nascimento','data de nascimento','data nasc','nascimento'].includes(key));
      if (typeof row[birthColumn] === 'number' && /\.xlsx?$/i.test(file.name)) {
        const parsed = XLSX.SSF.parse_date_code(row[birthColumn], {date1904});
        if (!parsed) invalid('data de nascimento inválida.');
        dataNascimento = [String(parsed.y).padStart(4,'0'),String(parsed.m).padStart(2,'0'),String(parsed.d).padStart(2,'0')].join('-');
      }
      const date = new Date(dataNascimento+'T00:00:00Z');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(dataNascimento) || !Number.isFinite(date.getTime()) ||
          date.toISOString().slice(0,10) !== dataNascimento) invalid('data de nascimento inválida.');
    }
    const amount = (value, label) => {
      if (!value) return null;
      const raw = value.replace(/^R\$\s*/i,'').trim();
      const normalized = /^-?(?:\d{1,3}(?:\.\d{3})+|\d+),\d{1,2}$/.test(raw) ? raw.replace(/\./g,'').replace(',','.') : raw;
      if (!/^-?\d{1,12}(?:\.\d{1,2})?$/.test(normalized)) invalid(label+' inválido.');
      return Number(normalized);
    };
    const margemLivre = amount(entry['margem livre'],'Margem livre');
    const margemEmprestimo = amount(entry['margem emprestimo'],'Margem de empréstimo');
    const margemCartao = amount(entry['margem cartao'],'Margem de cartão');
    const saqueValor = amount(entry['saque amigoz valor'] || entry['valor saque complementar amigoz'],'Valor do saque Amigoz');
    const eligibility = normalize(entry['saque amigoz elegivel'] || entry['saque complementar amigoz']);
    let saqueElegivel = null;
    if (eligibility) {
      if (['sim','true','1'].includes(eligibility)) saqueElegivel = true;
      else if (['nao','false','0'].includes(eligibility)) saqueElegivel = false;
      else invalid('Elegibilidade de saque Amigoz deve ser Sim ou Não.');
    }
    if (saqueValor < 0 || (saqueElegivel === false && saqueValor > 0)) invalid('Dados de saque Amigoz incompatíveis.');
    if (services && [margemLivre,margemEmprestimo,margemCartao].some(value=>value !== null)
        && !services.some(service=>service.endsWith('_margem'))) invalid('Margem indisponível neste convênio.');
    if (services && (saqueElegivel !== null || saqueValor !== null)
        && !services.includes('amigoz_saque')) invalid('Saque Amigoz indisponível neste convênio.');
    seen.add(cpf);
    return {cpf, nome:entry.nome || null, telefone:telefone || null,
      ...(margemLivre !== null ? {margem_livre:margemLivre} : {}),
      ...(margemEmprestimo !== null ? {margem_emprestimo:margemEmprestimo} : {}),
      ...(margemCartao !== null ? {margem_cartao:margemCartao} : {}),
      ...(saqueElegivel !== null ? {saque_amigoz_elegivel:saqueElegivel} : {}),
      ...(saqueValor !== null ? {saque_amigoz_valor:saqueValor} : {}),
      ...(dataNascimento ? {data_nascimento:dataNascimento} : {}),
      ...((entry.matricula || entry.numero_matricula || entry['numero matricula']) ? {numero_matricula:entry.matricula || entry.numero_matricula || entry['numero matricula']} : {})};
  });
}

function crmAgreementTemplate(agreement,example) {
  const services = agreement.servicos;
  const fields = ['cpf','nome','telefone','matricula','data_nascimento'];
  const values = {cpf:'000.000.008-92',nome:'Cliente de exemplo',telefone:agreement.uf==='BA'?'75900000000':'11900000000',
    matricula:'000123',data_nascimento:'1980-05-20',uf:agreement.uf,convenio:agreement.codigo,
    margem_emprestimo:180.50,margem_cartao:65.20,saque_amigoz_elegivel:'Sim',saque_amigoz_valor:250};
  if (services.some(service=>service.endsWith('_margem'))) fields.push('margem_emprestimo','margem_cartao');
  if (services.includes('amigoz_saque')) fields.push('saque_amigoz_elegivel','saque_amigoz_valor');
  fields.push('uf','convenio');
  return example ? [fields,fields.map(field=>values[field])] : [fields];
}

function crmWriteAgreementTemplate(agreement,example) {
  const book=crmAgreementWorkbook(agreement,crmAgreementTemplate(agreement,example),example);
  XLSX.writeFile(book,(example?'exemplo-':'modelo-')+agreement.uf.toLowerCase()+'-'+agreement.codigo+'.xlsx',{compression:true});
}

function crmAgreementWorkbook(agreement,data,example=false) {
  const book=XLSX.utils.book_new();
  const sheet=XLSX.utils.aoa_to_sheet(data);
  sheet['!cols']=data[0].map(field=>({wch:Math.max(18,field.length+3)}));
  XLSX.utils.book_append_sheet(book,sheet,'Clientes');
  const instructions=[
    ['Convênio',agreement.nome],['UF',agreement.uf],['ID',agreement.codigo],
    ['Serviços',agreement.servicos.map(service=>crmPlannedServices[service]||service).join(', ')],
    ['Preenchimento','CPF é obrigatório. Preserve o cabeçalho e deixe valores desconhecidos em branco.'],
    ['Digi+',agreement.servicos.includes('digimais_saldo')?'Nome e telefone com DDD são obrigatórios ao solicitar consulta Digi+.':'Consulta indisponível neste convênio.'],
    ['Identificadores','CPF, telefone e matrícula em texto. Data de nascimento em AAAA-MM-DD ou DD/MM/AAAA.'],
    ...(data[0].includes('margem_emprestimo')?[['Margens','Informe os valores em reais nas colunas de empréstimo e cartão. Use 0 para margem zerada.']]:[]),
    ...(data[0].includes('saque_amigoz_elegivel')?[['Saque Amigoz','Informe Sim ou Não na elegibilidade e o valor disponível em reais.']]:[]),
    ...(example?[['Exemplo','Os dados são fictícios. Remova a linha de exemplo antes de importar a sua base.']]:[])
  ];
  const guide=XLSX.utils.aoa_to_sheet(instructions);
  guide['!cols']=[{wch:20},{wch:100}];
  XLSX.utils.book_append_sheet(book,guide,'Como preencher');
  return book;
}

const crmPlannedServices = {
  consigx_margem:'Margens de empréstimo e cartão · ConsigX',
  amigoz_margem:'Margem de cartão · Amigoz',
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
    <p class="crm-import-intro">Escolha o convênio e marque as consultas para iniciar automaticamente após importar. Sem opções marcadas, a planilha atualiza o cadastro sem iniciar consultas.</p>
    <ol class="crm-import-steps" aria-label="Etapas da importação">
      <li>Estado</li><li>Convênio</li><li>Consultas e planilha</li>
    </ol>
    <div class="crm-import-fields">
      <label>Estado<select name="uf" required><option value="">Selecione o estado</option></select></label>
      <label hidden>Convênio<select name="convenio" required disabled></select></label>
      <fieldset class="crm-import-services" hidden>
        <legend>Consultas automáticas</legend>
        <small>As consultas selecionadas entram na fila da VPS, mesmo se você fechar esta página.</small>
        <div data-services></div>
      </fieldset>
      <div class="crm-import-file" hidden>
        <label>Planilha de clientes<input name="arquivo" type="file" accept=".csv,.tsv,.xlsx,.xls" required disabled></label>
        <small>CPF obrigatório. O modelo do convênio indica os campos disponíveis. Até 2 MB e 10.000 clientes.</small>
        <p data-agreement-info></p>
        <div class="crm-import-downloads">
          <button type="button" data-model>Baixar modelo Excel</button>
          <button type="button" data-example>Baixar exemplo preenchido</button>
        </div>
      </div>
    </div>
    <p role="status" class="crm-import-status"></p>
    <footer><button type="button" data-cancel>Cancelar</button><button type="submit" class="primary" disabled>Importar clientes</button></footer>`;
  const uf = form.elements.uf, convenio = form.elements.convenio;
  const serviceGroup = form.querySelector('fieldset');
  const serviceList = form.querySelector('[data-services]');
  const file = form.elements.arquivo, submit = form.querySelector('[type=submit]');
  const status = form.querySelector('[role=status]'), steps = form.querySelectorAll('.crm-import-steps li');
  let rows = [], generation = 0, saving = false, requestId = crypto.randomUUID();
  let submitted = null;
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
    const directory = document.createElement('details');
    directory.className = 'crm-import-directory';
    const summary = document.createElement('summary');
    summary.textContent = 'Lista de convênios e IDs';directory.append(summary);
    const list = document.createElement('ul');
    for (const item of catalog) {
      const line = document.createElement('li');
      line.textContent = item.uf+' · '+item.nome+' · ID '+item.codigo+' · '+item.servicos.map(service=>crmPlannedServices[service]||service).join(', ');
      list.append(line);
    }
    directory.append(list);form.querySelector('.crm-import-fields').after(directory);
    status.textContent = '';
  } catch {
    status.textContent = 'Não foi possível carregar os convênios. Feche e tente novamente.';
    return;
  }
  const selectedAgreement = () => catalog.find(row => row.uf === uf.value && row.codigo === convenio.value);
  const agreementInfo = form.querySelector('[data-agreement-info]');
  const downloadModel = example => {
    const agreement = selectedAgreement();
    if (!agreement) return;
    try { crmWriteAgreementTemplate(agreement,example); }
    catch { status.textContent = 'Não foi possível gerar a planilha. Tente novamente.'; }
  };
  form.querySelector('[data-model]').onclick = ()=>downloadModel(false);
  form.querySelector('[data-example]').onclick = ()=>downloadModel(true);
  function refresh() {
    const agreement = selectedAgreement();
    agreementInfo.textContent = agreement
      ? 'ID: '+agreement.codigo+' · CPF obrigatório.'+(agreement.servicos.includes('digimais_saldo')?' Para consultar Digi+, informe também nome e telefone com DDD.':'')
      : '';
    convenio.disabled = saving || !uf.value;
    convenio.parentElement.hidden = !uf.value;
    serviceGroup.disabled = saving;
    serviceGroup.hidden = !selectedAgreement();
    file.disabled = saving || !selectedAgreement();
    file.closest('.crm-import-file').hidden = !selectedAgreement();
    const selected = [...serviceList.querySelectorAll('input:checked')].map(input => input.value);
    submit.disabled = saving || file.disabled || !rows.length;
    submit.textContent = selected.length ? 'Importar e iniciar consultas' : 'Importar clientes';
    const step = !uf.value ? 0 : !convenio.value.trim() ? 1 : 2;
    steps.forEach((item,index)=>{
      if(index===step) item.setAttribute('aria-current','step');
      else item.removeAttribute('aria-current');
    });
  }
  function resetFile() {
    generation++;
    requestId = crypto.randomUUID(); submitted = null;
    file.value = '';
    rows = [];
    status.textContent = '';
    refresh();
  }
  uf.onchange = () => {
    convenio.replaceChildren(new Option('Selecione o convênio',''));
    for (const row of catalog.filter(row => row.uf === uf.value)) {
      const option=new Option(row.nome+' · '+row.codigo,row.codigo);
      option.title=row.servicos.map(service=>crmPlannedServices[service]||service).join(', ');
      convenio.add(option);
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
      const rule = service === 'consigx_margem' ? accessRule('tjba_margem') : accessRule('digimais_saldo_parcela');
      const allowed = currentAccess?.role === 'admin' || (service.startsWith('amigoz_') ? amigozCanConsult() : rule?.enabled && rule?.allow_campaign);
      checkbox.disabled = !allowed;
      if (checkbox.disabled) label.title = 'Sem permissão para consultar em lote.';
      checkbox.onchange = refresh;
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
      const agreement = selectedAgreement();
      const parsed = await crmReadClientFile(file.files[0], agreement.uf, agreement.codigo, agreement.nome, agreement.servicos);
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
    status.textContent = 'Salvando clientes e agendando consultas…';
    try {
      const selected = [...serviceList.querySelectorAll('input:checked')].map(input => input.value);
      if (selected.includes('digimais_saldo') && rows.some(row => !row.nome || !row.telefone)) throw Error('Digi+ exige nome e telefone com DDD em todas as linhas.');
      const payload = {p_uf:uf.value,p_convenio:convenio.value,p_rows:rows,p_servicos:selected};
      const fingerprint = JSON.stringify(payload);
      if (submitted && submitted !== fingerprint) requestId = crypto.randomUUID();
      submitted = fingerprint;
      const result = await crmRpc('crm_import_and_start', {...payload,p_request_id:requestId});
      if (authEpoch !== epoch) return;
      dialog.close();
      closeCrmHistory();
      $('#crmSearch').reset();
      crmFilters = {p_query:'',p_uf:'',p_convenio:'',p_servico:''};
      crmCursors = [''];
      await Promise.all([loadCrmClients(0),loadCrmFilterOptions()]);
      if (currentPage === 'clients' && authEpoch === epoch) toast(result.clientes + ' clientes cadastrados. ' + (result.consultas ? result.consultas + ' consultas na fila. Acompanhe em Ver histórico.' : 'Nenhuma consulta selecionada.'));
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
