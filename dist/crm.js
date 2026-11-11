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
  const params = {...crmFilters, p_after:crmCursors[page] || '',p_limit:crmPageSize+1};
  $('#crmStatus').textContent = 'Carregando clientes…';
  $('#crmRows').replaceChildren();
  $('#crmPrevious').disabled = $('#crmNext').disabled = true;
  try {
    const clients = await crmRpc('crm_filter_clients', params);
    if (request !== crmListRequest) return;
    crmPage = page;
    if(clients.length>crmPageSize)crmCursors[page+1]=clients[crmPageSize-1].cpf;
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
      const actions=crmElement('div','crm-client-actions');
      const profile=crmElement('button','','Abrir ficha');profile.type='button';
      profile.onclick=()=>crmOpenClientProfile(client);
      actions.append(profile,button);
      $('#crmRows').append(crmRow([client.nome, formatCpf(client.cpf), client.telefone, actions]));
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
    const owner = {cpf:'eq.' + client.cpf, user_id:'eq.' + client.user_id, limit:100};
    const [linksResponse, classificationsResponse, catalogResponse] = await Promise.allSettled([
      sbRequest(crmPath('crm_vinculos', {...owner, order:'confirmado_em.desc,convenio.asc,matricula.asc'})),
      sbRequest(crmPath('crm_classificacoes', {...owner, order:'importado_em.desc'})),
      crmGetImportCatalog().catch(() => [])
    ]);
    if (crmClient !== client) return;
    const links = linksResponse.value || [], classifications = classificationsResponse.value || [];
    const catalog = catalogResponse.value || [];
    if (client.data_nascimento) {
      list.append(crmElement('li','','Nascimento: '+client.data_nascimento.split('-').reverse().join('/')));
    }
    for (const [source, snapshot] of Object.entries(client.resumo_consultas || {})) {
      const data = snapshot.dados;
      const columns = crmAmigozColumns({
        margem:source.startsWith('amigoz_margem_') ? {status:'respondido',dados:data} : null,
        saque:source.startsWith('amigoz_saque_') ? {status:'respondido',dados:{ofertas:data}} : null
      }, value => crmMoney.format(value));
      const summary = source === 'digimais'
        ? [data.status === 'nao_cliente' ? 'Digi+ · Não é cliente' : 'Digi+',
           data.saldo != null ? 'Saldo '+crmMoney.format(data.saldo) : null,
           data.parcela != null ? 'Parcela '+crmMoney.format(data.parcela) : null]
        : source.startsWith('consigx_margem_') ? ['ConsigX', data.margem_emprestimo != null ? 'Margem empréstimo '+crmMoney.format(data.margem_emprestimo) : null, data.margem_cartao != null ? 'Margem cartão '+crmMoney.format(data.margem_cartao) : null]
        : ['Amigoz',columns.margemCartao,columns.limite && 'Limite '+columns.limite,columns.saque && 'Saque '+columns.saque];
      list.append(crmElement('li','',summary.filter(Boolean).join(' · ')));
    }
    for (const link of links) {
      const label = link.uf + ' · ' + link.convenio.toUpperCase();
      const item = document.createElement('li');
      item.textContent = [label, 'Matrícula ' + link.matricula, link.situacao_atual,
        ({consigx:'ConsigX',amigoz:'Amigoz',importacao:'Importação'})[link.fonte], new Date(link.confirmado_em).toLocaleDateString('pt-BR')].filter(Boolean).join(' · ');
      list.append(item);
      const agreements = $('#crmOpportunityAgreement');
      if (!Array.from(agreements.options).some(option => option.value === link.convenio)) {
        agreements.add(new Option(label, link.convenio));
      }
    }
    for (const classification of classifications) {
      const agreement = catalog.find(row => row.uf === classification.uf && row.codigo === classification.convenio);
      const label = classification.uf + ' · ' + (agreement?.nome || classification.convenio.toUpperCase());
      const planned = classification.servicos_planejados?.length ? classification.servicos_planejados
        : classification.usar_digimais ? ['digimais_saldo'] : [];
      const preference = planned.map(service => crmPlannedServices[service] || service).join(', ') || 'Sem consultas previstas';
      const item = crmElement('li','',label + ' · Informado na importação · ' + preference);
      if (agreement) crmAddPlannedActions(item, client, agreement, planned);
      list.append(item);
    }
    status.textContent = linksResponse.status === 'rejected' || classificationsResponse.status === 'rejected' ? 'Parte dos vínculos ou classificações não pôde ser carregada.' : links.length || classifications.length ? '' : 'Nenhum vínculo ou classificação registrado.';
  } catch {
    if (crmClient === client) status.textContent = 'Não foi possível carregar os vínculos.';
  }
}

