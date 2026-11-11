const bankTablesPanel = $('#settings-tables');
bankTablesPanel.innerHTML = `
 <section class="card">
  <h2>Tabelas</h2><p>Coeficientes, elegibilidade e comissões por convênio.</p>
  <fieldset id="bankTableControls" disabled>
   <div class="bank-table-grid">
    <label>Banco<select id="bankTableBank"><option value="amigoz">Amigoz</option></select></label>
    <label>Convênio<select id="bankTableAgreement"></select></label>
    <label>Prazo (parcelas)<input id="bankTableTerm" readonly></label>
    <label>Convênio de referência<select id="bankTableReference"></select></label>
   </div>
   <section id="bankTableEligibility" class="bank-table-eligibility"></section>
   <div id="bankTableCopy" class="bank-table-grid" hidden>
    <label>Convênio de destino<select id="bankTableDestination"></select></label>
    <div class="bank-table-actions"><button id="bankTableCopyAll" type="button">Duplicar todas as tabelas</button></div>
   </div>
   <div id="bankTableRows" class="bank-table-list"></div>
   <div class="bank-table-actions">
    <button id="bankTableSave" type="button" class="primary">Salvar tabelas</button>
    <button id="bankTableReload" type="button">Recarregar</button>
   </div>
  </fieldset>
  <p id="bankTableStatus" role="status"></p>
 </section>`;

const bankTableFields = [
 ['nome','Nome da tabela',100],['taxa','Taxa mensal (%)',100],['cet','CET mensal (%)',100],
 ['multiplicador','Multiplicador',1000],['iof_referencia','IOF de referência (R$)',140000],
 ['parcela_quitacao','Parcela de quitação (R$)',10000],['parcela_saque','Parcela de saque (R$)',10000],
 ['percentual','Comissão do vendedor (%)',100]
];
const bankTableProducts = {emprestimo:'Empréstimo',cartao:'Cartão',beneficio:'Cartão benefício',consignado:'Cartão consignado'};
let bankTableState = null, bankTableBusy = false;
const bankTableAdmin = () => Boolean(authenticated && currentAccess?.active && currentAccess.role==='admin');
const bankTableKey = (agreement,id) => agreement+'|'+id;
function bankTableSelected() {
 return bankTableState?.config.eligibilidade.find(rule=>rule.convenio===$('#bankTableAgreement').value);
}
function bankTableCommission(rule,table) {
 const key=bankTableKey(rule.convenio,table.id);
 const {commissions,legacy}=bankTableState;
 return commissions.has(key) ? commissions.get(key) : legacy.get(table.id);
}
function bankTableStatus(text) { $('#bankTableStatus').textContent=text; }

function bankTableRender(preferred) {
 const {config,catalog}=bankTableState;
 const agreement=$('#bankTableAgreement'), reference=$('#bankTableReference');
 const labels=new Map(catalog.map(row=>[row.codigo,row.nome+' · '+row.uf]));
 for(const select of [agreement,reference]){
  select.replaceChildren(...config.eligibilidade.map(rule=>
   new Option(rule.nome||labels.get(rule.convenio)||rule.convenio,rule.convenio)));
 }
 agreement.value=preferred && labels.has(preferred) && config.eligibilidade.some(rule=>rule.convenio===preferred)
  ? preferred : config.default_convenio;
 reference.value=config.default_convenio;
 reference.disabled=!bankTableAdmin();
 $('#bankTableTerm').value=config.prazo;
 $('#bankTableDestination').replaceChildren(...catalog.map(row=>new Option(row.nome+' · '+row.uf,row.codigo)));
 $('#bankTableDestination').value=agreement.value;
 bankTableRenderRows();
}

