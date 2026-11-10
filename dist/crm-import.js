const crmStates = {
  AC:'Acre', AL:'Alagoas', AP:'Amapá', AM:'Amazonas', BA:'Bahia', CE:'Ceará',
  DF:'Distrito Federal', ES:'Espírito Santo', GO:'Goiás', MA:'Maranhão',
  MT:'Mato Grosso', MS:'Mato Grosso do Sul', MG:'Minas Gerais', PA:'Pará',
  PB:'Paraíba', PR:'Paraná', PE:'Pernambuco', PI:'Piauí', RJ:'Rio de Janeiro',
  RN:'Rio Grande do Norte', RS:'Rio Grande do Sul', RO:'Rondônia', RR:'Roraima',
  SC:'Santa Catarina', SP:'São Paulo', SE:'Sergipe', TO:'Tocantins'
};

async function crmReadClientFile(file, uf, convenio) {
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
      if (normalize(agreement) !== normalize(convenio)) invalid('convênio diferente do selecionado.');
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

function crmOpenClientImport() {
  const epoch = authEpoch;
  const {dialog, form} = crmDialog('Importar base de clientes');
  dialog.classList.add('crm-import-dialog');
  const heading = dialog.querySelector('h2');
  heading.id = 'crmImportTitle';
  dialog.setAttribute('aria-labelledby', heading.id);
  form.innerHTML = `
    <p class="crm-import-intro">Cadastre os clientes e registre a finalidade da base. As consultas são iniciadas em Consultas.</p>
    <ol class="crm-import-steps" aria-label="Etapas da importação">
      <li>Estado</li><li>Convênio</li><li>Digi+ e planilha</li>
    </ol>
    <div class="crm-import-fields">
      <label>Estado<select name="uf" required><option value="">Selecione o estado</option></select></label>
      <label hidden>Convênio<input name="convenio" maxlength="120" placeholder="Ex.: TJBA" required disabled></label>
      <label hidden>Pretende usar esta base no Digi+?<select name="digimais" required disabled>
        <option value="">Selecione uma opção</option><option value="yes">Sim</option><option value="no">Não</option>
      </select></label>
      <div class="crm-import-file" hidden>
        <label>Planilha de clientes<input name="arquivo" type="file" accept=".csv,.tsv,.xlsx,.xls" required disabled></label>
        <small>CPF obrigatório. Nome e telefone são opcionais. Até 2 MB e 10.000 clientes.</small>
        <a href="modelo-clientes.csv" download>Baixar modelo de cadastro</a>
      </div>
    </div>
    <p role="status" class="crm-import-status"></p>
    <footer><button type="button" data-cancel>Cancelar</button><button type="submit" class="primary" disabled>Importar clientes</button></footer>`;
  const uf = form.elements.uf, convenio = form.elements.convenio, digimais = form.elements.digimais;
  const file = form.elements.arquivo, submit = form.querySelector('[type=submit]');
  const status = form.querySelector('[role=status]'), steps = form.querySelectorAll('li');
  let rows = [], generation = 0, saving = false;
  for (const [code, name] of Object.entries(crmStates).sort((a,b) => a[1].localeCompare(b[1],'pt-BR'))) {
    uf.add(new Option(name + ' (' + code + ')', code));
  }
  function refresh() {
    convenio.disabled = saving || !uf.value;
    convenio.parentElement.hidden = !uf.value;
    digimais.disabled = saving || !uf.value || !convenio.value.trim();
    digimais.parentElement.hidden = !uf.value || !convenio.value.trim();
    file.disabled = saving || digimais.disabled || !digimais.value;
    file.closest('.crm-import-file').hidden = digimais.parentElement.hidden || !digimais.value;
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
  uf.onchange = () => { convenio.value = ''; digimais.value = ''; resetFile(); };
  convenio.oninput = () => { digimais.value = ''; resetFile(); };
  digimais.onchange = resetFile;
  file.onchange = async () => {
    const request = ++generation;
    rows = [];
    refresh();
    if (!file.files.length) { status.textContent = ''; return; }
    status.textContent = 'Validando a planilha…';
    try {
      const parsed = await crmReadClientFile(file.files[0], uf.value, convenio.value.trim());
      if (request !== generation) return;
      rows = parsed;
      status.textContent = rows.length.toLocaleString('pt-BR') + ' clientes prontos para cadastrar.';
    } catch (error) {
      if (request === generation) status.textContent = error.message;
    } finally {
      if (request === generation) refresh();
    }
  };
  const cancel = form.querySelector('[data-cancel]');
  const close = dialog.querySelector('header button');
  cancel.onclick = () => dialog.close();
  dialog.addEventListener('cancel', event => { if (saving) event.preventDefault(); });
  form.onsubmit = async event => {
    event.preventDefault();
    if (saving || !rows.length || !authenticated || authEpoch !== epoch) return;
    saving = uf.disabled = cancel.disabled = close.disabled = true;
    refresh();
    status.textContent = 'Salvando cadastros…';
    try {
      const count = await crmRpc('crm_import_clients', {
        p_uf:uf.value, p_convenio:convenio.value.trim(), p_usar_digimais:digimais.value === 'yes', p_rows:rows
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

$('#crmImportClients').onclick = crmOpenClientImport;
