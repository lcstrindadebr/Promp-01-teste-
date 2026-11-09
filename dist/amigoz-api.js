const amigozConfigPanel=$('#settings-amigoz-api');
amigozConfigPanel.innerHTML=`<section class="card">
 <h2>Integração Amigoz</h2><p>Configure a API e valide o login e o Corban antes da primeira consulta.</p>
 <form id="amigozApiConfig">
  <label class="field" for="amigozApiUrl">URL base HTTPS</label><input id="amigozApiUrl" type="url" placeholder="https://api.exemplo.com.br" required>
  <label class="field" for="amigozApiUser">Usuário</label><input id="amigozApiUser" autocomplete="off" required maxlength="200">
  <label class="field" for="amigozApiPassword">Senha</label><input id="amigozApiPassword" type="password" autocomplete="new-password" maxlength="512"><small>Deixe em branco para manter a senha do mesmo usuário e endereço.</small>
  <label class="field" for="amigozApiCorban">ID do Corban</label><input id="amigozApiCorban" type="number" min="1" max="2147483647" required>
  <div class="actions"><button class="primary" type="submit">Salvar credenciais</button><button id="amigozApiTest" type="button">Testar conexão salva</button></div>
 </form><p id="amigozConfigStatus" role="status"></p>
</section>`;
const amigozPicker=document.createElement('section');
amigozPicker.className='card';amigozPicker.hidden=true;
amigozPicker.innerHTML=`<label class="field" for="individualProvider">Provedor da consulta individual</label><select id="individualProvider"><option value="existing">Digi+ / ConsigX</option><option value="amigoz">Amigoz</option></select>`;
const amigozConsultPanel=document.createElement('section');
amigozConsultPanel.className='card';amigozConsultPanel.hidden=true;
amigozConsultPanel.innerHTML=`<h2>Consulta individual Amigoz</h2>
 <form id="amigozConsultForm">
  <label class="field" for="amigozMode">O que consultar</label><select id="amigozMode"><option value="saque">Saque complementar</option><option value="margem">Margem</option><option value="ambos">Saque complementar + margem</option></select>
  <label class="field" for="amigozState">Estado</label><select id="amigozState" required><option value="">Selecione o estado</option></select>
  <label class="field" for="amigozConvenio">Convênio</label><select id="amigozConvenio" required disabled><option value="">Selecione o convênio</option></select>
  <p id="amigozConvenioHint" class="muted"></p>
  <label class="field" for="amigozConsultCpf">CPF</label><input id="amigozConsultCpf" inputmode="numeric" placeholder="000.000.000-00" required>
  <div id="amigozExtraMargin" hidden>
   <label class="field" for="amigozRegistration">Matrícula</label><input id="amigozRegistration" maxlength="256">
   <div id="amigozServerPasswordField" hidden><label class="field" for="amigozServerPassword">Senha do servidor</label><input id="amigozServerPassword" type="password" autocomplete="off" maxlength="256"></div>
  </div>
  <div class="actions"><button type="submit" class="primary">Consultar Amigoz</button></div>
 </form><p id="amigozConsultStatus" role="status"></p><div id="amigozConsultResults"></div>`;
const standardConsultCard=$('#single').closest('.card');
standardConsultCard.before(amigozPicker,amigozConsultPanel);
const stateLabelsAmigoz={AC:'Acre',AL:'Alagoas',AM:'Amazonas',CE:'Ceará',ES:'Espírito Santo',GO:'Goiás',MA:'Maranhão',MG:'Minas Gerais',MS:'Mato Grosso do Sul',MT:'Mato Grosso',PA:'Pará',PB:'Paraíba',PE:'Pernambuco',PI:'Piauí',PR:'Paraná',RJ:'Rio de Janeiro',RN:'Rio Grande do Norte',RO:'Rondônia',RR:'Roraima',SC:'Santa Catarina',SE:'Sergipe',SP:'São Paulo',TO:'Tocantins',BR:'Federal / Nacional'};
let amigozCatalog=[],amigozBusy=false,amigozConfigBusy=false;
const amigozIsAdmin=()=>Boolean(authenticated&&currentAccess?.active&&currentAccess.role==='admin');