function bankTableRenderRows() {
 const rule=bankTableSelected(), admin=bankTableAdmin();
 const rows=$('#bankTableRows'), eligibility=$('#bankTableEligibility');
 rows.replaceChildren();
 eligibility.replaceChildren();
 $('#bankTableCopy').hidden=!admin||!rule;
 if(!rule)return;
 const products=document.createElement('fieldset');
 const legend=document.createElement('legend');
 legend.textContent='Produtos elegíveis';
 products.append(legend);
 for(const [key,title] of Object.entries(bankTableProducts)){
  const label=document.createElement('label'), input=document.createElement('input');
  input.type='checkbox';
  input.checked=rule.produtos.includes(key);
  input.disabled=!admin;
  input.onchange=()=>{
   rule.produtos=input.checked?[...rule.produtos,key]:rule.produtos.filter(product=>product!==key);
   bankTableState.dirty=true;
  };
  label.append(input,' '+title);
  products.append(label);
 }
 const institutionLabel=document.createElement('label'), institutions=document.createElement('input');
 institutionLabel.textContent='Instituições elegíveis, separadas por vírgula';
 institutions.value=rule.instituicoes.join(', ');
 institutions.readOnly=!admin;
 institutions.oninput=()=>{
  rule.instituicoes=institutions.value.split(',').map(value=>value.trim().toLowerCase()).filter(Boolean);
  bankTableState.dirty=true;
 };
 institutionLabel.append(institutions);
 eligibility.append(products,institutionLabel);
 for(const table of rule.tabelas){
  const card=document.createElement('article'), title=document.createElement('h3');
  const fields=document.createElement('div');
  card.className='card';
  title.textContent=table.nome;
  fields.className='bank-table-grid';
  for(const [key,labelText,max] of bankTableFields){
   const label=document.createElement('label'), input=document.createElement('input');
   label.textContent=labelText;
   input.value=(key==='percentual'?bankTableCommission(rule,table):table[key])??'';
   if(key==='nome')input.maxLength=max;
   else{
    input.type='number';
    input.inputMode='decimal';
    input.min=['taxa','multiplicador'].includes(key)?'0.01':'0';
    input.max=max;
    input.step=key==='percentual'?'0.0001':'any';
   }
   input.required=key!=='percentual';
   input.readOnly=key!=='percentual'&&!admin;
   input.oninput=()=>{
    const value=input.value.trim();
    if(key==='percentual'){
     const commissionKey=bankTableKey(rule.convenio,table.id);
     bankTableState.commissions.set(commissionKey,value===''?null:Number(value));
     bankTableState.edited.add(commissionKey);
    }else{
     table[key]=key==='nome'?value:value===''?null:Number(value);
     if(key==='nome')title.textContent=value;
     bankTableState.dirty=true;
    }
   };
   label.append(input);
   fields.append(label);
  }
  card.append(title,fields);
  if(admin){
   const actions=document.createElement('div'), copy=document.createElement('button');
   actions.className='bank-table-actions';
   copy.type='button';
   copy.textContent='Duplicar tabela';
   copy.onclick=()=>bankTableDuplicate([table]);
   actions.append(copy);
   card.append(actions);
  }
  rows.append(card);
 }
}

function bankTableDuplicate(tables) {
 if(!bankTableAdmin()||bankTableBusy)return;
 const source=bankTableSelected(), destination=$('#bankTableDestination').value;
 if(!source||!destination)return;
 const {config,catalog}=bankTableState;
 let target=config.eligibilidade.find(rule=>rule.convenio===destination);
 if((target?.tabelas.length||0)+tables.length>30){
  bankTableStatus('O convênio pode ter até 30 tabelas.');
  return;
 }
 if(!target){
  target={...structuredClone(source),convenio:destination,nome:catalog.find(row=>row.codigo===destination)?.nome,tabelas:[]};
  config.eligibilidade.push(target);
 }
 for(const table of tables){
  const copy={...table,id:crypto.randomUUID(),nome:(target===source?table.nome+' (cópia)':table.nome).slice(0,100)};
  target.tabelas.push(copy);
  const key=bankTableKey(destination,copy.id);
  bankTableState.commissions.set(key,bankTableCommission(source,table)??null);
  bankTableState.edited.add(key);
 }
 bankTableState.dirty=true;
 bankTableRender(destination);
 bankTableStatus('Cópia criada. Salve para disponibilizar no simulador.');
}

