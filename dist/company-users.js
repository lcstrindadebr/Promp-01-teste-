// Usuários da empresa (quem tem usuarios.gerenciar) e troca obrigatória da senha provisória.
let companyUsers=[],companyInfo=null,companyUsersBusy=false,companyUsersEpoch=0;
const companyCan=key=>Boolean(currentAccess?.active&&currentAccess.tenant?.permissions?.includes(key));

async function companyRequest(path,body){
 await refreshSession();
 const response=await fetch('/api/admin/'+path,{method:body?'POST':'GET',
  headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},
  ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(45000)});
 let data;try{data=await response.json();}catch{throw Error('A API da VPS ainda não tem esta função. Atualize a VPS pelo instalador.');}
 if(!response.ok)throw Error(data.error?.message||'Não foi possível concluir. Tente novamente.');
 return data.data;
}

// Senha provisória legível: sem caracteres ambíguos, com letras e números.
function companyTemporaryPassword(){
 const letters='abcdefghjkmnpqrstuvwxyz',upper='ABCDEFGHJKMNPQRSTUVWXYZ',digits='23456789',all=letters+upper+digits;
 const pick=set=>set[crypto.getRandomValues(new Uint32Array(1))[0]%set.length];
 const chars=[pick(upper),pick(digits),pick(letters),...Array.from({length:9},()=>pick(all))];
 for(let i=chars.length-1;i>0;i--){const j=crypto.getRandomValues(new Uint32Array(1))[0]%(i+1);[chars[i],chars[j]]=[chars[j],chars[i]];}
 return chars.join('');
}

$('#settings-users').innerHTML=`<section class="card partner-admin"><div class="heading"><div><span class="section-kicker">EMPRESA</span><h2>Usuários da empresa</h2><p>Crie acessos com senha provisória. No primeiro acesso, cada usuário define a própria senha.</p></div><button id="newCompanyUser" type="button" class="primary">Novo usuário</button></div>
<div class="partner-layout"><div><h3 id="companyUserFormTitle">Novo usuário</h3><form id="companyUserForm"><input id="companyUserId" type="hidden">
<label class="field" for="companyUserName">Nome</label><input id="companyUserName" required maxlength="160" autocomplete="off">
<div id="companyUserCredentials"><label class="field" for="companyUserEmail">E-mail de acesso</label><input id="companyUserEmail" type="email" required maxlength="254" autocomplete="off">
<label class="field" for="companyUserPassword">Senha provisória</label><div class="actions"><input id="companyUserPassword" type="text" minlength="8" maxlength="256" autocomplete="off" spellcheck="false" required><button id="companyUserGenerate" type="button">Gerar</button></div>
<small>O usuário troca esta senha no primeiro acesso.</small></div>
<label class="field" for="companyUserRole">Papel</label><select id="companyUserRole" required></select><small id="companyUserRoleHelp" class="muted"></small>
<label class="partner-check" id="companyUserActiveField" hidden><input id="companyUserActive" type="checkbox" checked> Acesso ativo</label>
<details id="companyUserOverridesPanel"><summary>Ajustar permissões deste usuário</summary><p class="muted">Por padrão vale o papel. Ajustes ficam dentro do que a empresa contratou.</p><div id="companyUserOverrides"></div></details>
<div class="actions"><button id="saveCompanyUser" class="primary">Criar usuário</button><button id="cancelCompanyUser" type="button">Limpar</button></div></form>
<p id="companyUserStatus" role="status"></p>
<div id="companyUserCreated" class="notice" hidden><strong>Envie estes dados ao usuário</strong><pre id="companyUserCreatedText" class="log-code"></pre><div class="actions"><button id="copyCompanyUserCreated" type="button">Copiar</button><button id="dismissCompanyUserCreated" type="button">Já enviei</button></div><small>A senha não fica guardada no painel.</small></div></div>
<div><div class="heading"><h3>Usuários</h3><button id="reloadCompanyUsers" type="button">Atualizar</button></div><div id="companyUserList"></div></div></div></section>`;