async function amigozRequest(route,body){
 if(!amigozIsAdmin())throw Error('A consulta Amigoz está em homologação administrativa.');
 await refreshSession();
 const response=await fetch('/api/admin/amigoz/'+route,{
  method:body?'POST':'GET',headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},
  ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(40000)
 });
 let value;
 try{value=await response.json();}catch{throw Error('Não foi possível acessar a API Amigoz do ApoiarCred.');}
 if(!response.ok)throw Error(value.error?.message||'Falha ao acessar a integração Amigoz.');
 return value.data;
}
function updateAmigozPanel(){
 const admin=amigozIsAdmin(),home=currentPage==='home',enabled=admin&&home;
 $('#settings-tab-amigoz-api').hidden=!admin;
 amigozPicker.hidden=!enabled;
 const showing=enabled&&$('#individualProvider').value==='amigoz';
 amigozConsultPanel.hidden=!showing;
 standardConsultCard.hidden=showing;
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
  $('#amigozApiCorban').value=value.corban_id||'';$('#amigozApiPassword').value='';
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
 changeAmigozConfig('configuracao',{url:$('#amigozApiUrl').value.trim(),usuario:$('#amigozApiUser').value.trim(),senha:$('#amigozApiPassword').value,corban_id:Number($('#amigozApiCorban').value)},'Credenciais salvas.');
};
$('#amigozApiTest').onclick=()=>changeAmigozConfig('testar',{},'Login e seleção do Corban aceitos pela Amigoz.');

function optionsAmigoz(select,placeholder,items){
 select.replaceChildren(new Option(placeholder,''),...items.map(([id,label])=>new Option(label,id)));
}
function updateAmigozConvenio(){
 const convenio=amigozCatalog.find(row=>String(row.id)===$('#amigozConvenio').value);
 const wantsMargin=$('#amigozMode').value!=='saque',available=Boolean(convenio&&convenio.averbadora!=null);
 $('#amigozExtraMargin').hidden=!wantsMargin||!available;
 $('#amigozRegistration').required=wantsMargin&&available&&convenio.matricula_obrigatoria;
 $('#amigozServerPasswordField').hidden=!wantsMargin||!available||!convenio.senha_servidor;
 $('#amigozServerPassword').required=wantsMargin&&available&&convenio.senha_servidor;
 if($('#amigozServerPasswordField').hidden)$('#amigozServerPassword').value='';
 const products=convenio?.produtos.map(p=>`${p.produto} (produto ${p.codigo_produto}, margem ${p.tipo_margem})`).join(' · ');
 $('#amigozConvenioHint').textContent=[wantsMargin&&convenio&&!available?'Margem indisponível. O catálogo não informa a averbadora.':'',products].filter(Boolean).join(' ');
}
$('#amigozState').onchange=()=>{
 const uf=$('#amigozState').value;
 optionsAmigoz($('#amigozConvenio'),'Selecione o convênio',amigozCatalog.filter(row=>row.uf===uf).map(row=>[row.id,row.nome]));
 $('#amigozConvenio').disabled=!uf;$('#amigozConvenio').onchange();
};
$('#amigozConvenio').onchange=()=>{$('#amigozRegistration').value='';$('#amigozServerPassword').value='';updateAmigozConvenio();};
$('#amigozMode').onchange=updateAmigozConvenio;
$('#amigozConsultCpf').onblur=e=>{e.target.value=formatCpf(digits(e.target.value));};
$('#individualProvider').onchange=async()=>{
 updateAmigozPanel();
 if($('#individualProvider').value!=='amigoz'||amigozCatalog.length)return;
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
  if(epoch!==authEpoch)return;
  $('#amigozConsultStatus').textContent='Resposta recebida para '+result.cpf+'.';showAmigozResult(result);
 }catch(error){if(epoch===authEpoch)$('#amigozConsultStatus').textContent=error.message;}
 finally{amigozBusy=false;button.disabled=false;}
};
const previousAmigozLogout=showLogin;
showLogin=function(...args){
 amigozCatalog=[];$('#amigozConsultForm').reset();$('#amigozApiConfig').reset();$('#individualProvider').value='existing';
 $('#amigozConsultResults').replaceChildren();$('#amigozConsultStatus').textContent='';$('#amigozConfigStatus').textContent='';
 optionsAmigoz($('#amigozState'),'Selecione o estado',[]);$('#amigozState').onchange();
 previousAmigozLogout(...args);updateAmigozPanel();
};
updateAmigozPanel();
