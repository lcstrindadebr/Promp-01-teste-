// All data uses Supabase. The browser receives only a publishable/anon key.
const sb=window.SUPABASE_CONFIG;
const storageKey='apoiarcred-auth:'+sb.url;
let session=null,authenticated=false,refreshing=null,loadingCloud=false,authEpoch=0;
const statusNames={aguardando:'Aguardando',processando:'Processando',concluida:'Concluída',nao_localizado:'Não é cliente',nao_cliente:'Não é cliente',erro:'Erro',revisao:'Revisão'};
function showLogin(message=''){
 authenticated=false;session=null;authEpoch++;records=[];pending=[];
 sessionStorage.removeItem(storageKey);$('#appShell').hidden=true;$('#loginPage').hidden=false;
 $('#loginError').textContent=message;$('#preview').classList.add('hide');$('#file').value='';$('#import').disabled=true;render();
}
function saveSession(data){session={...data,expires_at:data.expires_at||Math.floor(Date.now()/1000)+data.expires_in};sessionStorage.setItem(storageKey,JSON.stringify(session))}
async function raw(path,options={}){
 const res=await fetch(sb.url+path,{...options,headers:{apikey:sb.key,'Content-Type':'application/json',...options.headers},signal:AbortSignal.timeout(20000)});
 const text=await res.text();let data;try{data=text?JSON.parse(text):null}catch{throw Error('Resposta inválida do Supabase.')}
 if(!res.ok){const error=Error(data?.message||data?.msg||data?.error_description||'Falha na conexão com Supabase');error.status=res.status;throw error}return data;
}
async function refreshSession(){
 if(!session)throw Error('Entre na sua conta.');if(Date.now()/1000<session.expires_at-60)return;
 if(!refreshing)refreshing=(async()=>{const epoch=authEpoch;try{const data=await raw('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:JSON.stringify({refresh_token:session.refresh_token})});if(epoch!==authEpoch)throw Error('Sessão encerrada.');saveSession(data)}catch(e){if(epoch===authEpoch&&[400,401,403].includes(e.status))showLogin('Sessão expirada. Entre novamente.');throw e}finally{refreshing=null}})();
 await refreshing;
}
async function sbRequest(path,options={}){
 if(!authenticated)throw Error('Entre na sua conta.');await refreshSession();
 try{return await raw(path,{...options,headers:{...options.headers,Authorization:'Bearer '+session.access_token}})}catch(e){if(e.status===401)showLogin('Sessão expirada. Entre novamente.');throw e}
}
async function loadCloud(){
 if(!authenticated||loadingCloud)return;loadingCloud=true;const epoch=authEpoch;
 try{const data=await sbRequest('/rest/v1/consulta_jobs?select=*&order=created_at.desc&limit=1000');if(epoch!==authEpoch)return;records=data.map(r=>({...r,date:r.consultado_em||r.created_at,status:statusNames[r.status]||r.status,saldo:r.saldo_liquidacao==null?null:Number(r.saldo_liquidacao),parcelas:r.total_parcelas}));render()}catch(e){if(authenticated)toast(e.message)}finally{loadingCloud=false}
}
async function add(items){
 if(!authenticated)throw Error('Entre na sua conta.');if(!items.length)throw Error('Selecione registros válidos.');
 const batches=await sbRequest('/rest/v1/consulta_lotes',{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify({nome:items.length===1?'Consulta individual':'Importação CSV · '+items.length+' clientes'})});
 await sbRequest('/rest/v1/consulta_jobs',{method:'POST',body:JSON.stringify(items.map(r=>({nome:r.nome,cpf:r.cpf,telefone:r.telefone,lote_id:batches[0].id,user_id:session.user.id})))});
 toast(items.length+' consulta(s) salva(s) na fila.');await loadCloud();
}
function openPanel(){authenticated=true;$('#loginPage').hidden=true;$('#appShell').hidden=false;$('#accountEmail').textContent=session.user.email;$('#authState').textContent='Conectado como '+session.user.email;$('#password').value='';$('#loginError').textContent='';loadCloud()}
$('#login').onsubmit=async e=>{
 e.preventDefault();const button=$('#loginSubmit');button.disabled=true;$('#loginError').textContent='Entrando…';
 try{const data=await raw('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email:$('#email').value.trim(),password:$('#password').value})});authEpoch++;saveSession(data);openPanel()}catch(e){showLogin(e.status===400?'E-mail ou senha inválidos. Confira também a confirmação da conta.':e.message)}finally{button.disabled=false}
};
$('#logout').onclick=async()=>{
 const token=session?.access_token;showLogin();$('#password').value='';
 if(token)try{await raw('/auth/v1/logout',{method:'POST',headers:{Authorization:'Bearer '+token}})}catch{/* The local session is already cleared. */}
};
async function restoreSession(){
 try{const stored=sessionStorage.getItem(storageKey);if(!stored)return;session=JSON.parse(stored);$('#loginError').textContent='Verificando sessão…';await refreshSession();
 const user=await raw('/auth/v1/user',{headers:{Authorization:'Bearer '+session.access_token}});session.user=user;saveSession(session);openPanel();
 }catch{showLogin('Entre novamente para acessar o sistema.')}
}
// Discard credentials from versions that did not distinguish Supabase projects.
sessionStorage.removeItem('sb-session');
restoreSession();setInterval(loadCloud,2000);