function crmAmigozColumns(result, money) {
  const margins = result?.margem?.status === 'respondido' && Array.isArray(result.margem.dados)
    ? result.margem.dados.filter(item => item && typeof item === 'object') : [];
  const offers = result?.saque?.status === 'respondido' && Array.isArray(result.saque.dados?.ofertas)
    ? result.saque.dados.ofertas.filter(item => item && !item.erro_informado) : [];
  const currency = value => typeof value === 'number' && Number.isFinite(value) ? money(value) : null;
  const join = values => [...new Set(values.filter(Boolean))].join(' · ') || null;
  const cardType = item => ({7:'Benefício',15:'Consignado'})[item.idProduto ?? item.tipo_produto];
  const offerValues = field => join(offers.map(item => {
    const amount = currency(item[field]);
    return amount && (item.nome_oferta ? item.nome_oferta + ': ' + amount : amount);
  }));
  return {
    matricula: join(margins.map(item => item.numeroMatricula != null ? String(item.numeroMatricula) : null)),
    margemCartao: join(margins.map(item => {
      const type = cardType(item), amount = currency(item.margem_atual);
      return type && amount ? type + ': ' + amount : null;
    })),
    limite: offerValues('limite_cartao'),
    saque: offerValues('valor_saque_disponivel')
  };
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
      const service = row.servico.startsWith('amigoz_') ? 'Amigoz · ' + ({amigoz_ambos:'Margem e saque',amigoz_margem:'Margem',amigoz_saque:'Saque complementar'}[row.servico] || row.servico) : row.convenio ? 'ConsigX · ' + row.convenio.toUpperCase() : 'Digi+';
      const amigoz = row.servico.startsWith('amigoz_');
      const columns = crmAmigozColumns(row.resultado_amigoz, money);
      $('#crmHistoryRows').append(crmRow([service, statusNames[row.status] || row.status,
        columns.matricula ?? row.matricula, row.situacao_atual, money(row.emprestimo_disponivel),
        columns.margemCartao ?? money(row.cartao_disponivel), money(row.saldo_liquidacao), money(row.valor_parcela),
        columns.limite, columns.saque,
        new Date(row.consultado_em || row.created_at).toLocaleString('pt-BR')]));
      if (!amigoz) continue;
      const detailRow = document.createElement('tr'), cell = document.createElement('td');
      cell.colSpan = 11;
      const details = document.createElement('details'), summary = document.createElement('summary');
      summary.textContent = 'Amigoz · ' + (row.detalhe || (row.status === 'aguardando' ? 'Aguardando processamento na VPS' : 'Detalhes da consulta'));
      details.append(summary);
      if (row.resultado_amigoz) {
        const body = document.createElement('pre');
        body.textContent = JSON.stringify(row.resultado_amigoz,null,2);
        body.style.whiteSpace = 'pre-wrap';
        details.append(body);
      }
      cell.append(details); detailRow.append(cell); $('#crmHistoryRows').append(detailRow);
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
  if (!authenticated) {
    for (const id of ['crmStageFilter','crmKanbanProduct','crmKanbanAgreement','crmKanbanOwner']) $('#'+id).value='';
    $('#crmKanbanAgreement').replaceChildren(new Option('Todos',''));
  }
  if (page === 'clients') {
    loadCrmFilterOptions();loadCrmClients(crmPage);
    return;
  }
  crmListRequest++;
  closeCrmHistory();
  $('#crmRows').replaceChildren();
  if (!authenticated) {
    document.querySelectorAll('.crm-dialog').forEach(dialog=>dialog.close());
    crmQuery = $('#crmQuery').value = '';
    crmPage = 0;crmCursors=[''];crmFilters={p_query:'',p_uf:'',p_convenio:'',p_servico:''};crmSettings=null;
    for(const id of ['crmUF','crmAgreementFilter','crmServiceFilter'])$('#'+id).value='';
  }
}

$('#crmSearch').onsubmit = event => {
  event.preventDefault();
  closeCrmHistory();
  crmQuery = $('#crmQuery').value.trim();
  crmFilters={p_query:crmQuery,p_uf:$('#crmUF').value,p_convenio:$('#crmAgreementFilter').value,p_servico:$('#crmServiceFilter').value};
  crmCursors=[''];loadCrmClients(0);
};
$('#crmPrevious').onclick = () => { closeCrmHistory(); loadCrmClients(crmPage - 1); };
$('#crmNext').onclick = () => { closeCrmHistory(); loadCrmClients(crmPage + 1); };
$('#crmClose').onclick = () => closeCrmHistory(true);
$('#crmMoreHistory').onclick = loadCrmHistory;
$('#crmOpenClientProfile').onclick = () => {if (crmClient) crmOpenClientProfile(crmClient);};

const crmStages = {
  novo:'Novo', exportada:'Exportadas', contato:'Em contato', simulacao:'Simulação enviada',
  negociacao:'Em negociação', ganho:'Ganho', perdido:'Perdido'
};
const crmProducts = {margem:'Contrato novo',saque:'Saque complementar',recompra:'Compra de dívida'};
let crmPipelineRequest = 0;
let crmPipelinePage = 0;

function crmStageOptions(select, value, includeAll = false) {
  if (includeAll) select.add(new Option('Todas', ''));
  for (const [key,label] of Object.entries(crmStages)) select.add(new Option(label, key));
  select.value = value;
}

async function loadCrmPipeline(page) {
  const request = ++crmPipelineRequest;
  const status=$('#crmPipelineStatus'), board=$('#crmPipelineRows');
  board.replaceChildren();status.textContent='Carregando oportunidades…';
  $('#crmPipelinePrevious').hidden=$('#crmPipelineNext').hidden=true;
  try {
    const settings=await crmLoadSettings();
    if(request!==crmPipelineRequest)return;
    const selected=$('#crmStageFilter').value;
    const agreement=$('#crmKanbanAgreement');
    const filters={p_produto:$('#crmKanbanProduct').value,p_convenio:agreement.value,p_responsavel:$('#crmKanbanOwner').value.trim()};
    try {
      const options=await crmRpc('crm_filter_options');
      if(request!==crmPipelineRequest)return;
      agreement.replaceChildren(new Option('Todos',''));
      for(const value of [...new Set(options.map(row=>row.convenio))]) agreement.add(new Option(value.toUpperCase(),value));
      agreement.value=filters.p_convenio;
    } catch {
      if(request!==crmPipelineRequest)return;
    }
    for(const [key,label] of Object.entries(crmStages)) {
      if(selected&&key!==selected)continue;
      const column=crmElement('section','crm-kanban-column');
      const heading=crmElement('h2','',label), cards=crmElement('div','crm-kanban-cards');
      const more=crmElement('button','','Carregar mais');more.type='button';
      column.append(heading,cards,more);board.append(column);
      let offset=0,busy=false;
      const load=async()=>{
        if(busy)return;busy=true;more.disabled=true;more.textContent='Carregando…';
        try {
          const rows=await crmRpc('crm_filtrar_kanban',{...filters,p_etapa:key,p_offset:offset});
          if(request!==crmPipelineRequest)return;
          for(const row of rows.slice(0,crmPageSize))cards.append(crmOpportunityCard(row,settings,request));
          offset+=Math.min(rows.length,crmPageSize);
          heading.textContent=label+' · '+offset+(rows.length>crmPageSize?' +':'');
          if(!offset)cards.append(crmElement('p','muted','Nenhuma oportunidade nesta etapa.'));
          more.hidden=rows.length<=crmPageSize;more.textContent='Carregar mais';
        }catch{if(request===crmPipelineRequest){status.textContent='Uma etapa não carregou. Use Tentar novamente.';more.textContent='Tentar novamente';}}
        finally{busy=false;more.disabled=false;}
      };
      more.onclick=load;
      column.ondragover=event=>{event.preventDefault();};
      column.ondrop=async event=>{
        event.preventDefault();const id=event.dataTransfer.getData('text/plain');
        if(!/^[a-f0-9-]{36}$/.test(id))return;
        await crmMoveOpportunity(id,key,request);
      };
      await load();
      if(request!==crmPipelineRequest)return;
    }
    if(request===crmPipelineRequest&&!status.textContent.startsWith('Uma etapa'))status.textContent='Arraste um cartão ou use o seletor de etapa. Os valores financeiros vêm das consultas.';
  }catch{if(request===crmPipelineRequest)status.textContent='Não foi possível carregar o funil. Clique em Atualizar.';}
}

