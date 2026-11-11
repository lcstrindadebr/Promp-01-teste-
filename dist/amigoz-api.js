(()=>{
const amigozConfigPanel=$('#settings-amigoz-api');
amigozConfigPanel.innerHTML=`<section class="card">
 <h2>Integração Amigoz</h2><p>Configure a API e valide o login antes da primeira consulta.</p>
 <form id="amigozApiConfig">
  <label class="field" for="amigozApiUrl">URL base HTTPS</label><input id="amigozApiUrl" type="url" placeholder="https://api.exemplo.com.br" required>
  <label class="field" for="amigozApiUser">Usuário</label><input id="amigozApiUser" autocomplete="off" required maxlength="200">
  <label class="field" for="amigozApiPassword">Senha</label><input id="amigozApiPassword" type="password" autocomplete="new-password" maxlength="512"><small>Deixe em branco para manter a senha do mesmo usuário e endereço.</small>
  <div class="actions"><button class="primary" type="submit">Salvar credenciais</button><button id="amigozApiTest" type="button">Testar conexão salva</button></div>
 </form><p id="amigozConfigStatus" role="status"></p>
</section>`;
const amigozPicker=document.createElement('div');
amigozPicker.className='consultation-picker';amigozPicker.hidden=true;
amigozPicker.innerHTML=`<fieldset class="consultation-options">
 <legend>O que você quer consultar?</legend>
 <div class="consultation-options-grid">
  <label><input type="radio" name="consultationProvider" value="digimais_saldo_parcela" checked><span><strong>Digi+</strong><small>Saldo devedor e parcela</small></span></label>
  <label><input type="radio" name="consultationProvider" value="tjba_margem"><span><strong>ConsigX</strong><small>Margem consignável · Bahia (BA)</small></span></label>
  <label><input type="radio" name="consultationProvider" value="amigoz"><span><strong>Amigoz</strong><small>Saque complementar e margem</small></span></label>
 </div>
</fieldset>`;
$('#individualChoice').appendChild(amigozPicker);
let individualProvider='existing';
const amigozConsultPanel=document.createElement('section');
amigozConsultPanel.className='card amigoz-consult-card';amigozConsultPanel.hidden=true;
amigozConsultPanel.innerHTML=`<header class="amigoz-consult-heading"><h2>Consulta Amigoz</h2>
 <p>Consulte o saque complementar, a margem consignável ou ambos.</p></header>
 <form id="amigozConsultForm">
  <fieldset class="amigoz-form-group"><legend>Modalidade e convênio</legend>
   <div class="amigoz-form-fields">
    <div class="amigoz-field-wide"><label class="field" for="amigozMode">Modalidade</label><select id="amigozMode"><option value="saque">Saque complementar</option><option value="margem">Margem consignável</option><option value="ambos">Saque complementar + margem</option></select></div>
    <div><label class="field" for="amigozState">Estado</label><select id="amigozState" required><option value="">Selecione o estado</option></select></div>
    <div><label class="field" for="amigozConvenio">Convênio</label><select id="amigozConvenio" aria-describedby="amigozConvenioHint" required disabled><option value="">Selecione o estado primeiro</option></select></div>
   </div>
   <p id="amigozConvenioHint" class="muted"></p>
  </fieldset>
  <fieldset class="amigoz-form-group"><legend>Dados do cliente</legend>
   <div class="amigoz-form-fields">
    <div><label class="field" for="amigozConsultCpf">CPF</label><input id="amigozConsultCpf" inputmode="numeric" placeholder="000.000.000-00" required></div>
    <details id="amigozExtraMargin" class="amigoz-field-wide" hidden><summary>Dados adicionais (opcionais)</summary>
     <div><label class="field" for="amigozRegistration">Matrícula (opcional)</label><input id="amigozRegistration" maxlength="256"></div>
     <div id="amigozServerPasswordField" hidden><label class="field" for="amigozServerPassword">Senha do servidor (opcional)</label><input id="amigozServerPassword" type="password" autocomplete="off" maxlength="256"></div>
    </details>
   </div>
  </fieldset>
  <div class="actions"><button type="submit" class="primary">Consultar Amigoz</button><p id="amigozConsultStatus" role="status"></p></div>
 </form><div id="amigozConsultResults"></div>`;
const standardConsultCard=$('#single').closest('.card');
standardConsultCard.before(amigozConsultPanel);
const stateLabelsAmigoz={AC:'Acre',AL:'Alagoas',AM:'Amazonas',CE:'Ceará',ES:'Espírito Santo',GO:'Goiás',MA:'Maranhão',MG:'Minas Gerais',MS:'Mato Grosso do Sul',MT:'Mato Grosso',PA:'Pará',PB:'Paraíba',PE:'Pernambuco',PI:'Piauí',PR:'Paraná',RJ:'Rio de Janeiro',RN:'Rio Grande do Norte',RO:'Rondônia',RR:'Roraima',SC:'Santa Catarina',SE:'Sergipe',SP:'São Paulo',TO:'Tocantins',BR:'Federal / Nacional'};
let amigozCatalog=[],amigozBusy=false,amigozConfigBusy=false;
const amigozIsAdmin=()=>Boolean(authenticated&&currentAccess?.active&&currentAccess.role==='admin');

const amigozCanConsult=()=>Boolean(amigozIsAdmin()||(authenticated&&currentAccess?.active&&currentAccess.allow_amigoz&&!currentAccess.trial_expired));
async function amigozRequest(route,body){
 const consultationRoute=route==='consultar'||route==='convenios';
 if(!(consultationRoute?amigozCanConsult():amigozIsAdmin()))throw Error('Acesso Amigoz não liberado para esta conta.');
 await refreshSession();
 const response=await fetch('/api/admin/amigoz/'+route,{
  method:body?'POST':'GET',headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},
  ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(route === 'consultar' ? 240000 : 40000)
 });
 let value;
 try{value=await response.json();}catch{throw Error('Não foi possível acessar a API Amigoz do ApoiarCred.');}
 if(!response.ok)throw Error(value.error?.message||'Falha ao acessar a integração Amigoz.');
 return value.data;
}
// Reuse the authenticated route, quota checks and CRM persistence from the simulator.
window.consultarMargemAmigozSimulador=async function(input){
 const match=/^amigoz_([0-9]+)$/.exec(input.convenio||'');
 if(!match)throw Error('Selecione um convênio Amigoz para consultar a margem.');
 if(!amigozCanConsult())throw Error('Acesso Amigoz não liberado para esta conta.');
 if(!amigozCatalog.length)amigozCatalog=await amigozRequest('convenios');
 const convenio=amigozCatalog.find(row=>row.id===Number(match[1]));
 if(!convenio||convenio.averbadora==null)throw Error('Consulta de margem indisponível neste convênio.');
 return amigozRequest('consultar',{modo:'margem',convenio_id:convenio.id,cpf:input.cpf,
  ...(input.matricula?{numero_matricula:input.matricula}:{}),
  ...(convenio.senha_servidor&&input.senha?{senha_servidor:input.senha}:{})});
};
function updateAmigozPanel(){
 const admin=amigozIsAdmin(),home=currentPage==='home',allowed=amigozCanConsult();
 $('#settings-tab-amigoz-api').hidden=!admin;
 amigozPicker.hidden=!home||!authenticated;
 if(!allowed){
  $('#amigozConsultResults').replaceChildren();
  $('#amigozServerPassword').value='';
  individualProvider='existing';
 }
 const standard=$('#serviceSelect');
 for(const radio of amigozPicker.querySelectorAll('input')){
  const isAmigoz=radio.value==='amigoz';
  radio.disabled=isAmigoz?!allowed:![...standard.options].some(option=>option.value===radio.value&&!option.disabled);
  radio.closest('label').hidden=radio.disabled;
  radio.checked=radio.value===(individualProvider==='amigoz'?'amigoz':standard.value);
 }
 const showing=allowed&&home&&individualProvider==='amigoz';
 amigozConsultPanel.hidden=!showing;
 standardConsultCard.hidden=showing;
 $('#home').classList.toggle('individual-amigoz',showing);
 $('#results').hidden=showing;
 $('#consultationSummaryTitle').textContent=standard.value==='tjba_margem'?'Resumo ConsigX':'Resumo Digi+';
 $('#home').classList.toggle('individual-picker-ready',!amigozPicker.hidden);
 $('#home').classList.toggle('individual-consigx',!showing&&standard.value==='tjba_margem');
 $('#serviceContext').classList.toggle('amigoz-context-hidden',showing);
}
const amigozPreviousAccess=applyAccessUi;
applyAccessUi=function(){amigozPreviousAccess();updateAmigozPanel();};
const amigozPreviousSettings=switchSettings;
switchSettings=function(id){
 if(id==='amigoz-api'&&!amigozIsAdmin())return;
 amigozPreviousSettings(id);
 if(id==='amigoz-api')loadAmigozConfig();
};
async function loadAmigozConfig(){
 const epoch=authEpoch;
 try{
  const value=await amigozRequest('configuracao');
  if(epoch!==authEpoch)return;
  $('#amigozApiUrl').value=value.url||'';$('#amigozApiUser').value=value.usuario||'';
  $('#amigozApiPassword').value='';
  $('#amigozConfigStatus').textContent=value.configured?'Credenciais cadastradas.':'Configure a conexão.';
 }catch(error){if(epoch===authEpoch)$('#amigozConfigStatus').textContent=error.message;}
}
async function changeAmigozConfig(route,payload,message){
 if(amigozConfigBusy)return;
 amigozConfigBusy=true;const epoch=authEpoch;
 $('#amigozConfigStatus').textContent='Aguarde…';
 try{
  await amigozRequest(route,payload);
  if(epoch===authEpoch)$('#amigozConfigStatus').textContent=message;
 }catch(error){if(epoch===authEpoch)$('#amigozConfigStatus').textContent=error.message;}
 finally{amigozConfigBusy=false;if(epoch===authEpoch)$('#amigozApiPassword').value='';}
}
$('#amigozApiConfig').onsubmit=e=>{
 e.preventDefault();
 changeAmigozConfig('configuracao',{url:$('#amigozApiUrl').value.trim(),usuario:$('#amigozApiUser').value.trim(),senha:$('#amigozApiPassword').value},'Credenciais salvas.');
};
$('#amigozApiTest').onclick=()=>changeAmigozConfig('testar',{},'Login aceito pela Amigoz.');

function optionsAmigoz(select,placeholder,items){
 select.replaceChildren(new Option(placeholder,''),...items.map(([id,label])=>new Option(label,id)));
}
function updateAmigozConvenio(){
 const convenio=amigozCatalog.find(row=>String(row.id)===$('#amigozConvenio').value);
 const wantsMargin=$('#amigozMode').value!=='saque',available=Boolean(convenio&&convenio.averbadora!=null);
 $('#amigozExtraMargin').hidden=!wantsMargin||!available;
 $('#amigozRegistration').required=false;
 $('#amigozServerPasswordField').hidden=!wantsMargin||!available||!convenio.senha_servidor;
 $('#amigozServerPassword').required=false;
 if($('#amigozServerPasswordField').hidden)$('#amigozServerPassword').value='';
 const products=convenio?.produtos.map(p=>`${p.produto} (produto ${p.codigo_produto}, margem ${p.tipo_margem})`).join(' · ');
 $('#amigozConvenioHint').textContent=[wantsMargin&&convenio&&!available?'Margem indisponível. O catálogo não informa a averbadora.':'',products].filter(Boolean).join(' ');
}
$('#amigozState').onchange=()=>{
 const uf=$('#amigozState').value;
 optionsAmigoz($('#amigozConvenio'),uf?'Selecione o convênio':'Selecione o estado primeiro',amigozCatalog.filter(row=>row.uf===uf).map(row=>[row.id,row.nome]));
 $('#amigozConvenio').disabled=!uf;$('#amigozConvenio').onchange();
};
$('#amigozConvenio').onchange=()=>{$('#amigozRegistration').value='';$('#amigozServerPassword').value='';updateAmigozConvenio();};
$('#amigozMode').onchange=updateAmigozConvenio;
$('#amigozConsultCpf').onblur=e=>{e.target.value=formatCpf(digits(e.target.value));};
amigozPicker.onchange=async e=>{
 const choice=e.target.value;
 individualProvider=choice==='amigoz'?'amigoz':'existing';
 if(individualProvider==='existing'){
  $('#serviceSelect').value=choice;
  $('#serviceSelect').onchange?.();
 }
 updateAmigozPanel();
 if(individualProvider!=='amigoz'||amigozCatalog.length)return;
 const epoch=authEpoch;
 try{
  const list=await amigozRequest('convenios');
  if(epoch!==authEpoch)return;
  amigozCatalog=list;
  const states=[...new Set(list.map(row=>row.uf))].map(uf=>[uf,stateLabelsAmigoz[uf]||uf]).sort((a,b)=>a[1].localeCompare(b[1],'pt-BR'));
  optionsAmigoz($('#amigozState'),'Selecione o estado',states);
  $('#amigozConsultStatus').textContent='';
 }catch(error){if(epoch===authEpoch)$('#amigozConsultStatus').textContent=error.message;}
};
function showAmigozResult(result){
 const output=$('#amigozConsultResults');output.replaceChildren();
 for(const [key,title] of [['saque','Saque complementar'],['margem','Consulta de margem']]){
  const value=result[key];if(!value)continue;
  const section=document.createElement('section'),heading=document.createElement('h3');
  heading.textContent=title;section.appendChild(heading);output.appendChild(section);
  if(value.status!=='respondido'){const p=document.createElement('p');p.textContent=value.mensagem;section.appendChild(p);continue;}
  if(key==='saque'){
   const {ofertas,total_sem_correspondencia}=value.dados;
   const p=document.createElement('p');p.textContent=ofertas.length?`${ofertas.length} resultado(s) associado(s) ao convênio selecionado.`:'Nenhum resultado foi associado com segurança ao convênio selecionado.';
   if(total_sem_correspondencia)p.textContent+=` ${total_sem_correspondencia} resultado(s) sem correspondência.`;
   section.appendChild(p);
   const labels={elegivel:'Elegibilidade',valor_saque_disponivel:'Saque disponível',valor_saque_minimo:'Saque mínimo',limite_cartao:'Limite do cartão',limite_disponivel_cliente:'Limite disponível',status:'Status',nome_oferta:'Oferta',erro_informado:'Erro informado pela Amigoz'};
   const money=new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'});
   for(const offer of ofertas){
    const list=document.createElement('dl');
    for(const [field,label] of Object.entries(labels)){
     if(offer[field]==null)continue;
     const dt=document.createElement('dt'),dd=document.createElement('dd');
     dt.textContent=label;dd.textContent=field==='erro_informado'?(offer[field]?'Sim':'Não'):typeof offer[field]==='number'?money.format(offer[field]):String(offer[field]);list.append(dt,dd);
    }
    section.appendChild(list);
   }
  }else{
   const p=document.createElement('p');p.textContent='Retorno da Amigoz para conferência durante a homologação.';
   const pre=document.createElement('pre');pre.textContent=JSON.stringify(value.dados,null,2);section.append(p,pre);
  }
 }
}
$('#amigozConsultForm').onsubmit=async e=>{
 e.preventDefault();if(amigozBusy)return;
 const epoch=authEpoch,button=e.target.querySelector('button');
 const payload={modo:$('#amigozMode').value,convenio_id:Number($('#amigozConvenio').value),cpf:$('#amigozConsultCpf').value};
 if(!$('#amigozExtraMargin').hidden)payload.numero_matricula=$('#amigozRegistration').value;
 if(!$('#amigozServerPasswordField').hidden)payload.senha_servidor=$('#amigozServerPassword').value;
 $('#amigozServerPassword').value='';$('#amigozConsultResults').replaceChildren();
 amigozBusy=true;button.disabled=true;$('#amigozConsultStatus').textContent='Consultando…';
 try{
  const result=await amigozRequest('consultar',payload);
  if(epoch!==authEpoch||!amigozCanConsult())return;
  $('#amigozConsultStatus').textContent='Resposta recebida para '+result.cpf+'.' + (result.salvo_no_historico === false ? ' Não foi possível salvar o resultado. Não repita a consulta; confira o histórico e o diagnóstico.' : result.salvo_no_historico ? ' Salva no histórico do cliente.' : '');showAmigozResult(result);
 }catch(error){if(epoch===authEpoch)$('#amigozConsultStatus').textContent=error.message;}
 finally{amigozBusy=false;button.disabled=false;if(epoch===authEpoch)refreshMyAccess(true).catch(()=>{});}
};
const previousAmigozLogout=showLogin;
showLogin=function(...args){
 amigozCatalog=[];$('#amigozConsultForm').reset();$('#amigozApiConfig').reset();individualProvider='existing';
 $('#amigozConsultResults').replaceChildren();$('#amigozConsultStatus').textContent='';$('#amigozConfigStatus').textContent='';
 optionsAmigoz($('#amigozState'),'Selecione o estado',[]);$('#amigozState').onchange();
 previousAmigozLogout(...args);updateAmigozPanel();
};
updateAmigozPanel();
})();
