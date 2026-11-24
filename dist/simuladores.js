// Simuladores por convênio.
// Cada simulador (Amigoz, AKI Capital · SIAPE e os que vierem) aparece só onde está liberado:
// nas consultas Digi+ (que não informam convênio) se marcado para elas, ou nos convênios do catálogo.
// A lista vem de public.simuladores_config; sem essa função no banco, o painel segue como antes.
// Simuladores por coeficiente abrem a janela "Simulador de valor liberado", no mesmo padrão do Amigoz,
// e calculam no banco (public.simular_coeficientes).
let simConfig=null,simConfigEpoch=-1,simConfigLoading=null,simLegacy=false;
const simProducts={cartao_beneficio:'Cartão Benefício',cartao_credito:'Cartão Crédito'};
const simMoney=v=>Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});

function loadSimuladores(force=false){
 if(!authenticated)return Promise.resolve(null);
 if(!force&&simConfigEpoch===authEpoch&&(simConfig||simLegacy))return Promise.resolve(simConfig);
 if(simConfigLoading)return simConfigLoading;
 const epoch=authEpoch;
 simConfigLoading=sbRequest('/rest/v1/rpc/simuladores_config',{method:'POST',body:'{}'})
  .then(data=>{if(epoch!==authEpoch)return null;simConfig=data;simLegacy=false;simConfigEpoch=epoch;render();if(currentPage==='settings')renderSimuladoresSettings();return data;})
  .catch(error=>{if(epoch===authEpoch&&error?.code==='PGRST202'){simLegacy=true;simConfig=null;simConfigEpoch=epoch;}return null;})
  .finally(()=>{simConfigLoading=null;});
 return simConfigLoading;
}
function simReady(){return simConfigEpoch===authEpoch&&!!simConfig;}
// Simuladores para uma origem: consulta Digi+ e/ou convênios do catálogo.
function simuladoresPara({digimais=false,convenios=[]}){
 const wanted=convenios.filter(Boolean);
 return (simConfig||[]).filter(s=>s.ativo&&((digimais&&s.consultas_digimais)||wanted.some(c=>s.convenios.includes(c))));
}
function simuladoresDaConsulta(row){
 const margin=row.servico==='tjba_margem';
 return simuladoresPara({digimais:!margin,convenios:margin?[row.convenio||'tjba']:[]});
}

// Botões nas linhas das consultas e campanhas (dentro do menu Ações).
const simLegacyAction=amigozAction;
amigozAction=function(row){
 if(['Aguardando','Processando'].includes(row.status))return '';
 if(!simReady()){loadSimuladores();return simLegacy?simLegacyAction(row):'';}
 return simuladoresDaConsulta(row).map(s=>s.tipo==='amigoz'
  ?`<button data-simulate="${escapeHTML(row.id)}">Simular ${escapeHTML(s.banco)}</button>`
  :`<button data-simulate-coef="${escapeHTML(s.codigo)}" data-job="${escapeHTML(row.id)}">Simular ${escapeHTML(s.banco)}</button>`).join('');
};
for(const selector of ['#rows','#campaignRows']){
 const previous=$(selector).onclick;
 $(selector).onclick=e=>{
  const button=e.target.closest?.('[data-simulate-coef]');
  if(!button)return previous?.(e);
  const row=findRecord(button.dataset.job);if(!row)return;
  openCoefSimulator({simulador:button.dataset.simulateCoef,jobId:row.servico==='tjba_margem'?null:row.id,
   convenio:row.servico==='tjba_margem'?(row.convenio||'tjba'):'',cpf:row.cpf,nome:row.nome,
   parcela:row.valorParcela,saldo:row.saldo});
 };
}
// Ficha do cliente no CRM: um botão por simulador liberado para os convênios do cliente.
function crmSimuladorButtons(client,convenios){
 if(!simReady()){
  if(simLegacy&&typeof openAmigozClient==='function'){
   const b=document.createElement('button');b.type='button';b.className='primary';b.textContent='Simular Amigoz';
   b.onclick=()=>openAmigozClient(client.cpf,convenios[0]||'',null,client.nome);return [b];
  }
  return [];
 }
 return simuladoresPara({convenios}).map(s=>{
  const convenio=convenios.find(c=>s.convenios.includes(c))||'';
  const b=document.createElement('button');b.type='button';b.className='primary';b.textContent='Simular '+s.banco;
  b.onclick=()=>s.tipo==='amigoz'?openAmigozClient(client.cpf,convenio,null,client.nome)
   :openCoefSimulator({simulador:s.codigo,convenio,cpf:client.cpf,nome:client.nome});
  return b;
 });
}