const companyOverrideLabel={'':'Padrão do papel',allow:'Liberar',deny:'Bloquear'};
function renderCompanyRoles(selected){
 const select=$('#companyUserRole');select.replaceChildren();
 for(const role of companyInfo?.roles||[]){
  if(role.code==='administrador'&&companyInfo.actor_role!=='administrador'&&selected!=='administrador')continue;
  select.add(new Option(role.name,role.code));
 }
 select.value=selected||'operador';syncCompanyRoleHelp();
}
function syncCompanyRoleHelp(){
 const role=(companyInfo?.roles||[]).find(r=>r.code===$('#companyUserRole').value);
 const names=new Map((companyInfo?.catalog||[]).map(p=>[p.key,p.description]));
 $('#companyUserRoleHelp').textContent=role?'Inclui: '+(role.permissions.map(k=>names.get(k)||k).join('; ')||'nenhuma permissão'):'';
 for(const row of $('#companyUserOverrides').querySelectorAll('[data-key]')){
  const base=role?.permissions.includes(row.dataset.key);
  row.querySelector('option[value=""]').textContent=companyOverrideLabel['']+(base?' (liberado)':' (bloqueado)');
 }
}
function renderCompanyOverrides(overrides={}){
 const box=$('#companyUserOverrides');box.replaceChildren();
 for(const permission of companyInfo?.catalog||[]){
  const row=document.createElement('label');row.className='field';row.dataset.key=permission.key;
  row.append(permission.description);
  const select=document.createElement('select');select.setAttribute('aria-label',permission.description);
  for(const [value,label] of Object.entries(companyOverrideLabel))select.add(new Option(label,value));
  select.value=permission.key in overrides?(overrides[permission.key]?'allow':'deny'):'';
  row.append(select);box.append(row);
 }
 syncCompanyRoleHelp();
}
function companyOverridesValue(){
 const result={};
 for(const row of $('#companyUserOverrides').querySelectorAll('[data-key]')){const v=row.querySelector('select').value;if(v)result[row.dataset.key]=v==='allow';}
 return result;
}
function clearCompanyUserForm(){
 $('#companyUserForm').reset();$('#companyUserId').value='';$('#companyUserCredentials').hidden=false;
 $('#companyUserEmail').required=$('#companyUserPassword').required=true;$('#companyUserActiveField').hidden=true;
 $('#companyUserFormTitle').textContent='Novo usuário';$('#saveCompanyUser').textContent='Criar usuário';
 $('#companyUserOverridesPanel').open=false;renderCompanyRoles('operador');renderCompanyOverrides();
}
function renderCompanyUsers(){
 const list=$('#companyUserList');
 if(!companyUsers.length){list.innerHTML='<p class="muted">Nenhum usuário.</p>';return;}
 list.innerHTML=companyUsers.map(u=>`<article class="api-token-row"><div><strong>${escapeHTML(u.name)}</strong> <span class="pill ${u.active?'ok':''}">${u.active?escapeHTML(u.role_name):'Desativado'}</span>${u.owner?' <span class="pill">Responsável</span>':''}${u.must_change_password&&u.active?' <span class="pill">Aguardando troca de senha</span>':''}</div><p class="muted">${escapeHTML(u.email)}</p>${u.user_id===currentAccess?.user_id||u.owner?'':`<div class="actions"><button type="button" data-company-edit="${escapeHTML(u.user_id)}">Editar</button><button type="button" data-company-reset="${escapeHTML(u.user_id)}">Nova senha provisória</button><button type="button" class="danger" data-company-delete="${escapeHTML(u.user_id)}">Excluir</button></div>`}</article>`).join('');
}
async function loadCompanyUsers(done=''){
 if(!authenticated||!companyCan('usuarios.gerenciar'))return;
 const epoch=authEpoch,request=++companyUsersEpoch;$('#companyUserStatus').textContent='Carregando usuários…';
 try{
  const data=await companyRequest('usuarios');if(epoch!==authEpoch||request!==companyUsersEpoch)return;
  companyInfo=data.empresa;companyUsers=data.usuarios;$('#companyUserStatus').textContent=done;
  if(!$('#companyUserId').value)clearCompanyUserForm();renderCompanyUsers();
 }catch(error){if(epoch===authEpoch)$('#companyUserStatus').textContent=error.message;}
}
function showCompanyCredentials(user,password){
 $('#companyUserCreatedText').textContent=`Acesso ao ApoiarCred\nEndereço: ${location.origin}\nE-mail: ${user.email}\nSenha provisória: ${password}\nNo primeiro acesso, você vai criar a sua senha.`;
 $('#companyUserCreated').hidden=false;
}
$('#companyUserGenerate').onclick=()=>{$('#companyUserPassword').value=companyTemporaryPassword();};
$('#companyUserRole').onchange=syncCompanyRoleHelp;
$('#newCompanyUser').onclick=$('#cancelCompanyUser').onclick=()=>{clearCompanyUserForm();$('#companyUserName').focus();};
$('#reloadCompanyUsers').onclick=loadCompanyUsers;
$('#copyCompanyUserCreated').onclick=async()=>{try{await navigator.clipboard.writeText($('#companyUserCreatedText').textContent);toast('Copiado.');}catch{toast('Não foi possível copiar. Selecione e copie o texto.');}};
$('#dismissCompanyUserCreated').onclick=()=>{$('#companyUserCreatedText').textContent='';$('#companyUserCreated').hidden=true;};
$('#companyUserList').onclick=async e=>{
 const editId=e.target.dataset.companyEdit,resetId=e.target.dataset.companyReset,deleteId=e.target.dataset.companyDelete;
 const user=companyUsers.find(u=>u.user_id===(editId||resetId||deleteId));if(!user||companyUsersBusy)return;
 if(deleteId)return openCompanyDelete(user);
 if(editId){
  clearCompanyUserForm();$('#companyUserId').value=user.user_id;$('#companyUserName').value=user.name;
  $('#companyUserCredentials').hidden=true;$('#companyUserEmail').required=$('#companyUserPassword').required=false;
  $('#companyUserActiveField').hidden=false;$('#companyUserActive').checked=user.active;
  renderCompanyRoles(user.role);renderCompanyOverrides(user.overrides);$('#companyUserOverridesPanel').open=Object.keys(user.overrides).length>0;
  $('#companyUserFormTitle').textContent='Editar '+user.name;$('#saveCompanyUser').textContent='Salvar alterações';$('#companyUserName').focus();
  return;
 }
 if(!confirm(`Gerar nova senha provisória para ${user.name}? A senha atual deixa de valer.`))return;
 const password=companyTemporaryPassword(),epoch=authEpoch;companyUsersBusy=true;$('#companyUserStatus').textContent='Gerando senha provisória…';
 try{await companyRequest('usuarios/'+user.user_id+'/senha',{password});if(epoch!==authEpoch)return;
  showCompanyCredentials(user,password);await loadCompanyUsers('Senha provisória gerada.');}
 catch(error){if(epoch===authEpoch)$('#companyUserStatus').textContent=error.message;}
 finally{companyUsersBusy=false;}
};
$('#companyUserForm').onsubmit=async e=>{
 e.preventDefault();if(companyUsersBusy)return;
 const id=$('#companyUserId').value,epoch=authEpoch;
 const payload={name:$('#companyUserName').value.trim(),role:$('#companyUserRole').value,overrides:companyOverridesValue()};
 let password='';
 if(id)payload.active=$('#companyUserActive').checked;
 else{password=$('#companyUserPassword').value;Object.assign(payload,{email:$('#companyUserEmail').value.trim(),password});}
 companyUsersBusy=true;$('#saveCompanyUser').disabled=true;$('#companyUserStatus').textContent=id?'Salvando…':'Criando usuário…';
 try{
  const user=await companyRequest(id?'usuarios/'+id:'usuarios',payload);if(epoch!==authEpoch)return;
  clearCompanyUserForm();if(!id)showCompanyCredentials(user,password);
  await loadCompanyUsers(id?'Usuário atualizado.':'Usuário criado.');
 }catch(error){if(epoch===authEpoch)$('#companyUserStatus').textContent=error.message;}
 finally{$('#companyUserPassword').value='';companyUsersBusy=false;$('#saveCompanyUser').disabled=false;}
};

