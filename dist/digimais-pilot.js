// Admin settings are also enforced by database RPCs and queue reservations.
const digiPilot=document.createElement('section');digiPilot.className='card';digiPilot.hidden=true;
digiPilot.innerHTML=`<h2>Digi+ · API experimental</h2><p>O modo escolhido vale para novas consultas e para clientes na fila das suas campanhas Digi+.</p><form id="digiPilotForm"><label class="field" for="digiPilotMode">Modo de consulta</label><div id="digiPilotSwitch" class="digi-pilot-switch" data-api="false"><span aria-hidden="true">Robô</span><span aria-hidden="true">API</span><input id="digiPilotMode" type="range" min="0" max="1" step="1" value="0" aria-valuetext="Robô" disabled></div><p id="digiPilotActive" role="status"></p><label class="field" for="digiPilotMax">Limite de clientes simultâneos (1 a 12)</label><input id="digiPilotMax" type="number" min="1" max="12" step="1" value="12" required><label class="portal-enable"><input id="digiPilotPaused" type="checkbox"> Pausar novas execuções da API</label><p>As consultas em andamento terminam normalmente. A capacidade pode diminuir conforme CPU e RAM da VPS. As campanhas pausadas continuam pausadas até você retomar.</p><button class="primary" id="digiPilotSave">Salvar preferência</button></form><p id="digiPilotStatus" role="status"></p><div id="digiPilotMetrics"></div>`;
$('#settings-robots').prepend(digiPilot);
let digiPilotEpoch=-1, digiPilotSaved=null;
const digiPilotMode=$('#digiPilotMode');
function renderDigiPilotMode(){
 const api=digiPilotMode.value==='1';
 const selected=api?'API':'Robô';
 $('#digiPilotSwitch').dataset.api=String(api);
 digiPilotMode.setAttribute('aria-valuetext',selected);
 const saved=digiPilotSaved;
 $('#digiPilotActive').textContent=saved
  ? 'Modo ativo: '+(saved.mode==='api'?(saved.paused?'API · pausada':'API'):'Robô')+
    (api!==(saved.mode==='api')?' · '+selected+' selecionado. Salve para aplicar.':'')
  : 'Carregando modo ativo…';
}
digiPilotMode.oninput=renderDigiPilotMode;
function showSavedDigiPilot(preference){
 digiPilotSaved=preference;
 digiPilotMode.value=preference.mode==='api'?'1':'0';
 renderDigiPilotMode();
}
async function loadDigiPilot(){
 digiPilot.hidden=!(authenticated&&currentAccess?.active&&currentAccess.role==='admin');
 if(digiPilot.hidden)return;
 const epoch=authEpoch;$('#digiPilotSave').disabled=true;digiPilotMode.disabled=true;
 try{const p=await sbRequest('/rest/v1/rpc/manage_digimais_pilot',{method:'POST',body:JSON.stringify({})});if(epoch!==authEpoch)return;
 showSavedDigiPilot(p);$('#digiPilotMax').value=p.max_concurrency;$('#digiPilotPaused').checked=p.paused;digiPilotEpoch=epoch;$('#digiPilotStatus').textContent='Preferência exclusiva da sua conta.';
 }catch{if(epoch===authEpoch)$('#digiPilotStatus').textContent='Não foi possível carregar o piloto. Verifique a atualização do banco.';}
 finally{if(epoch===authEpoch)digiPilotMode.disabled=$('#digiPilotSave').disabled=digiPilotEpoch!==epoch;}
}
$('#digiPilotForm').onsubmit=async e=>{e.preventDefault();if(currentAccess?.role!=='admin'||digiPilotEpoch!==authEpoch)return;const epoch=authEpoch;$('#digiPilotSave').disabled=true;digiPilotMode.disabled=true;
 try{const saved=await sbRequest('/rest/v1/rpc/manage_digimais_pilot',{method:'POST',body:JSON.stringify({p_mode:digiPilotMode.value==='1'?'api':'robot',p_paused:$('#digiPilotPaused').checked,p_max:Number($('#digiPilotMax').value)})});if(epoch===authEpoch){showSavedDigiPilot(saved);$('#digiPilotStatus').textContent='Preferência salva. Os clientes na fila das suas campanhas já usam o modo escolhido.';}}
 catch(e){if(epoch===authEpoch)$('#digiPilotStatus').textContent=e.message||'Não foi possível salvar.';}
 finally{if(epoch===authEpoch)digiPilotMode.disabled=$('#digiPilotSave').disabled=false;}
};
const digiPilotAccess=applyAccessUi;applyAccessUi=function(){digiPilotAccess();digiPilot.hidden=!(authenticated&&currentAccess?.active&&currentAccess.role==='admin');if(!digiPilot.hidden&&digiPilotEpoch!==authEpoch)loadDigiPilot();};
const digiPilotSettings=switchSettings;switchSettings=function(id){digiPilotSettings(id);if(id==='robots')loadDigiPilot();};
const digiPilotReset=resetApiSettings;resetApiSettings=function(){digiPilotReset();digiPilotEpoch=-1;digiPilotSaved=null;digiPilot.hidden=true;$('#digiPilotMetrics').textContent='';};
const digiPilotMonitoring=renderMonitoring;renderMonitoring=function(){digiPilotMonitoring();if(digiPilot.hidden)return;const r=monitoringSnapshot?.payload?.robots,slots=r?.api_slots||[];
 const sum=k=>slots.reduce((n,s)=>n+(Number(s[k])||0),0),total=sum('finished_last_hour');
 const average=total?slots.reduce((n,s)=>n+(s.average_seconds||0)*(s.finished_last_hour||0),0)/total:null;
 const stale=Date.now()-Date.parse(r?.updated_at||'')>20000||!r;
 $('#digiPilotMetrics').textContent=(stale?'Métricas indisponíveis ou desatualizadas. ':'')+`Capacidade da VPS: ${r?.api_capacity||0}/12 · Em execução: ${slots.filter(s=>['consulting','saving'].includes(s.state)).length} · Última hora: ${total} clientes · Saldo e parcela preenchidos: ${sum('complete_values_last_hour')} · Sem ambos os valores: ${sum('missing_values_last_hour')} · HTTP 429: ${sum('rate_limited_last_hour')} · Revisão: ${sum('review_last_hour')} · Tempo médio: ${robotDuration(average)}. Métricas globais do piloto desde o reinício do executor.`;
};