// Janela "Simulador de valor liberado" (simuladores por coeficiente).
const coefPanel=document.createElement('section');
coefPanel.id='coefPanel';coefPanel.className='amigoz-overlay';coefPanel.hidden=true;
coefPanel.setAttribute('role','dialog');coefPanel.setAttribute('aria-modal','true');coefPanel.setAttribute('aria-labelledby','coefTitle');
coefPanel.innerHTML=`<div class="amigoz-dialog"><header class="amigoz-header"><div><span class="section-kicker" id="coefBank"></span><h2 id="coefTitle">Simulador de valor liberado</h2><p id="coefClient"></p></div><button type="button" id="coefClose" aria-label="Fechar simulação">Fechar <span aria-hidden="true">×</span></button></header>
<div class="amigoz-body">
<form id="coefForm" class="amigoz-controls coef-controls" novalidate>
 <div><label class="field" for="coefProduto">Produto</label><select id="coefProduto"></select><small id="coefProdutoHint"></small></div>
 <div><label class="field" for="coefParcela">Parcela (R$)</label><input id="coefParcela" inputmode="decimal" autocomplete="off" placeholder="0,00"><small>Parcela atual do contrato a comprar.</small></div>
 <div class="coef-margin"><label class="portal-enable"><input id="coefUsarMargem" type="checkbox"> Adicionar margem</label><label class="field" for="coefMargem">Margem (R$)</label><input id="coefMargem" inputmode="decimal" autocomplete="off" placeholder="Bloqueado" disabled></div>
 <div><label class="field" for="coefSaldo">Saldo devedor (R$)</label><input id="coefSaldo" inputmode="decimal" autocomplete="off" placeholder="0,00"><small>Valor de quitação descontado de cada tabela.</small></div>
 <div class="amigoz-update"><button class="primary" type="submit" id="coefCalcular">Calcular</button><small id="coefBase"></small></div>
</form>
<p id="coefStale" class="notice" hidden>Os dados mudaram desde o último cálculo. Clique em Calcular para atualizar as tabelas.</p>
<div class="amigoz-results-heading"><div><h3 id="coefResultsTitle">Tabelas</h3><p>Compare o valor liberado em cada tabela.</p></div><span class="amigoz-estimate">Valores estimados</span></div>
<p id="coefStatus" role="status" class="amigoz-status"></p>
<div id="coefCards" class="amigoz-grid"></div>
<footer class="amigoz-disclaimer">Valor bruto = (parcela + margem) ÷ coeficiente da tabela, arredondado ao centavo. Valor liberado = valor bruto − saldo devedor. Valores sujeitos à confirmação do banco.</footer>
</div></div>`;
document.body.append(coefPanel);
let coefSource=null,coefLast=null,coefBusy=false,coefQueued=false,coefGeneration=0,coefReturnFocus=null;
// Aceita "1.234,56", "1234,56", "1234.56" e "R$ 1.234,56".
function simParseMoney(text){
 let s=String(text??'').replace(/[^\d.,]/g,'');if(!/\d/.test(s))return null;
 if(s.includes(','))s=s.replace(/\./g,'').replace(',','.');
 else if((s.match(/\./g)||[]).length>1||/\.\d{3}$/.test(s))s=s.replace(/\./g,'');
 const value=Number(s);return Number.isFinite(value)?Math.round(value*100)/100:null;
}
const simFormatMoney=v=>v==null||v===''?'':Number(v).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2});
function coefInputs(){
 return {produto:$('#coefProduto').value,parcela:simParseMoney($('#coefParcela').value),
  margem:$('#coefUsarMargem').checked?simParseMoney($('#coefMargem').value):0,saldo:simParseMoney($('#coefSaldo').value)||0,
  usarMargem:$('#coefUsarMargem').checked};
}
function coefSyncStale(){
 const stale=!!coefLast&&JSON.stringify(coefInputs())!==JSON.stringify(coefLast.inputs);
 $('#coefStale').hidden=!stale;$('#coefCards').classList.toggle('is-stale',stale);
}
async function openCoefSimulator({simulador,jobId=null,convenio='',cpf='',nome='',parcela=null,saldo=null}){
 await loadSimuladores();
 const sim=(simConfig||[]).find(s=>s.codigo===simulador);if(!sim)return toast('Simulador indisponível.');
 const products=Object.keys(simProducts).filter(p=>sim.tabelas.some(t=>t.ativa&&t.produto===p));
 coefSource={sim,jobId,convenio};coefLast=null;coefQueued=false;coefGeneration++;
 $('#coefBank').textContent='SIMULADOR DE VALOR LIBERADO';$('#coefTitle').textContent=sim.nome;
 $('#coefClient').textContent=[nome,cpf&&formatCpf(String(cpf).replace(/\D/g,''))].filter(Boolean).join(' · ');
 $('#coefProduto').replaceChildren(...products.map(p=>new Option(`${simProducts[p]} (${sim.tabelas.filter(t=>t.ativa&&t.produto===p).length})`,p)));
 $('#coefProdutoHint').textContent=products.length?'Cada produto tem as próprias tabelas.':'Nenhuma tabela ativa neste simulador.';
 $('#coefParcela').value=simFormatMoney(parcela);$('#coefSaldo').value=simFormatMoney(saldo);
 $('#coefUsarMargem').checked=false;$('#coefMargem').value='';$('#coefMargem').disabled=true;$('#coefMargem').placeholder='Bloqueado';
 $('#coefCards').innerHTML='';$('#coefStale').hidden=true;$('#coefBase').textContent='';
 $('#coefStatus').textContent=parcela>0?'':'Digite a parcela e clique em Calcular para ver o valor em todas as tabelas.';
 coefReturnFocus=document.activeElement;coefPanel.hidden=false;coefPanel.scrollTop=0;$('#appShell').inert=true;$('#coefClose').focus?.();
 if(parcela>0&&products.length)calculateCoef();
}
async function calculateCoef(){
 if(!coefSource)return;
 // Uma mudança durante um cálculo (ex.: trocar o produto) recalcula assim que ele termina.
 if(coefBusy){coefQueued=true;return;}
 const inputs=coefInputs();
 if(!inputs.produto)return void($('#coefStatus').textContent='Nenhuma tabela ativa neste simulador.');
 if(!(inputs.parcela>0)){$('#coefStatus').textContent='Digite o valor da parcela para calcular.';$('#coefParcela').focus();return;}
 if(inputs.usarMargem&&!(inputs.margem>0)){$('#coefStatus').textContent='A opção "Adicionar margem" está marcada, mas a margem não foi informada. Informe a margem ou desmarque a opção.';$('#coefMargem').focus();return;}
 coefBusy=true;const generation=coefGeneration,epoch=authEpoch;
 $('#coefCalcular').disabled=true;$('#coefCalcular').textContent='Calculando…';$('#coefStatus').textContent='Calculando…';
 try{
  const result=await sbRequest('/rest/v1/rpc/simular_coeficientes',{method:'POST',body:JSON.stringify({
   p_simulador:coefSource.sim.codigo,p_produto:inputs.produto,p_parcela:inputs.parcela,p_margem:inputs.margem||0,
   p_saldo:inputs.saldo,p_job_id:coefSource.jobId,p_convenio:coefSource.convenio||''})});
  if(generation!==coefGeneration||epoch!==authEpoch)return;
  coefLast={inputs,result};renderCoefResult(result);
 }catch(error){if(generation===coefGeneration&&epoch===authEpoch)$('#coefStatus').textContent=error.message;}
 finally{coefBusy=false;$('#coefCalcular').disabled=false;$('#coefCalcular').textContent='Calcular';coefSyncStale();
  if(coefQueued&&generation===coefGeneration){coefQueued=false;calculateCoef();}}
}
function renderCoefResult(result){
 const tables=result.tabelas||[],best=tables.length?Math.max(...tables.map(t=>Number(t.liberado))):null;
 $('#coefResultsTitle').textContent=`${simProducts[result.produto]}: ${tables.length} ${tables.length===1?'tabela':'tabelas'}`;
 $('#coefBase').textContent='Base de cálculo: '+simMoney(result.base)+(Number(result.margem)>0?` (parcela ${simMoney(result.parcela)} + margem ${simMoney(result.margem)})`:' (parcela, sem margem)');
 $('#coefCards').innerHTML=tables.map(t=>{
  const top=best!==null&&Number(t.liberado)===best&&best>0;
  return `<article class="card amigoz-option${top?' amigoz-best':''}"><div class="amigoz-option-top"><h4>Tabela ${escapeHTML(t.codigo)}</h4>${top?'<span class="amigoz-best-label">Maior valor liberado</span>':''}</div>
<p class="amigoz-option-term">${escapeHTML(t.nome)} · coeficiente ${escapeHTML(String(t.coeficiente).replace('.',','))}</p><dl>
<div class="amigoz-troco"><dt>Valor liberado</dt><dd class="amigoz-cash${t.saldo_maior?' amigoz-unavailable':''}">${simMoney(t.liberado)}</dd>${t.saldo_maior?'<p>Saldo devedor maior que o valor bruto.</p>':''}</div>
<div class="amigoz-amount-row"><dt>Valor bruto</dt><dd>${simMoney(t.bruto)}</dd></div>
<div class="amigoz-amount-row"><dt>Saldo devedor</dt><dd>${simMoney(result.saldo)}</dd></div></dl></article>`;
 }).join('')||'<p class="muted">Nenhuma tabela ativa para este produto.</p>';
 $('#coefStatus').textContent='Simulação atualizada. Compare as tabelas abaixo.';
}
function closeCoef(){coefPanel.hidden=true;$('#appShell').inert=false;coefGeneration++;coefReturnFocus?.focus?.();}
$('#coefClose').onclick=closeCoef;
$('#coefForm').onsubmit=e=>{e.preventDefault();calculateCoef();};
$('#coefUsarMargem').onchange=()=>{const on=$('#coefUsarMargem').checked;$('#coefMargem').disabled=!on;$('#coefMargem').placeholder=on?'0,00':'Bloqueado';if(on)$('#coefMargem').focus();coefSyncStale();};
for(const id of ['#coefParcela','#coefMargem','#coefSaldo']){
 $(id).addEventListener('input',coefSyncStale);
 $(id).addEventListener('blur',()=>{const v=simParseMoney($(id).value);$(id).value=v==null?'':simFormatMoney(v);});
}
$('#coefProduto').onchange=()=>{if(coefLast||coefBusy)calculateCoef();};
coefPanel.onkeydown=e=>{
 if(e.key==='Escape'){e.preventDefault();closeCoef();return;}
 if(e.key!=='Tab')return;
 const controls=[...coefPanel.querySelectorAll('button:not(:disabled),input:not(:disabled),select:not(:disabled)')],first=controls[0],last=controls.at(-1);
 if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}
 else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}
};