async function loadAmigozTables(preferred,force=false) {
 if(!authenticated||bankTableBusy||(!force&&bankTableState?.epoch===authEpoch))return;
 const epoch=authEpoch;
 bankTableBusy=true;
 $('#bankTableControls').disabled=true;
 bankTableStatus('Carregando tabelas…');
 try{
  const [[version],legacy,commissions,catalog]=await Promise.all([
   sbRequest('/rest/v1/amigoz_model_versions?select=id,config&order=id.desc&limit=1'),
   sbRequest('/rest/v1/amigoz_comissoes?select=taxa,percentual'),
   sbRequest('/rest/v1/amigoz_comissoes_tabela?select=convenio,tabela_id,percentual'),
   crmGetImportCatalog()
  ]);
  if(epoch!==authEpoch||!authenticated)return;
  if(!version)throw Error('Nenhuma configuração Amigoz cadastrada.');
  const config=version.config;
  for(const rule of config.eligibilidade){
   rule.tabelas ??=config.tabelas.filter(table=>rule.taxas.includes(Number(table.taxa))).map(table=>({
    ...table,id:'legacy-'+Number(table.taxa),nome:'Tabela '+Number(table.taxa).toLocaleString('pt-BR',{minimumFractionDigits:2})+'%'
   }));
  }
  bankTableState={config,version:version.id,catalog,epoch,dirty:false,edited:new Set(),
   legacy:new Map(legacy.map(row=>['legacy-'+Number(row.taxa),row.percentual])),
   commissions:new Map(commissions.map(row=>[bankTableKey(row.convenio,row.tabela_id),row.percentual]))};
  bankTableRender(preferred);
  bankTableStatus('Versão '+version.id+' · Comissão sobre dívida + troco. Campo vazio oculta a comissão.');
 }catch(error){if(epoch===authEpoch)bankTableStatus(error.message);}
 finally{
  bankTableBusy=false;
  if(epoch===authEpoch)$('#bankTableControls').disabled=!bankTableState;
 }
}
$('#bankTableAgreement').onchange=()=>{
 $('#bankTableDestination').value=$('#bankTableAgreement').value;
 bankTableRenderRows();
};
$('#bankTableReference').onchange=()=>{
 if(!bankTableAdmin())return;
 bankTableState.config.default_convenio=$('#bankTableReference').value;
 bankTableState.dirty=true;
};
$('#bankTableCopyAll').onclick=()=>{
 const rule=bankTableSelected();
 if(rule)bankTableDuplicate([...rule.tabelas]);
};
$('#bankTableReload').onclick=()=>{
 if((bankTableState?.dirty||bankTableState?.edited.size)&&!confirm('Descartar alterações ainda não salvas?'))return;
 loadAmigozTables($('#bankTableAgreement').value,true);
};
$('#bankTableSave').onclick=async()=>{
 const state=bankTableState;
 if(!state||bankTableBusy||!authenticated)return;
 if(!state.dirty&&!state.edited.size){bankTableStatus('Nenhuma alteração para salvar.');return;}
 for(const input of $('#bankTableRows').querySelectorAll('input')){
  if(!input.reportValidity())return;
 }
 const epoch=authEpoch,preferred=$('#bankTableAgreement').value;
 const commissions=[...state.edited].map(key=>{
  const [convenio,tabela_id]=key.split('|');
  return {convenio,tabela_id,percentual:state.commissions.get(key)};
 });
 if(commissions.some(row=>row.percentual!==null&&(!Number.isFinite(row.percentual)||row.percentual<0||row.percentual>100))){
  bankTableStatus('Use comissões entre 0 e 100%.');
  return;
 }
 if(state.dirty){
  for(const rule of state.config.eligibilidade)rule.taxas=[...new Set(rule.tabelas.map(table=>table.taxa))];
 }
 bankTableBusy=true;
 $('#bankTableControls').disabled=true;
 bankTableStatus('Salvando…');
 let saved=false;
 try{
  state.version=await coefficientRequest('amigoz_save_tables',{
   p_version:state.version,p_config:state.dirty&&bankTableAdmin()?state.config:null,p_comissoes:commissions
  });
  state.dirty=false;
  state.edited.clear();
  saved=epoch===authEpoch;
 }catch(error){if(epoch===authEpoch)bankTableStatus(error.message);}
 finally{
  bankTableBusy=false;
  if(epoch===authEpoch)$('#bankTableControls').disabled=false;
 }
 if(saved){
  await loadAmigozTables(preferred,true);
  if(epoch===authEpoch&&bankTableState!==state)bankTableStatus('Tabelas salvas · versão '+bankTableState.version+'.');
 }
};
const bankTablesReset=resetApiSettings;
resetApiSettings=function(){
 bankTablesReset();
 bankTableState=null;
 $('#bankTableRows').replaceChildren();
 $('#bankTableEligibility').replaceChildren();
 $('#bankTableControls').disabled=true;
 bankTableStatus('');
};
