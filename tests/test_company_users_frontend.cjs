const fs=require('fs'),vm=require('vm'),assert=require('assert');const {setup}=require('./test_frontend.cjs');
const json=(data,status=200)=>({ok:status<400,status,json:async()=>data,text:async()=>JSON.stringify(data)});
(async()=>{
 const t=setup();const run=code=>vm.runInContext(code,t.ctx);
 run('function loadAmigozTables(){};function tickMonitoring(){};function loadApiTokens(){};function loadApiDocs(){};');
 run(fs.readFileSync('dist/settings.js','utf8'));
 run('function applyAccessUi(){};function resetPartnerSettings(){};');
 run(fs.readFileSync('dist/company-users.js','utf8'));
 run("authenticated=true;session={access_token:'fixture',expires_at:Date.now()/1000+3600};");

 // Without usuarios.gerenciar the tab stays hidden and nothing is requested.
 run("currentAccess={user_id:'me',active:true,role:'partner',tenant:{permissions:['consulta.digimais.individual']}};applyAccessUi()");
 assert.equal(t.get('#settings-tab-users').hidden,true);
 assert.equal(t.get('#crmImportClients').hidden,true,'Import hidden without clientes.importar');
 run("currentAccess.tenant.permissions.push('clientes.importar');applyAccessUi()");
 assert.equal(t.get('#crmImportClients').hidden,false,'Import shown with clientes.importar');
 const before=t.calls.length;await run('loadCompanyUsers()');assert.equal(t.calls.length,before);

 // Administrator: lists users and creates one with a temporary password.
 const empresa={actor_role:'administrador',roles:[
  {code:'administrador',name:'Administrador',permissions:['clientes.exportar','usuarios.gerenciar']},
  {code:'gestor',name:'Gestor',permissions:['clientes.exportar']},{code:'operador',name:'Operador',permissions:[]},{code:'leitura',name:'Leitura',permissions:[]}],
  catalog:[{key:'clientes.exportar',description:'Exportar clientes'},{key:'usuarios.gerenciar',description:'Gerenciar usuários'}]};
 const users=[{user_id:'me',name:'Dono',email:'dono@x.invalid',role:'administrador',role_name:'Administrador',active:true,owner:true,overrides:{}},
  {user_id:'11111111-1111-1111-1111-111111111111',name:'Op',email:'op@x.invalid',role:'operador',role_name:'Operador',active:true,must_change_password:true,overrides:{}}];
 t.handler(async(url,options)=>{
  if(String(url)==='/api/admin/usuarios'&&!options.body)return json({data:{empresa,usuarios:users}});
  if(String(url)==='/api/admin/usuarios')return json({data:{...JSON.parse(options.body),user_id:'22222222-2222-2222-2222-222222222222'}},201);
  return json({data:{}});
 });
 run("currentAccess.tenant.permissions.push('usuarios.gerenciar');applyAccessUi()");
 assert.equal(t.get('#settings-tab-users').hidden,false);
 await run("switchSettings('users')");await new Promise(setImmediate);
 assert.match(t.get('#companyUserList').textContent,/Aguardando troca de senha/);
 assert.equal(t.get('#companyUserList').querySelectorAll('[data-company-edit]').length,1,'Own account and owner are not editable');
 run("$('#companyUserGenerate').click()");
 const temporary=t.get('#companyUserPassword').value;
 assert.match(temporary,/^(?=.*[0-9])(?=.*[A-Z])[A-Za-z0-9]{12}$/);
 t.get('#companyUserName').value='Nova Pessoa';t.get('#companyUserEmail').value='nova@x.invalid';t.get('#companyUserRole').value='gestor';
 t.get('#companyUserOverrides').querySelector('[data-key="clientes.exportar"] select').value='deny';
 await t.get('#companyUserForm').onsubmit({preventDefault(){}});
 const sent=t.calls.find(([url,options])=>url==='/api/admin/usuarios'&&options.body);
 assert.deepEqual(JSON.parse(sent[1].body),{name:'Nova Pessoa',role:'gestor',overrides:{'clientes.exportar':false},email:'nova@x.invalid',password:temporary});
 assert.equal(t.get('#companyUserCreated').hidden,false);
 assert.match(t.get('#companyUserCreatedText').textContent,new RegExp('Senha provisória: '+temporary));
 assert.equal(t.get('#companyUserPassword').value,'','Password field cleared after creating');
 assert.equal(t.get('#companyUserStatus').textContent,'Usuário criado.','Message survives the list reload');

 // A Gestor with user management cannot pick Administrador.
 run("companyInfo={...companyInfo,actor_role:'gestor'};renderCompanyRoles('operador')");
 assert.ok(![...t.get('#companyUserRole').options].some(o=>o.value==='administrador'));

 // First access: a dialog that cannot be dismissed until the password is changed.
 run("currentAccess.must_change_password=true;applyAccessUi()");
 assert.equal(t.get('#firstPasswordDialog').open,true);
 t.get('#firstPasswordNew').value='Minha-senha-1';t.get('#firstPasswordConfirm').value='Outra-senha-1';
 await t.get('#firstPasswordForm').onsubmit({preventDefault(){}});
 assert.match(t.get('#firstPasswordStatus').textContent,/não conferem/);assert.equal(t.get('#firstPasswordDialog').open,true);
 t.get('#firstPasswordConfirm').value='Minha-senha-1';
 await t.get('#firstPasswordForm').onsubmit({preventDefault(){}});
 const change=t.calls.at(-1);assert.equal(change[0],'/api/admin/minha-senha');assert.deepEqual(JSON.parse(change[1].body),{password:'Minha-senha-1'});
 assert.equal(t.get('#firstPasswordDialog').open,false);assert.equal(run('currentAccess.must_change_password'),false);

 // Delete a user: typed confirmation, then the API call.
 let deleted=null;
 t.handler(async(url,options)=>{
  if(String(url).endsWith('/excluir')){deleted=[String(url),JSON.parse(options.body)];return json({data:{registros:7,conta_removida:true}});}
  if(String(url)==='/api/admin/usuarios')return json({data:{empresa,usuarios:users}});
  return json({data:{}});
 });
 await run('loadCompanyUsers()');
 t.get('#companyUserList').querySelector('[data-company-delete]').click();
 assert.equal(t.get('#companyDeleteDialog').open,true);
 t.get('#companyDeleteConfirm').value='excluir';
 await t.get('#companyDeleteForm').onsubmit({preventDefault(){},target:t.get('#companyDeleteForm')});
 assert.equal(deleted,null,'Lowercase confirmation must not delete');assert.match(t.get('#companyDeleteStatus').textContent,/EXCLUIR/);
 t.get('#companyDeleteConfirm').value='EXCLUIR';
 await t.get('#companyDeleteForm').onsubmit({preventDefault(){},target:t.get('#companyDeleteForm')});
 assert.deepEqual(deleted,['/api/admin/usuarios/11111111-1111-1111-1111-111111111111/excluir',{confirmacao:'EXCLUIR'}]);
 assert.equal(t.get('#companyDeleteDialog').open,false);assert.match(t.get('#companyUserStatus').textContent,/7 registros/);

 // Logout clears everything.
 run('resetPartnerSettings()');
 assert.equal(t.get('#companyUserList').innerHTML,'');assert.equal(t.get('#settings-tab-users').hidden,true);
 console.log('company users frontend ok');
})().catch(error=>{console.error(error);process.exit(1);});