// Configurações › Simuladores (equipe ApoiarCred).
let simCatalog=null,simCatalogEpoch=-1,simSaving=false;
const simSettings=$('#settings-simuladores');
simSettings.innerHTML=`<section class="card"><div class="heading"><div><span class="section-kicker">EQUIPE APOIARCRED</span><h2>Simuladores</h2><p>Escolha em quais convênios cada simulador aparece e mantenha as tabelas de coeficiente.</p></div><button type="button" id="simReload">Atualizar</button></div><p id="simSettingsStatus" class="muted" role="status"></p><div id="simSettingsList"></div></section>`;
async function loadSimCatalog(){
 if(simCatalogEpoch===authEpoch&&simCatalog)return simCatalog;
 const epoch=authEpoch,rows=await sbRequest('/rest/v1/crm_catalogo_importacao?select=uf,codigo,nome&order=uf.asc,nome.asc');
 if(epoch===authEpoch){simCatalog=rows;simCatalogEpoch=epoch;}
 return rows;
}
async function renderSimuladoresSettings(){
 if(!(currentAccess?.role==='admin'&&currentAccess.active)||$('#settings-simuladores').hidden)return;
 const status=$('#simSettingsStatus');
 try{
  status.textContent='Carregando simuladores…';
  const [config,catalog]=await Promise.all([loadSimuladores(),loadSimCatalog()]);
  if(!config){status.textContent=simLegacy?'O banco ainda não tem os simuladores por convênio.':'Não foi possível carregar os simuladores.';return;}
  status.textContent='';
  const byUf=new Map();for(const c of catalog){if(!byUf.has(c.uf))byUf.set(c.uf,[]);byUf.get(c.uf).push(c);}
  $('#simSettingsList').innerHTML=config.map(s=>`<article class="sim-config" data-sim="${escapeHTML(s.codigo)}">
<header class="sim-config-head"><div><h3>${escapeHTML(s.nome)}</h3><p class="muted"><span data-sim-count>${s.convenios.length}</span> convênio(s) liberado(s)${s.consultas_digimais?' · consultas Digi+':''}</p></div>
<div class="sim-config-toggles"><label class="portal-enable"><input type="checkbox" data-sim-ativo ${s.ativo?'checked':''}> Ativo</label>
<label class="portal-enable"><input type="checkbox" data-sim-digimais ${s.consultas_digimais?'checked':''}> Disponível nas consultas Digi+</label></div></header>
<details class="sim-agreements"><summary>Convênios liberados</summary><input type="search" data-sim-search placeholder="Buscar convênio ou UF" aria-label="Buscar convênio">
<div class="sim-uf-list">${[...byUf].map(([uf,items])=>`<fieldset class="sim-uf" data-uf="${escapeHTML(uf)}"><legend><label><input type="checkbox" data-sim-uf> ${escapeHTML(uf)}</label></legend>${items.map(c=>`<label class="sim-agreement" data-text="${escapeHTML((uf+' '+c.nome).toLowerCase())}"><input type="checkbox" data-sim-convenio value="${escapeHTML(c.codigo)}" ${s.convenios.includes(c.codigo)?'checked':''}> ${escapeHTML(c.nome)}</label>`).join('')}</fieldset>`).join('')}</div></details>
${s.tipo==='coeficiente'?`<details class="sim-tables" open><summary>Tabelas de coeficiente (${s.tabelas.length})</summary><div class="scroll"><table><thead><tr><th>Código</th><th>Tabela</th><th>Produto</th><th>Coeficiente</th><th>Ativa</th><th></th></tr></thead><tbody data-sim-tables>${s.tabelas.map((t,i)=>simTableRow(t,i)).join('')}</tbody></table></div><button type="button" data-sim-add-table>Adicionar tabela</button></details>`:''}
<div class="actions"><button type="button" class="primary" data-sim-save>Salvar ${escapeHTML(s.nome)}</button><span class="muted" data-sim-status role="status"></span></div></article>`).join('');
  for(const card of $('#simSettingsList').querySelectorAll('.sim-config'))simSyncUfBoxes(card);
 }catch(error){status.textContent='Não foi possível carregar os simuladores: '+error.message;}
}
function simTableRow(t={codigo:'',nome:'',produto:'cartao_credito',coeficiente:'',ativa:true},i=0){
 return `<tr data-original="${escapeHTML(t.codigo)}"><td><input data-t="codigo" value="${escapeHTML(t.codigo)}" aria-label="Código da tabela"></td><td><input data-t="nome" value="${escapeHTML(t.nome)}" aria-label="Nome da tabela"></td>
<td><select data-t="produto" aria-label="Produto">${Object.entries(simProducts).map(([v,l])=>`<option value="${v}" ${t.produto===v?'selected':''}>${l}</option>`).join('')}</select></td>
<td><input data-t="coeficiente" inputmode="decimal" value="${t.coeficiente===''?'':escapeHTML(String(t.coeficiente).replace('.',','))}" aria-label="Coeficiente"></td>
<td><input type="checkbox" data-t="ativa" ${t.ativa?'checked':''} aria-label="Tabela ativa"></td><td><button type="button" class="danger" data-sim-remove-table>Remover</button></td></tr>`;
}
function simSyncUfBoxes(card){
 for(const set of card.querySelectorAll('.sim-uf')){
  const boxes=[...set.querySelectorAll('[data-sim-convenio]')],on=boxes.filter(b=>b.checked).length,head=set.querySelector('[data-sim-uf]');
  head.checked=on===boxes.length;head.indeterminate=on>0&&on<boxes.length;
 }
 card.querySelector('[data-sim-count]').textContent=card.querySelectorAll('[data-sim-convenio]:checked').length;
}
simSettings.addEventListener('change',e=>{
 const card=e.target.closest('.sim-config');if(!card)return;
 if(e.target.matches('[data-sim-uf]'))for(const b of e.target.closest('.sim-uf').querySelectorAll('[data-sim-convenio]'))b.checked=e.target.checked;
 if(e.target.matches('[data-sim-uf],[data-sim-convenio]'))simSyncUfBoxes(card);
});
simSettings.addEventListener('input',e=>{
 if(!e.target.matches('[data-sim-search]'))return;
 const q=e.target.value.trim().toLowerCase(),card=e.target.closest('.sim-config');
 for(const label of card.querySelectorAll('.sim-agreement'))label.hidden=!!q&&!label.dataset.text.includes(q);
 for(const set of card.querySelectorAll('.sim-uf'))set.hidden=![...set.querySelectorAll('.sim-agreement')].some(l=>!l.hidden);
});
simSettings.addEventListener('click',async e=>{
 if(e.target.id==='simReload'){simCatalogEpoch=-1;await loadSimuladores(true);return renderSimuladoresSettings();}
 const card=e.target.closest('.sim-config');if(!card)return;
 if(e.target.matches('[data-sim-add-table]')){card.querySelector('[data-sim-tables]').insertAdjacentHTML('beforeend',simTableRow());return;}
 if(e.target.matches('[data-sim-remove-table]')){e.target.closest('tr').remove();return;}
 if(e.target.matches('[data-sim-save]'))return saveSimulador(card);
});
async function saveSimulador(card){
 if(simSaving)return;
 const codigo=card.dataset.sim,status=card.querySelector('[data-sim-status]'),epoch=authEpoch;
 const sim=(simConfig||[]).find(s=>s.codigo===codigo);
 const rows=[...card.querySelectorAll('[data-sim-tables] tr')].map((tr,i)=>({original:tr.dataset.original,
  codigo:tr.querySelector('[data-t="codigo"]').value.trim(),nome:tr.querySelector('[data-t="nome"]').value.trim(),
  produto:tr.querySelector('[data-t="produto"]').value,coeficiente:Number(tr.querySelector('[data-t="coeficiente"]').value.trim().replace(',','.')),
  ativa:tr.querySelector('[data-t="ativa"]').checked,ordem:i+1}));
 const invalid=rows.find(r=>!r.codigo||!r.nome||!(r.coeficiente>0)||r.coeficiente>=1);
 if(invalid){status.textContent='Confira as tabelas: código, nome e coeficiente entre 0 e 1 (ex.: 0,043297241) são obrigatórios.';return;}
 if(new Set(rows.map(r=>r.codigo)).size!==rows.length){status.textContent='Há códigos de tabela repetidos.';return;}
 simSaving=true;status.textContent='Salvando…';
 try{
  await sbRequest('/rest/v1/rpc/admin_simulador_salvar',{method:'POST',body:JSON.stringify({p_codigo:codigo,
   p_ativo:card.querySelector('[data-sim-ativo]').checked,p_consultas_digimais:card.querySelector('[data-sim-digimais]').checked,
   p_convenios:[...card.querySelectorAll('[data-sim-convenio]:checked')].map(b=>b.value)})});
  if(sim?.tipo==='coeficiente'){
   const kept=new Set(rows.map(r=>r.codigo));
   for(const t of sim.tabelas)if(!kept.has(t.codigo))await sbRequest('/rest/v1/rpc/admin_simulador_tabela_excluir',{method:'POST',body:JSON.stringify({p_simulador:codigo,p_codigo:t.codigo})});
   for(const r of rows)await sbRequest('/rest/v1/rpc/admin_simulador_tabela_salvar',{method:'POST',body:JSON.stringify({p_simulador:codigo,
    p_codigo:r.codigo,p_nome:r.nome,p_produto:r.produto,p_coeficiente:r.coeficiente,p_ativa:r.ativa,p_ordem:r.ordem})});
  }
  if(epoch!==authEpoch)return;
  await loadSimuladores(true);await renderSimuladoresSettings();
  $('#simSettingsList').querySelector(`[data-sim="${codigo}"] [data-sim-status]`).textContent='Salvo.';
 }catch(error){if(epoch===authEpoch)status.textContent='Não foi possível salvar: '+error.message;}
 finally{simSaving=false;}
}

// Aba só para a equipe; o painel carrega a lista ao entrar e a limpa ao trocar de conta.
const simBaseSwitch=switchSettings;
switchSettings=function(id){simBaseSwitch(id);if(id==='simuladores')renderSimuladoresSettings();};
const simBaseAccess=applyAccessUi;
applyAccessUi=function(...args){
 simBaseAccess(...args);
 const admin=!!(currentAccess?.active&&currentAccess.role==='admin');
 $('#settings-tab-simuladores').hidden=!admin;
 if(!admin&&!$('#settings-simuladores').hidden)switchSettings('account');
 if(authenticated)loadSimuladores();
};
const simBaseShowLogin=showLogin;
showLogin=function(...args){
 simConfig=null;simLegacy=false;simConfigEpoch=-1;simCatalog=null;simCatalogEpoch=-1;
 if(!coefPanel.hidden)closeCoef();$('#simSettingsList').innerHTML='';$('#settings-tab-simuladores').hidden=true;
 return simBaseShowLogin(...args);
};
$('#settings-tab-simuladores').hidden=true;