// Separate own-account API diagnostics; never render cookies or API configuration.
const digiApiLog=document.createElement('section');digiApiLog.className='card';digiApiLog.hidden=true;
digiApiLog.innerHTML='<h2>Log DigiMais · API</h2><p>Tentativas encerradas da API, incluindo consultas encaminhadas ao robô. Veja as etapas e os motivos de interrupção nos 50 registros carregados mais recentes do filtro.</p><label class="field" for="digiApiLogSlot">Executor API</label><select id="digiApiLogSlot"><option value="">Todos</option>'+Array.from({length:12},(_,i)=>'<option value="'+(i+1)+'">API '+(i+1)+'</option>').join('')+'<option value="unassigned">Ainda sem executor</option></select><div class="log-actions"><span id="digiApiLogContentCount" class="muted"></span><button id="digiApiLogContentCopy" type="button" disabled>Copiar</button><button id="digiApiLogContentDownload" type="button" disabled>Baixar TXT</button></div><pre class="log-code" tabindex="0" aria-label="Registros de consulta"><code id="digiApiLogContent"></code></pre>';
$('#settings-digimais-api').append(digiApiLog);
const showDigiApiLog = createConsultationLog('digiApiLogContent', 'log-digimais-api', 'Nenhuma consulta via API para este filtro.');
let digiLogRequest=0,digiLogRows=[];
async function renderDigiApiLogs(){
 const allowed=authenticated&&currentAccess?.active&&currentAccess.role==='admin';
 digiApiLog.hidden=!allowed;
 $('#settings-tab-digimais-api').hidden=!allowed;
 if(!allowed&&!$('#settings-digimais-api').hidden)switchSettings('account');
 if(!allowed||currentPage!=='settings'||$('#settings-digimais-api').hidden){
  digiLogRequest++;digiLogRows=[];showDigiApiLog([],false);return;
 }
 const slot=$('#digiApiLogSlot').value;
 const selected=records.filter(r=>{
  if(!r.api_handoff&&!(r.execution_mode==='api'&&consultationWasPerformed(r)))return false;
  const executor=r.api_handoff?.api_slot??r.api_slot;
  return !slot||(slot==='unassigned'?executor==null:String(executor)===slot);
 }).sort((a,b)=>Date.parse(b.api_handoff?.date||b.date)-Date.parse(a.api_handoff?.date||a.date)).slice(0,50);
 if(selected.length&&selected.length===digiLogRows.length&&selected.every((row,index)=>row===digiLogRows[index]))return;
 digiLogRows=selected;
 const request=++digiLogRequest,epoch=authEpoch;
 showDigiApiLog([],false);
 $('#digiApiLogContent').textContent='Carregando logs…';
 const loaded=await Promise.allSettled(selected.map(loadConsultationLogDetail));
 if(request!==digiLogRequest||epoch!==authEpoch||!amigozIsAdmin()||currentPage!=='settings'||$('#settings-digimais-api').hidden)return;
 const rows=loaded.map((entry,index)=>{
  const row=entry.status==='fulfilled'?entry.value:selected[index];
  return row.api_handoff?{...row,...row.api_handoff,status:'Encaminhada ao robô',progress:100,stage:''}:row;
 });
 if(loaded.some(entry=>entry.status==='rejected'))digiLogRows=[];
 showDigiApiLog(rows.map(r=>{
  const lines=[`${new Date(r.date).toLocaleString('pt-BR')} | ${r.api_slot?'API '+r.api_slot:'Ainda sem executor'} | CPF: ${r.cpf} | ${statusLabel(r.status)} | ${Number(r.progress)||0}%`,r.lote_id?'Campanha: '+r.lote_id:'Consulta individual',r.stage,r.message];
  for(const [key,label,value] of [['resultado_saldo','Saldo','valorSaldo'],['resultado_parcela','Parcela','valorParcela']]){
   const result=r[key];
   if(!result){lines.push(label+': sem retorno registrado');continue;}
   lines.push(label+': '+(result[value]!=null?'R$ '+result[value]:'valor não informado')+' | Sucesso informado pelo fluxo: '+(result.sucesso===true?'sim':'não'));
   if(result.etapa)lines.push('Etapa: '+result.etapa);
   if(result.motivo_interrupcao)lines.push('Motivo da interrupção: '+result.motivo_interrupcao);
   if(Array.isArray(result.eventos))for(const event of result.eventos)lines.push((event.horario||'')+' | '+(event.etapa||'')+' | '+(event.status||''));
   if(result.http_status)lines.push('HTTP: '+result.http_status);
   if(result.erro)lines.push('Erro: '+result.erro);
   const messages=Array.isArray(result.todasMensagens)?result.todasMensagens:[];
   lines.push(...(messages.length?messages:[result.mensagemCompleta]).filter(v=>typeof v==='string'));
  }
  return lines.filter(Boolean).join('\n');
 }));
}
$('#digiApiLogSlot').onchange=renderDigiApiLogs;
const digiLogSwitchSettings=switchSettings;
switchSettings=function(id){digiLogSwitchSettings(id);renderDigiApiLogs();if(id==='digimais-api'&&cloudSyncVisible())loadCloud();};
$('#consultationLogPanel').addEventListener('toggle',()=>{if($('#consultationLogPanel').open&&cloudSyncVisible())loadCloud();});
const digiApiPreviousLogs=renderLogs;renderLogs=function(){digiApiPreviousLogs();renderDigiApiLogs();};
const digiApiPreviousAccess=applyAccessUi;applyAccessUi=function(){digiApiPreviousAccess();renderDigiApiLogs();};
const digiApiPreviousReset=resetApiSettings;resetApiSettings=function(){digiApiPreviousReset();digiApiLog.hidden=true;$('#settings-tab-digimais-api').hidden=true;showDigiApiLog([], false);$('#digiApiLogSlot').value='';};
