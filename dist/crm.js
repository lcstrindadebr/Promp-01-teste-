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
  if (!authenticated) $('#crmStageFilter').value = '';
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
          const rows=await sbRequest(crmPath('crm_opportunity_cards',{etapa:'eq.'+key,order:'created_at.desc,id.desc',limit:crmPageSize+1,offset}));
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
$('#crmExportOpportunities').onclick = async () => {
  const button = $('#crmExportOpportunities'), status = $('#crmExportOpportunitiesStatus');
  const stage = $('#crmStageFilter').value, epoch = authEpoch;
  const products = Object.keys(crmProducts).filter(key=>$('#crmExportProduct-'+key).checked);
  const openStages = ['novo','contato','simulacao','negociacao'];
  if (!products.length) {status.textContent = 'Selecione pelo menos um tipo para exportar.';return;}
  if (stage && !openStages.includes(stage)) {
    status.textContent = 'Selecione uma etapa aberta para exportar.';
    return;
  }
  button.disabled = true;
  status.textContent = 'Preparando planilha…';
  const rows = [];
  let after = '', downloaded = false;
  try {
    for (;;) {
      const params = {etapa:stage ? 'eq.'+stage : 'in.('+openStages.join(',')+')',order:'id.asc',limit:500};
      params.produto = 'in.('+products.join(',')+')';
      if (after) params.id = 'gt.'+after;
      const page = await sbRequest(crmPath('crm_opportunity_cards',params));
      if (!authenticated || epoch !== authEpoch) return;
      if (!page.length) break;
      rows.push(...page);
      const next = page[page.length-1].id;
      if (!next || next <= after) throw Error('Paginação inválida');
      after = next;
    }
    if (!rows.length) {status.textContent = 'Nenhuma oportunidade aberta neste filtro.';return;}
    const sheet = XLSX.utils.aoa_to_sheet([
      ['Nome','CPF','Convênio','Produto','Etapa original','Próxima ação','Saldo Digi+','Parcela Digi+','Saque Amigoz','Margem livre'],
      ...rows.map(row => {
        const signals = row.sinais_consulta || {};
        const offers = Object.entries(signals).filter(([key,value])=>key.startsWith('amigoz_saque_') && Array.isArray(value))
          .flatMap(([,items])=>items.filter(item=>item && String(item.elegivel).toLowerCase()==='sim' && !item.erro_informado && item.valor_saque_disponivel>0));
        return [row.nome,formatCpf(row.cpf),row.convenio,crmProducts[row.produto],crmStages[row.etapa],row.proxima_acao,
          signals.digimais?.saldo ?? row.saldo_liquidacao,signals.digimais?.parcela,
          offers.map(item=>crmMoney.format(item.valor_saque_disponivel)).join(' · '),crmOpportunityMargins(signals).map(value=>crmMoney.format(value)).join(' · ')];
      })
    ]);
    const book = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(book,sheet,'Oportunidades');
    XLSX.writeFile(book,'oportunidades-'+new Date().toISOString().slice(0,10)+'.xlsx');
    downloaded = true;
    status.textContent = 'Download iniciado. Movendo oportunidades…';
    const moved = await crmRpc('crm_marcar_exportadas',{p_itens:rows.map(({id,etapa})=>({id,etapa}))});
    if (!authenticated || epoch !== authEpoch) return;
    status.textContent = rows.length+' no arquivo · '+moved+' movidas para Exportadas.'+
      (moved < rows.length ? ' As demais já mudaram de etapa.' : '');
    if (!$('#crmPipelineRows').closest('[hidden]')) await loadCrmPipeline(0);
  } catch {
    if (epoch === authEpoch) status.textContent = downloaded
      ? 'Download iniciado. Não foi possível confirmar a movimentação. Confira o Kanban.'
      : 'Não foi possível gerar a planilha.';
  } finally {button.disabled = false;}
};
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
function crmCsvCell(value){let str=String(value??'');if(/^[=+@\-\t\r]/.test(str))str="'"+str;return '"'+str.replace(/"/g,'""')+'"';}
$('#crmExport').onclick=async()=>{
  const button=$('#crmExport'),status=$('#crmStatus'),epoch=authEpoch;button.disabled=true;
  const filters={p_query:$('#crmQuery').value.trim(),p_uf:$('#crmUF').value,p_convenio:$('#crmAgreementFilter').value,p_servico:$('#crmServiceFilter').value};
  const chunks=['\uFEFFNome;CPF;Telefone;Última atividade\r\n'];let after='',total=0;
  try{
    for(;;){
      const rows=await crmRpc('crm_filter_clients',{...filters,p_after:after,p_limit:500});
      if(!authenticated||epoch!==authEpoch)throw Error('Sessão encerrada');
      if(!rows.length)break;
      chunks.push(rows.map(x=>[x.nome,formatCpf(x.cpf),x.telefone,x.ultima_atividade?new Date(x.ultima_atividade).toLocaleString('pt-BR'):''].map(crmCsvCell).join(';')).join('\r\n')+'\r\n');
      total+=rows.length;status.textContent='Exportando '+total+' clientes…';
      const next=rows[rows.length-1].cpf;if(next<=after)throw Error('Paginação inválida');after=next;
    }
    if(!total){status.textContent='Nenhum cliente corresponde aos filtros.';return;}
    const url=URL.createObjectURL(new Blob(chunks,{type:'text/csv;charset=utf-8'}));
    const link=document.createElement('a');link.href=url;link.download='clientes-'+new Date().toISOString().slice(0,10)+'.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    status.textContent=total+' clientes exportados. Filtros aplicados ao arquivo inteiro.';
  }catch{status.textContent='A exportação não foi concluída. Nenhum arquivo parcial foi baixado. Tente novamente.';}
  finally{button.disabled=false;}
};
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
  card.append(crmElement('h3','',row.nome||formatCpf(row.cpf)));
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
      tags.append(crmElement('span','crm-card-tag crm-tag-amigoz','Contrato novo'));
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
    const ok=await crmMoveOpportunity(row.id,row.etapa,request,{nome:title.value.trim()||null,proxima_acao:action.value.trim()||null,campos});
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