crmStageOptions($('#crmStageFilter'), '', true);
$('#crmStageFilter').onchange = () => loadCrmPipeline(0);
for (const id of ['crmKanbanProduct','crmKanbanAgreement','crmKanbanOwner']) $('#'+id).onchange = () => loadCrmPipeline(0);
$('#crmExportOpportunities').onclick = async () => {
  const {dialog,form} = crmDialog('Exportar oportunidades');
  const epoch = authEpoch;
  const stage = $('#crmStageFilter').value;
  const uf = document.createElement('select'), convenio = document.createElement('select');
  crmLabeled(form,'Estado',uf);
  crmLabeled(form,'Convênio',convenio);
  const types = crmElement('fieldset','crm-export-types');
  types.append(crmElement('legend','','Tipos de oportunidade'));
  const checks = Object.entries(crmProducts).map(([key,name])=>{
    const box = document.createElement('input');
    box.type = 'checkbox';box.value = key;box.checked = true;
    crmLabeled(types,name,box);
    return box;
  });
  form.append(types,crmElement('p','muted','Etapa: '+(crmStages[stage] || 'Todas as etapas abertas')));
  const status = crmElement('p','muted','Carregando estados e convênios…');
  status.setAttribute('role','status');
  const submit = crmElement('button','primary','Ver prévia');
  submit.type = 'submit';submit.disabled = true;
  form.append(status,submit);
  try {
    const [options,catalog] = await Promise.all([crmRpc('crm_filter_options'),crmGetImportCatalog().catch(()=>[])]);
    if (epoch !== authEpoch || !dialog.open) return;
    uf.add(new Option('Todos os estados',''));
    for (const code of [...new Set(options.map(item=>item.uf))]) uf.add(new Option(crmStates[code] || code,code));
    const updateAgreements = ()=>{
      convenio.replaceChildren(new Option('Todos os convênios',''));
      const shown = new Set();
      for (const item of options) {
        if ((uf.value && item.uf !== uf.value) || shown.has(item.convenio)) continue;
        shown.add(item.convenio);
        const name = catalog.find(row=>row.uf===item.uf && row.codigo===item.convenio)?.nome || item.convenio.toUpperCase();
        convenio.add(new Option(name,item.convenio));
      }
    };
    uf.onchange = updateAgreements;
    updateAgreements();
    status.textContent = '';
    submit.disabled = false;
    form.onsubmit = async event=>{
      event.preventDefault();
      if (submit.disabled || epoch !== authEpoch) return;
      await crmDownloadOpportunities({stage,uf:uf.value,convenio:convenio.value,products:checks.filter(box=>box.checked).map(box=>box.value)},submit,status,form);
    };
  } catch {
    status.textContent = 'Não foi possível carregar os filtros de exportação.';
  }
};

async function crmDownloadOpportunities({stage,uf,convenio,products},button,status,previewForm) {
  const epoch = authEpoch;
  const openStages = ['novo','contato','simulacao','negociacao'];
  if (!products.length) {status.textContent = 'Selecione pelo menos um tipo para exportar.';return;}
  if (stage && !openStages.includes(stage)) {
    status.textContent = 'Selecione uma etapa aberta para exportar.';
    return;
  }
  previewForm?.querySelector('.crm-export-preview')?.remove();
  button.disabled = true;
  status.textContent = 'Preparando planilha…';
  const rows = [];
  let after = '', downloaded = false;
  try {
    for (;;) {
      const page = await crmRpc('crm_export_opportunities',{
        p_uf:uf,p_convenio:convenio,p_tipos:products,p_etapa:stage,p_after:after || null
      });
      if (!authenticated || epoch !== authEpoch) return;
      if (!page.length) break;
      rows.push(...page);
      const next = page[page.length-1].id;
      if (!next || next <= after) throw Error('Paginação inválida');
      after = next;
    }
    if (!rows.length) {status.textContent = 'Nenhuma oportunidade aberta neste filtro.';return;}
    const workbookRows = [
      ['Nome','CPF','Convênio','Produto','Etapa original','Responsável','Próxima ação','Saldo Digi+','Parcela Digi+','Saque Amigoz','Margem livre'],
      ...rows.map(row => {
        const signals = row.sinais_consulta || {};
        const offers = Object.entries(signals).filter(([key,value])=>key.startsWith('amigoz_saque_') && Array.isArray(value))
          .flatMap(([,items])=>items.filter(item=>item && String(item.elegivel).toLowerCase()==='sim' && !item.erro_informado && item.valor_saque_disponivel>0));
        return [row.nome,formatCpf(row.cpf),row.convenio,crmProducts[row.produto],crmStages[row.etapa],row.responsavel,row.proxima_acao,
          signals.digimais?.saldo ?? row.saldo_liquidacao,signals.digimais?.parcela,
          offers.map(item=>crmMoney.format(item.valor_saque_disponivel)).join(' · '),crmOpportunityMargins(signals).map(value=>crmMoney.format(value)).join(' · ')];
      })
    ];
    const download = async (trigger)=>{
      trigger.disabled = true;
      try {
        if (!authenticated || epoch !== authEpoch) return;
        crmSaveOpportunityWorkbook(workbookRows);
        downloaded = true;
        status.textContent = 'Download iniciado. Registrando lote e movimentando cartões…';
        const moved = await crmRpc('crm_registrar_exportacao',{
          p_lote:batchId,p_itens:rows.map(({id,etapa})=>({id,etapa})),p_planilha:workbookRows
        });
        if (!authenticated || epoch !== authEpoch) return;
        status.textContent = rows.length+' no arquivo · '+moved+' movidas para Exportadas.';
        $('#crmExportOpportunitiesStatus').textContent = status.textContent;
        if (!$('#crmPipelineRows').closest('[hidden]')) await loadCrmPipeline(0);
      } catch {
        status.textContent = downloaded ? 'Download iniciado. O lote não foi confirmado. Tente novamente nesta janela.' : 'Não foi possível gerar a planilha.';
        trigger.disabled = false;
      }
    };
    const batchId = crypto.randomUUID();
    if (!previewForm) {await download(button);return;}
    const preview = crmElement('section','crm-export-preview');
    preview.append(crmElement('h3','',rows.length+' oportunidades na planilha'));
    for (const [key,label] of Object.entries(crmProducts)) {
      const count = rows.filter(row=>row.produto===key).length;
      if (count) preview.append(crmElement('p','',label+' · '+count));
    }
    const confirm = crmElement('button','primary','Baixar planilha e mover para Exportadas');
    confirm.type = 'button';confirm.onclick = ()=>download(confirm);
    preview.append(confirm);previewForm.append(preview);
    previewForm.onchange = ()=>{preview.remove();status.textContent='Filtros alterados. Gere uma nova prévia.';};
    status.textContent = 'Confira a seleção antes de baixar.';
  } catch {
    if (epoch === authEpoch) status.textContent = downloaded
      ? 'Download iniciado. Não foi possível confirmar a movimentação. Confira o Kanban.'
      : 'Não foi possível gerar a planilha.';
  } finally {button.disabled = false;}
}
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

