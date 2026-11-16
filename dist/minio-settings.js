const minioAdmin=()=>Boolean(authenticated&&currentAccess?.active&&currentAccess.role==='admin');
const minioPanel=$('#settings-minio');
minioPanel.innerHTML=`<section class="card">
 <h2>Armazenamento MinIO (S3)</h2>
 <p>Configuração global para todas as contas desta instalação. Os fluxos de arquivos serão conectados em uma etapa posterior.</p>
 <form id="minioForm">
  <fieldset id="minioFields" disabled>
   <label class="field" for="minioEndpoint">Endereço HTTPS da API S3</label>
   <input id="minioEndpoint" type="url" required maxlength="512" placeholder="https://s3.exemplo.com">
   <label class="field" for="minioBucket">Bucket privado</label>
   <input id="minioBucket" required maxlength="63">
   <label class="field" for="minioRegion">Região</label>
   <input id="minioRegion" required maxlength="64" value="us-east-1">
   <label class="field" for="minioAccess">Access Key</label>
   <input id="minioAccess" type="password" autocomplete="new-password" maxlength="512">
   <label class="field" for="minioSecret">Secret Key</label>
   <input id="minioSecret" type="password" autocomplete="new-password" maxlength="512">
   <p id="minioCredentials" class="muted"></p>
   <label class="partner-check"><input id="minioEnabled" type="checkbox"> Ativar integração global</label>
   <div class="actions">
    <button id="minioTest" type="button">Testar conexão</button>
    <button class="primary" type="submit">Salvar configuração</button>
   </div>
  </fieldset>
 </form>
 <button id="minioReload" type="button">Recarregar configuração</button>
 <p id="minioStatus" role="status"></p>
</section>`;
let minioRequestId=0;

function resetMinioSettings(){
 minioRequestId++;
 $('#minioForm').reset();
 $('#minioFields').disabled=true;
 $('#minioReload').disabled=false;
 $('#minioCredentials').textContent='';
 $('#minioStatus').textContent='';
 $('#settings-tab-minio').hidden=true;
}

async function requestMinio(action){
 if(!minioAdmin())return;
 const epoch=authEpoch, requestId=++minioRequestId;
 const form=$('#minioForm'), fields=$('#minioFields'), status=$('#minioStatus');
 const reload=$('#minioReload');
 const payload=action==='load'?null:{
  endpoint:$('#minioEndpoint').value,bucket:$('#minioBucket').value,region:$('#minioRegion').value,
  access_key:$('#minioAccess').value,secret_key:$('#minioSecret').value,enabled:$('#minioEnabled').checked
 };
 const current=()=>epoch===authEpoch&&requestId===minioRequestId&&minioAdmin();
 const wasLoaded=!fields.disabled;
 fields.disabled=true;
 reload.disabled=true;
 status.textContent=action==='test'?'Testando conexão…':action==='save'?'Salvando…':'Carregando configuração…';
 let loaded=action!=='load'&&wasLoaded;
 try{
  await refreshSession();
  if(!current())return;
  const response=await fetch('/api/admin/minio'+(action==='test'?'/test':''),{
   method:payload?'POST':'GET',
   headers:{Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},
   ...(payload?{body:JSON.stringify(payload)}:{}),signal:AbortSignal.timeout(30000)
  });
  const result=await response.json();
  if(!current())return;
  if(!response.ok)throw Error(result.error?.message||'Não foi possível acessar a configuração.');
  if(action==='test'){status.textContent='A VPS conseguiu acessar o bucket.';return;}
  const config=result.data;
  form.reset();
  $('#minioEndpoint').value=config.endpoint;
  $('#minioBucket').value=config.bucket;
  $('#minioRegion').value=config.region;
  $('#minioEnabled').checked=config.enabled;
  $('#minioCredentials').textContent=config.has_credentials
   ?'Credenciais salvas. Deixe os dois campos vazios para mantê-las.'
   :'Informe as duas chaves de acesso.';
  const state=config.enabled?'Integração ativa.':'Integração desativada.';
  status.textContent=action==='save'?'Configuração salva. '+state:state;
  loaded=true;
 }catch(error){
  if(current())status.textContent=error.message;
 }finally{
  if(current()){fields.disabled=!loaded;reload.disabled=false;}
 }
}

$('#minioForm').onsubmit=event=>{event.preventDefault();requestMinio('save');};
$('#minioReload').onclick=()=>requestMinio('load');
$('#minioTest').onclick=()=>{if($('#minioForm').reportValidity())requestMinio('test');};