// Excluir usuário: apaga a conta e tudo o que ele criou. Confirmação digitando EXCLUIR.
const companyDeleteDialog=document.createElement('dialog');companyDeleteDialog.id='companyDeleteDialog';
companyDeleteDialog.setAttribute('aria-labelledby','companyDeleteTitle');
companyDeleteDialog.innerHTML=`<form id="companyDeleteForm"><h2 id="companyDeleteTitle">Excluir usuário</h2><p id="companyDeleteText"></p>
<p class="muted">As consultas, campanhas, clientes e cartões que ele criou serão apagados e não podem ser recuperados. Etapas do funil, acesso ConsigX e webhooks que ele cadastrou continuam na empresa.</p>
<label class="field" for="companyDeleteConfirm">Digite EXCLUIR para confirmar</label><input id="companyDeleteConfirm" autocomplete="off" required>
<p id="companyDeleteStatus" role="status"></p><div class="actions"><button id="companyDeleteSave" class="danger">Excluir usuário</button><button type="button" id="companyDeleteCancel">Cancelar</button></div></form>`;
document.body.append(companyDeleteDialog);
$('#companyDeleteCancel').onclick=()=>companyDeleteDialog.close();
function openCompanyDelete(user){
 $('#companyDeleteForm').reset();$('#companyDeleteForm').dataset.user=user.user_id;
 $('#companyDeleteText').textContent=`${user.name} (${user.email}) perde o acesso na hora.`;$('#companyDeleteStatus').textContent='';
 companyDeleteDialog.showModal();
}
$('#companyDeleteForm').onsubmit=async e=>{
 e.preventDefault();const epoch=authEpoch,id=e.target.dataset.user;
 if($('#companyDeleteConfirm').value.trim()!=='EXCLUIR'){$('#companyDeleteStatus').textContent='Digite EXCLUIR, em maiúsculas, para confirmar.';return;}
 companyUsersBusy=true;$('#companyDeleteSave').disabled=true;$('#companyDeleteStatus').textContent='Excluindo…';
 try{
  const r=await companyRequest('usuarios/'+id+'/excluir',{confirmacao:'EXCLUIR'});if(epoch!==authEpoch)return;
  companyDeleteDialog.close();if($('#companyUserId').value===id)clearCompanyUserForm();await loadCompanyUsers(`Usuário excluído, com ${r.registros} registros.`);
 }catch(error){if(epoch===authEpoch)$('#companyDeleteStatus').textContent=error.message;}
 finally{companyUsersBusy=false;$('#companyDeleteSave').disabled=false;}
};