let crmFilters={p_query:'',p_uf:'',p_convenio:'',p_servico:''};
let crmCursors=[''];
let crmSettings=null;
let crmOptions=[];
const crmBuiltinFields={cpf:'CPF',produto:'Produto',convenio:'Convênio',proxima_acao:'Próxima ação'};
function crmElement(tag,className='',text='') {const el=document.createElement(tag);el.className=className;el.textContent=text;return el;}
function crmRpc(name,params={}) {return sbRequest('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(params)});}
async function loadCrmFilterOptions(){
  const epoch=authEpoch;
  try{
    const [options, catalog] = await Promise.all([
      crmRpc('crm_filter_options'),
      typeof crmGetImportCatalog === 'function' ? crmGetImportCatalog().catch(() => []) : []
    ]);
    if(currentPage!=='clients'||!authenticated||epoch!==authEpoch)return;
    crmOptions=options.map(option => ({
      ...option,
      nome:catalog.find(row => row.uf === option.uf && row.codigo === option.convenio)?.nome
    }));
    const uf=$('#crmUF'),selected=uf.value;
    uf.replaceChildren(new Option('Todos',''));
    for(const value of [...new Set(options.map(x=>x.uf))])uf.add(new Option(value,value));
    uf.value=selected;crmUpdateAgreements();
  }catch{if(currentPage==='clients')$('#crmStatus').textContent='Não foi possível carregar os filtros. Tente abrir Clientes novamente.';}
}
function crmUpdateAgreements(){
  const select=$('#crmAgreementFilter'),selected=select.value;
  select.replaceChildren(new Option('Todos',''));
  for(const item of crmOptions.filter(x=>!$('#crmUF').value||x.uf===$('#crmUF').value))select.add(new Option((item.nome || item.convenio.toUpperCase())+' · '+item.uf,item.convenio));
  select.value=Array.from(select.options).some(x=>x.value===selected)?selected:'';
}
$('#crmUF').onchange=crmUpdateAgreements;
function crmCsvCell(value){let str=String(value??'');if(typeof value!=='number' && /^[=+@\-\t\r]/.test(str))str="'"+str;return '"'+str.replace(/"/g,'""')+'"';}
$('#crmExport').onclick=()=>crmExportClients(false);
$('#crmExportTemplate').onclick=()=>crmExportClients(true);
$('#crmExportTemplateExcel').onclick=()=>crmExportClients(true,true);
async function crmExportClients(template,excel=false){
  const button=$(excel?'#crmExportTemplateExcel':template?'#crmExportTemplate':'#crmExport'),status=$('#crmStatus'),epoch=authEpoch;
  button.disabled=true;
  const filters={p_query:$('#crmQuery').value.trim(),p_uf:$('#crmUF').value,p_convenio:$('#crmAgreementFilter').value,p_servico:$('#crmServiceFilter').value};
  let after='',total=0;
  try{
    const agreement=template && (await crmGetImportCatalog()).find(item=>item.uf===filters.p_uf && item.codigo===filters.p_convenio);
    if(template && !agreement){
      status.textContent='Selecione Estado e Convênio para baixar no modelo padrão.';
      return;
    }
    const headers=template?crmAgreementTemplate(agreement,false)[0]:['Nome','CPF','Telefone','Última atividade'];
    const chunks=['\uFEFF'+headers.join(';')+'\r\n'];
    const workbookRows=excel?[headers]:null;
    for(;;){
      const rows=await crmRpc('crm_filter_clients',{...filters,p_after:after,p_limit:500});
      if(!authenticated||epoch!==authEpoch)throw Error('Sessão encerrada');
      if(!rows.length)break;
      const cells = template
        ? await crmClientTemplateRows(rows,filters,headers)
        : rows.map(x=>[x.nome,formatCpf(x.cpf),x.telefone,x.ultima_atividade?new Date(x.ultima_atividade).toLocaleString('pt-BR'):'']);
      if(!authenticated||epoch!==authEpoch)throw Error('Sessão encerrada');
      if(excel) workbookRows.push(...cells);
      else chunks.push(cells.map(row=>row.map(crmCsvCell).join(';')).join('\r\n')+'\r\n');
      total+=rows.length;status.textContent='Exportando '+total+' clientes…';
      const next=rows[rows.length-1].cpf;if(next<=after)throw Error('Paginação inválida');after=next;
    }
    if(!total){status.textContent='Nenhum cliente corresponde aos filtros.';return;}
    let file;
    if(excel){
      const book=crmAgreementWorkbook(agreement,workbookRows);
      const bytes=XLSX.write(book,{type:'array',bookType:'xlsx',compression:true});
      file=new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
    }else{
      file=new Blob(chunks,{type:'text/csv;charset=utf-8'});
    }
    if(template && (total>10000 || file.size>2000000)){
      status.textContent='O arquivo excede o limite de importação. Reduza o filtro para baixar um lote reimportável.';
      return;
    }
    const url=URL.createObjectURL(file);
    const link=document.createElement('a');link.href=url;
    link.download=(template?'clientes-modelo-padrao-':'clientes-')+new Date().toISOString().slice(0,10)+(excel?'.xlsx':'.csv');
    link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    status.textContent=total+' clientes exportados. Filtros aplicados ao arquivo inteiro.';
  }catch{status.textContent='A exportação não foi concluída. Nenhum arquivo parcial foi baixado. Tente novamente.';}
  finally{button.disabled=false;}
}
async function crmClientTemplateRows(rows,filters,headers){
  const registrations=new Map();
  for(let start=0;start<rows.length;start+=100){
    const group=rows.slice(start,start+100);
    let offset=0;
    for(;;){
      const links=await sbRequest(crmPath('crm_vinculos',{
        cpf:'in.('+group.map(row=>row.cpf).join(',')+')',uf:'eq.'+filters.p_uf,convenio:'eq.'+filters.p_convenio,
        select:'cpf,matricula',order:'confirmado_em.desc,cpf.asc,matricula.asc',limit:100,offset
      }));
      for(const link of links) if(!registrations.has(link.cpf)) registrations.set(link.cpf,link.matricula);
      offset+=links.length;
      if(!links.length || registrations.size===rows.length) break;
    }
  }
  const agreement=filters.p_convenio;
  return rows.map(row=>{
    const facts=row.resumo_consultas||{};
    const latest = entries=>entries.filter(([fact])=>fact)
      .sort(([a],[b])=>String(b.data).localeCompare(String(a.data)))
      .map(([fact,read])=>read(fact.dados)).find(Number.isFinite);
    const imported=facts['margem_importada_'+agreement], consigx=facts['consigx_margem_'+agreement];
    const loan=latest([[imported,d=>d?.margem_emprestimo],[consigx,d=>d?.margem_emprestimo]]);
    const card=latest([[imported,d=>d?.margem_cartao],[consigx,d=>d?.margem_cartao],
      [facts['amigoz_margem_'+agreement],data=>{
        const values=Array.isArray(data)?data.map(item=>item?.margem_atual).filter(Number.isFinite):[];
        return values.length?Math.max(...values):null;
      }]]);
    const offers=facts['amigoz_saque_'+agreement]?.dados;
    const valid=Array.isArray(offers)?offers.filter(item=>item && !item.erro_informado):[];
    const eligible=valid.filter(item=>String(item.elegivel).toLowerCase()==='sim');
    const declined=valid.some(item=>['não','nao'].includes(String(item.elegivel).toLowerCase()));
    const values=(eligible.length?eligible:valid).map(item=>item.valor_saque_disponivel).filter(Number.isFinite);
    const cells={cpf:formatCpf(row.cpf),nome:row.nome,telefone:row.telefone,
      matricula:registrations.get(row.cpf),data_nascimento:row.data_nascimento,
      margem_emprestimo:loan,margem_cartao:card,saque_amigoz_elegivel:eligible.length?'Sim':declined?'Não':'',
      saque_amigoz_valor:values.length && (eligible.length || !declined)?Math.max(...values):null,
      uf:filters.p_uf,convenio:agreement};
    return headers.map(field=>cells[field]);
  });
}
async function crmLoadSettings(){
  const rows=await sbRequest(crmPath('crm_card_settings',{}));
  crmSettings=rows[0]||{visible:Object.keys(crmBuiltinFields),fields:[]};return crmSettings;
}
async function crmMoveOpportunity(id,stage,request,extra={}){
  try{
    const rows=await sbRequest(crmPath('crm_oportunidades',{id:'eq.'+id}),{method:'PATCH',headers:{Prefer:'return=representation'},body:JSON.stringify({etapa:stage,...extra})});
    if(!rows?.length)throw Error();
    if(request===crmPipelineRequest){await loadCrmPipeline(0);$('#crmPipelineStatus').textContent='Oportunidade salva.';}
    return true;
  }catch{if(request===crmPipelineRequest)$('#crmPipelineStatus').textContent='Não foi possível salvar. O cartão permanece na etapa anterior.';return false;}
}
function crmOpportunityCard(row,settings,request){
  const card=crmElement('article','crm-kanban-card'+(settings.density==='compact'?' compact':''));card.draggable=true;card.dataset.id=row.id;
  card.ondragstart=event=>event.dataTransfer.setData('text/plain',row.id);
  const title=crmElement('button','crm-card-title',row.nome||formatCpf(row.cpf));
  title.type='button';title.onclick=()=>crmOpenClientProfile(row,row.id);
  const heading=crmElement('h3');heading.append(title);card.append(heading);
  card.onclick=event=>{if (!event.target.closest('button,select,label,input,textarea,a')) crmOpenClientProfile(row,row.id);};
  card.append(crmElement('p','crm-card-detail','Responsável: '+(row.responsavel||'Não atribuído')));
  if(row.proxima_acao) card.append(crmElement('p','crm-card-detail','Próxima ação: '+row.proxima_acao));
  for(const key of settings.visible){const value=key==='cpf'?formatCpf(row.cpf):key==='produto'?crmProducts[row.produto]:row[key];if(value)card.append(crmElement('p','crm-card-detail',crmBuiltinFields[key]+': '+value));}
  for(const field of settings.fields.filter(x=>x.visible)){
    const value=row.campos?.[field.id];if(value!=null&&value!=='')card.append(crmElement('p','crm-card-detail',field.label+': '+(field.type==='boolean'?(value?'Sim':'Não'):value)));
  }
  const finance=crmElement('div','crm-card-finance','Buscando resultado financeiro…');card.append(finance);
  crmCardFinance(row,finance,request);
  const label=crmElement('label','','Mover para');const select=document.createElement('select');crmStageOptions(select,row.etapa);label.append(select);
  select.setAttribute('aria-label','Etapa de '+(row.nome||formatCpf(row.cpf)));
  select.onchange=async()=>{select.disabled=true;const ok=await crmMoveOpportunity(row.id,select.value,request);if(!ok){select.value=row.etapa;select.disabled=false;}};
  const edit=crmElement('button','','Editar cartão');edit.type='button';edit.onclick=()=>crmEditOpportunity(row,settings,request);
  const actions=crmElement('div','crm-card-actions');
  actions.append(label,edit);card.append(actions);return card;
}
function crmOpportunityMargins(signals) {
  return Object.entries(signals).flatMap(([source,data])=>{
    if(source.startsWith('amigoz_margem_') && Array.isArray(data)) return data.map(item=>item?.margem_atual);
    if(source.startsWith('consigx_margem_')) return [data?.margem_emprestimo];
    if(source.startsWith('margem_importada_')) return [data?.margem_emprestimo,data?.margem_cartao];
    return [];
  }).filter(value=>typeof value==='number' && value>20);
}
function crmCardFinance(row,target,request){
  target.replaceChildren();
  if(row.automatica){
    const tags=crmElement('div','crm-card-tags');
    const metrics=crmElement('div','crm-card-metrics');
    const metric=(label,value)=>{
      if(value == null) return;
      const item=crmElement('div','crm-card-metric');
      item.append(crmElement('span','',label),crmElement('strong','',crmMoney.format(value)));
      metrics.append(item);
    };
    const sources=Object.entries(row.sinais_consulta || {});
    const digi=row.sinais_consulta?.digimais;
    if(digi){
      tags.append(crmElement('span','crm-card-tag crm-tag-digi','Cliente Digi+'));
      metric('Saldo devedor',digi.saldo);
      metric('Parcela',digi.parcela);
    }
    const offers=sources.filter(([source,data])=>source.startsWith('amigoz_saque_')&&Array.isArray(data))
      .flatMap(([,data])=>data.filter(item=>item && String(item.elegivel).toLowerCase()==='sim' && !item.erro_informado && item.valor_saque_disponivel>0));
    if(offers.length){
      tags.append(crmElement('span','crm-card-tag crm-tag-amigoz','Saque Amigoz'));
      for(const offer of offers) metric(offer.nome_oferta ? 'Saque · '+offer.nome_oferta : 'Saque disponível',offer.valor_saque_disponivel);
    }
    const margins=crmOpportunityMargins(row.sinais_consulta || {});
    if(margins.length){
      tags.append(crmElement('span','crm-card-tag crm-tag-amigoz','Contrato novo / agregação'));
      for(const margin of margins) metric('Margem livre',margin);
    }
    if(tags.childNodes.length) target.append(tags,metrics);
    else target.textContent='Sem sinal comercial ativo.';
    return;
  }
  const key=row.produto==='recompra'?'saldo_liquidacao':'emprestimo_disponivel';
  if(row[key]==null){target.textContent='Sem resultado financeiro vinculado.';return;}
  target.append(crmElement('strong','',(key==='saldo_liquidacao'?'Saldo: ':'Margem: ')+crmMoney.format(row[key])));
  target.append(crmElement('small','',(row.resultado_fonte==='digimais_saldo_parcela'?'Digi+':'ConsigX · '+row.convenio.toUpperCase())+' · '+new Date(row.resultado_em||row.resultado_criado_em).toLocaleString('pt-BR')));
}
function crmSaveOpportunityWorkbook(rows) {
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet(rows),'Oportunidades');
  XLSX.writeFile(book,'oportunidades-'+new Date().toISOString().slice(0,10)+'.xlsx');
}

$('#crmExportHistory').onclick = async () => {
  const {dialog,form} = crmDialog('Histórico de exportações');
  const epoch = authEpoch;
  const status = crmElement('p','muted','Carregando lotes…');
  status.setAttribute('role','status');
  const list = crmElement('div','crm-export-history');
  const more = crmElement('button','','Carregar mais');more.type='button';more.hidden=true;
  form.append(status,list,more);
  let offset=0;
  const load=async()=>{
    more.disabled=true;
    try {
      const batches=await sbRequest(crmPath('crm_exportacoes',{select:'id,criada_em,total,movidas',order:'criada_em.desc,id.desc',limit:26,offset}));
      if (!dialog.open || epoch!==authEpoch) return;
      for (const batch of batches.slice(0,25)) {
        const item=crmElement('div','crm-export-batch');
        item.append(crmElement('strong','',new Date(batch.criada_em).toLocaleString('pt-BR')));
        item.append(crmElement('span','muted',batch.total+' no arquivo · '+batch.movidas+' movidas'));
        const download=crmElement('button','','Baixar novamente');download.type='button';
        download.onclick=async()=>{
          download.disabled=true;
          try {
            const [saved]=await sbRequest(crmPath('crm_exportacoes',{id:'eq.'+batch.id,select:'planilha'}));
            if (dialog.open && epoch===authEpoch && saved) crmSaveOpportunityWorkbook(saved.planilha);
          } catch {status.textContent='Não foi possível baixar este lote.';}
          finally {download.disabled=false;}
        };
        item.append(download);list.append(item);
      }
      offset+=Math.min(25,batches.length);
      more.hidden=batches.length<=25;
      status.textContent=offset?'':'Nenhum lote registrado.';
    } catch {status.textContent='Não foi possível carregar os lotes.';more.hidden=false;}
    finally {more.disabled=false;}
  };
  more.onclick=load;await load();
};

async function crmOpenClientProfile(row,selectedId) {
  const {dialog,form}=crmDialog('Ficha · '+(row.nome||formatCpf(row.cpf)));
  dialog.classList.add('crm-client-drawer');
  const epoch=authEpoch;
  const status=crmElement('p','muted','Carregando cadastro e consultas…');status.setAttribute('role','status');form.append(status);
  const scope={cpf:'eq.'+row.cpf,user_id:'eq.'+row.user_id};
  const money=value=>value==null?'Não informado':crmMoney.format(value);
  try {
    const [clients,links,opportunities,history,profileData]=await Promise.all([
      sbRequest(crmPath('crm_cadastros',{...scope,limit:1})),
      sbRequest(crmPath('crm_vinculos',{...scope,order:'confirmado_em.desc'})),
      sbRequest(crmPath('crm_opportunity_cards',{...scope,order:'created_at.desc,id.desc'})),
      sbRequest(crmPath('crm_consultas',{...scope,order:'created_at.desc,id.desc',limit:25})),
      sbRequest(crmPath('crm_dados_cliente',{...scope,order:'registrado_em.desc'}))
    ]);
    if (!dialog.open || epoch!==authEpoch) return;
    const client=clients[0]||row;
    status.remove();
    const registration=crmElement('section','crm-profile-section');
    registration.append(crmElement('h3','','Cadastro'));
    for (const [label,value] of [['Nome',client.nome],['CPF',formatCpf(row.cpf)],['Telefone',client.telefone],['Nascimento',client.data_nascimento?.split('-').reverse().join('/')]]) {
      registration.append(crmElement('p','',label+': '+(value||'Não informado')));
    }
    for (const link of links) registration.append(crmElement('p','','Matrícula '+link.matricula+' · '+link.uf+' · '+link.convenio));
    form.append(registration);
    const dataSection=crmElement('section','crm-profile-section');
    dataSection.append(crmElement('h3','','Dados registrados no perfil'));
    for(const fact of profileData){
      const institution={amigoz:'Amigoz',consigx:'ConsigX',digimais:'Digi+'}[fact.instituicao] || 'Instituição não informada';
      const kind={margem:'Margem',saque_complementar:'Saque complementar',saldo_parcela:'Saldo e parcela'}[fact.tipo];
      const entry=crmElement('div','crm-profile-opportunity');
      entry.append(crmElement('strong','',[kind,institution,fact.convenio].filter(Boolean).join(' · ')),
        crmElement('p','muted',(fact.origem==='importacao'?'Planilha':'Consulta')+' · '+new Date(fact.registrado_em).toLocaleString('pt-BR')));
      if(fact.tipo==='saque_complementar' && Array.isArray(fact.dados)){
        for(const offer of fact.dados) entry.append(crmElement('p','',
          'Elegível: '+(offer.elegivel ?? 'Não informado')+' · Valor disponível: '+money(offer.valor_saque_disponivel)));
        if(!fact.dados.length) entry.append(crmElement('p','','Sem oferta registrada.'));
      } else if(fact.tipo==='margem'){
        if(Array.isArray(fact.dados)){
          for(const item of fact.dados) entry.append(crmElement('p','',
            'Margem de cartão'+(item.idProduto===7?' Benefício':item.idProduto===15?' Consignado':'')+': '+money(item.margem_atual)));
        } else {
          entry.append(crmElement('p','','Margem de empréstimo: '+money(fact.dados.margem_emprestimo)),
            crmElement('p','','Margem de cartão: '+money(fact.dados.margem_cartao)));
        }
      } else if(fact.tipo==='saldo_parcela'){
        entry.append(crmElement('p','',fact.dados.status==='nao_cliente'?'Não é cliente':'Saldo: '+money(fact.dados.saldo)+' · Parcela: '+money(fact.dados.parcela)));
      }
      dataSection.append(entry);
    }
    if(!profileData.length) dataSection.append(crmElement('p','muted','Nenhum dado registrado.'));
    form.append(dataSection);

    const cards=crmElement('section','crm-profile-section');cards.append(crmElement('h3','','Oportunidades deste cliente'));
    const ordered=[...opportunities].sort((a,b)=>Number(b.id===selectedId)-Number(a.id===selectedId));
    for (const opportunity of ordered) {
      const item=crmElement('div','crm-profile-opportunity'+(opportunity.id===selectedId?' selected':''));
      item.append(crmElement('strong','',crmProducts[opportunity.produto]+' · '+crmStages[opportunity.etapa]),
        crmElement('p','','Responsável: '+(opportunity.responsavel||'Não atribuído')),
        crmElement('p','','Próxima ação: '+(opportunity.proxima_acao||'Não informada')));
      const finance=crmElement('div','crm-card-finance');crmCardFinance(opportunity,finance);item.append(finance);cards.append(item);
    }
    if(!ordered.length) cards.append(crmElement('p','muted','Nenhuma oportunidade registrada.'));
    form.append(cards);
    const consultations=crmElement('section','crm-profile-section');
    consultations.append(crmElement('h3','','Consultas recentes'));
    const seen=new Set();
    const list=crmElement('div');consultations.append(list);
    const append=items=>{
      for (const result of items) {
        const source=result.servico.startsWith('amigoz_')?'Amigoz':result.servico==='tjba_margem'?'ConsigX':'Digi+';
        const key=source+'|'+(result.convenio||'');
        const detail=crmElement('details','crm-profile-consultation');
        detail.open=!seen.has(key);seen.add(key);
        detail.append(crmElement('summary','',[
          source,result.convenio,statusNames[result.status]||result.status,new Date(result.consultado_em||result.created_at).toLocaleString('pt-BR')
        ].filter(Boolean).join(' · ')));
        const columns=crmAmigozColumns(result.resultado_amigoz,money);
        const fields=source==='Amigoz' ? [['Matrícula',columns.matricula||result.matricula],['Margem por produto',columns.margemCartao],['Limite',columns.limite],['Saque disponível',columns.saque]]
          : source==='ConsigX' ? [['Matrícula',result.matricula],['Situação funcional',result.situacao_atual],['Margem empréstimo',money(result.emprestimo_disponivel)],['Margem cartão',money(result.cartao_disponivel)]]
          : [['Saldo devedor',money(result.saldo_liquidacao)],['Parcela',money(result.valor_parcela)]];
        for(const [label,value] of fields) detail.append(crmElement('p','',label+': '+(value??'Não informado')));
        if(result.detalhe) detail.append(crmElement('p','muted',result.detalhe));
        list.append(detail);
      }
    };
    append(history);
    if(!history.length) list.append(crmElement('p','muted','Nenhuma consulta registrada.'));
    let offset=history.length;
    const more=crmElement('button','','Carregar consultas anteriores');more.type='button';more.hidden=history.length<25;
    more.onclick=async()=>{
      more.disabled=true;
      try {
        const page=await sbRequest(crmPath('crm_consultas',{...scope,order:'created_at.desc,id.desc',limit:25,offset}));
        if (!dialog.open || epoch!==authEpoch) return;
        append(page);offset+=page.length;more.hidden=page.length<25;
      } catch {more.textContent='Tentar carregar novamente';}
      finally {more.disabled=false;}
    };
    consultations.append(more);form.append(consultations);
  } catch {status.textContent='Não foi possível carregar a ficha. Feche e tente novamente.';}
}

function crmDialog(title){
  const dialog=document.createElement('dialog');dialog.className='crm-dialog';
  const header=crmElement('header','heading');header.append(crmElement('h2','',title));
  const close=crmElement('button','','Fechar');close.type='button';close.onclick=()=>dialog.close();header.append(close);dialog.append(header);
  const form=document.createElement('form');dialog.append(form);
  dialog.addEventListener('close',()=>dialog.remove());document.body.append(dialog);dialog.showModal();return {dialog,form};
}
function crmLabeled(form,text,input){const label=crmElement('label','crm-edit-field',text);label.append(input);form.append(label);return input;}
function crmEditOpportunity(row,settings,request){
  const {dialog,form}=crmDialog('Editar oportunidade');
  const title=document.createElement('input');title.value=row.nome||'';title.maxLength=160;crmLabeled(form,'Título do cartão (não altera o cadastro do cliente)',title);
  const owner=document.createElement('input');owner.maxLength=120;owner.value=row.responsavel||'';crmLabeled(form,'Responsável',owner);
  const action=document.createElement('textarea');action.maxLength=500;action.value=row.proxima_acao||'';crmLabeled(form,'Próxima ação',action);
  const inputs={};
  for(const field of settings.fields){
    const input=document.createElement('input');input.type=field.type==='boolean'?'checkbox':field.type==='number'?'number':field.type==='date'?'date':'text';input.maxLength=2000;if(input.type==='number')input.step='any';
    if(field.type==='boolean')input.checked=!!row.campos?.[field.id];else input.value=row.campos?.[field.id]??'';
    inputs[field.id]=input;crmLabeled(form,field.label,input);
  }
  form.append(crmElement('p','muted','Saldo e margem são dados de consulta e não podem ser editados.'));
  const status=crmElement('p');status.setAttribute('role','status');form.append(status);
  const save=crmElement('button','primary','Salvar alterações');save.type='submit';form.append(save);
  form.onsubmit=async event=>{
    event.preventDefault();save.disabled=true;const campos={};
    for(const field of settings.fields){const input=inputs[field.id];campos[field.id]=field.type==='boolean'?input.checked:input.value===''?null:field.type==='number'?Number(input.value):input.value;}
    const ok=await crmMoveOpportunity(row.id,row.etapa,request,{nome:title.value.trim()||null,responsavel:owner.value.trim()||null,proxima_acao:action.value.trim()||null,campos});
    if(ok)dialog.close();else{status.textContent='Não foi possível salvar. Verifique sua conexão e tente novamente.';save.disabled=false;}
  };
}
$('#crmCustomize').onclick=async()=>{
  const button=$('#crmCustomize');button.disabled=true;
  try{
    const settings=await crmLoadSettings(),fields=structuredClone(settings.fields);
    const {dialog,form}=crmDialog('Personalizar cartões');
    form.append(crmElement('p','muted','Escolha o que aparece nos cartões. Saldo e margem permanecem protegidos. A configuração é salva na sua conta.'));
    const density=document.createElement('select');density.add(new Option('Confortável','comfortable'));density.add(new Option('Compacto','compact'));density.value=settings.density||'comfortable';crmLabeled(form,'Espaçamento dos cartões',density);
    const visible={};for(const [key,label] of Object.entries(crmBuiltinFields)){
      const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.checked=settings.visible.includes(key);visible[key]=checkbox;crmLabeled(form,label,checkbox);
    }
    const list=crmElement('div','crm-custom-fields');form.append(list);
    const draw=()=>{list.replaceChildren();for(const field of fields){
      const item=crmElement('div','crm-custom-row');const input=document.createElement('input');input.value=field.label;input.maxLength=60;input.required=true;input.oninput=()=>field.label=input.value.trim();crmLabeled(item,'Nome do campo',input);
      item.append(crmElement('small','',({text:'Texto',number:'Número',date:'Data',boolean:'Sim / Não'})[field.type]));
      const check=document.createElement('input');check.type='checkbox';check.checked=field.visible;check.onchange=()=>field.visible=check.checked;crmLabeled(item,'Exibir no cartão',check);list.append(item);
    }};draw();
    const type=document.createElement('select');for(const [key,label] of Object.entries({text:'Texto',number:'Número',date:'Data',boolean:'Sim / Não'}))type.add(new Option(label,key));crmLabeled(form,'Tipo do novo campo',type);
    const add=crmElement('button','','Adicionar campo');add.type='button';add.onclick=()=>{if(fields.length>=30)return;fields.push({id:'cf_'+crypto.randomUUID().replace(/-/g,'').slice(0,16),label:'Novo campo',type:type.value,visible:true});draw();};form.append(add);
    const status=crmElement('p');status.setAttribute('role','status');form.append(status);const save=crmElement('button','primary','Salvar personalização');save.type='submit';form.append(save);
    form.onsubmit=async event=>{
      event.preventDefault();if(fields.some(f=>!f.label||/(saldo|margem|margens)/i.test(f.label))){status.textContent='Informe nomes válidos. Saldo e margem são reservados aos resultados.';return;}
      save.disabled=true;
      try{
        const data={density:density.value,visible:Object.keys(visible).filter(k=>visible[k].checked),fields};
        const saved=await sbRequest('/rest/v1/crm_card_settings'+(settings.user_id?'?user_id=eq.'+encodeURIComponent(settings.user_id):''),{method:settings.user_id?'PATCH':'POST',headers:{Prefer:'return=representation'},body:JSON.stringify(data)});
        if(!saved?.length)throw Error();dialog.close();await loadCrmPipeline(0);
      }catch{status.textContent='Não foi possível salvar a personalização. Tente novamente.';save.disabled=false;}
    };
  }catch{$('#crmPipelineStatus').textContent='Não foi possível carregar a personalização.';}finally{button.disabled=false;}
};
const crmRefresh=crmElement('button','','Atualizar');crmRefresh.type='button';crmRefresh.onclick=()=>loadCrmPipeline(0);$('#crmCustomize').after(crmRefresh);

$('#sidebarToggle').onclick=()=>{const collapsed=$('#appShell').classList.toggle('sidebar-collapsed');$('#sidebarToggle').setAttribute('aria-expanded',String(!collapsed));};