// Primeiro acesso: a senha provisória precisa ser trocada antes de usar o painel.
const passwordDialog=document.createElement('dialog');passwordDialog.id='firstPasswordDialog';
passwordDialog.setAttribute('aria-labelledby','firstPasswordTitle');
passwordDialog.innerHTML=`<form id="firstPasswordForm"><h2 id="firstPasswordTitle">Crie a sua senha</h2><p class="muted">Você entrou com uma senha provisória. Defina uma senha só sua para continuar.</p>
<label class="field" for="firstPasswordNew">Nova senha</label><input id="firstPasswordNew" type="password" minlength="8" maxlength="256" autocomplete="new-password" required>
<label class="field" for="firstPasswordConfirm">Repita a nova senha</label><input id="firstPasswordConfirm" type="password" minlength="8" maxlength="256" autocomplete="new-password" required>
<p id="firstPasswordStatus" role="status"></p><div class="actions"><button id="firstPasswordSave" class="primary">Salvar senha</button><button id="firstPasswordLogout" type="button">Sair</button></div></form>`;
document.body.append(passwordDialog);
passwordDialog.addEventListener('cancel',e=>e.preventDefault());
$('#firstPasswordLogout').onclick=()=>{passwordDialog.close();$('#logout').click();};
$('#firstPasswordForm').onsubmit=async e=>{
 e.preventDefault();const password=$('#firstPasswordNew').value,epoch=authEpoch;
 if(password!==$('#firstPasswordConfirm').value){$('#firstPasswordStatus').textContent='As senhas não conferem.';return;}
 $('#firstPasswordSave').disabled=true;$('#firstPasswordStatus').textContent='Salvando…';
 try{
  await companyRequest('minha-senha',{password});if(epoch!==authEpoch)return;
  if(currentAccess){currentAccess.must_change_password=false;if(currentAccess.tenant)currentAccess.tenant.must_change_password=false;}
  $('#firstPasswordForm').reset();$('#firstPasswordStatus').textContent='';passwordDialog.close();toast('Senha criada. Use-a nos próximos acessos.');
 }catch(error){if(epoch===authEpoch)$('#firstPasswordStatus').textContent=error.message;}
 finally{$('#firstPasswordSave').disabled=false;}
};

function syncCompanyUsersUi(){
 // Importar base de clientes só aparece para quem tem a permissão (o banco também confere).
 const importButton=$('#crmImportClients');
 if(importButton)importButton.hidden=!!currentAccess&&currentAccess.role!=='admin'&&!!currentAccess.tenant&&!companyCan('clientes.importar');
 const allowed=companyCan('usuarios.gerenciar');
 $('#settings-tab-users').hidden=!allowed;
 if(!allowed&&!$('#settings-users').hidden)switchSettings('account');
 if(authenticated&&currentAccess?.must_change_password){if(!passwordDialog.open)passwordDialog.showModal();}
 else if(passwordDialog.open)passwordDialog.close();
}
function resetCompanyUsers(){
 companyUsersEpoch++;companyUsers=[];companyInfo=null;$('#companyUserList').innerHTML='';$('#companyUserStatus').textContent='';
 $('#companyUserCreatedText').textContent='';$('#companyUserCreated').hidden=true;$('#companyUserForm').reset();
 $('#settings-tab-users').hidden=true;$('#firstPasswordForm').reset();if(passwordDialog.open)passwordDialog.close();if(companyDeleteDialog.open)companyDeleteDialog.close();
}
const companyBaseApply=applyAccessUi;
applyAccessUi=function(){companyBaseApply();syncCompanyUsersUi();};
const companyBaseReset=resetPartnerSettings;
resetPartnerSettings=function(){companyBaseReset();resetCompanyUsers();};
const companyBaseSwitch=switchSettings;
switchSettings=function(id){companyBaseSwitch(id);if(id==='users')loadCompanyUsers();};
$('#settings-tab-users').hidden=true;
