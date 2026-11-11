// Admin settings are also enforced by database RPCs and queue reservations.
const digiPilot=document.createElement('section');digiPilot.className='card';digiPilot.hidden=true;
digiPilot.innerHTML=`<h2>Digi+ · API experimental</h2><p>Escolha o executor para novas consultas da sua conta. Cada vaga consulta saldo e depois parcela. As consultas já enviadas mantêm o modo original.</p><form id="digiPilotForm"><label class="field" for="digiPilotMode">Executor</label><select id="digiPilotMode"><option value="robot">Robôs</option><option value="api">API experimental</option></select><label class="field" for="digiPilotMax">Limite de clientes simultâneos (1 a 12)</label><input id="digiPilotMax" type="number" min="1" max="12" step="1" value="12" required><label class="portal-enable"><input id="digiPilotPaused" type="checkbox"> Pausar novas execuções da API</label><p>As consultas em andamento terminam normalmente. A capacidade pode diminuir conforme CPU e RAM da VPS. Para esvaziar a fila API após voltar aos robôs, deixe a pausa desmarcada.</p><button class="primary" id="digiPilotSave">Salvar preferência</button></form><p id="digiPilotStatus" role="status"></p><div id="digiPilotMetrics"></div>`;
$('#settings-robots').prepend(digiPilot);
let digiPilotEpoch=-1;
async function loadDigiPilot(){
 digiPilot.hidden=!(authenticated&&currentAccess?.active&&currentAccess.role==='admin');
 if(digiPilot.hidden)return;
 const epoch=authEpoch;$('#digiPilotSave').disabled=true;
 try{const p=await sbRequest('/rest/v1/rpc/manage_digimais_pilot',{method:'POST',body:JSON.stringify({})});if(epoch!==authEpoch)return;
 $('#digiPilotMode').value=p.mode;$('#digiPilotMax').value=p.max_concurrency;$('#digiPilotPaused').checked=p.paused;digiPilotEpoch=epoch;$('#digiPilotStatus').textContent='Preferência exclusiva da sua conta.';
 }catch{if(epoch===authEpoch)$('#digiPilotStatus').textContent='Não foi possível carregar o piloto. Verifique a atualização do banco.';}
 finally{if(epoch===authEpoch)$('#digiPilotSave').disabled=digiPilotEpoch!==epoch;}
}
$('#digiPilotForm').onsubmit=async e=>{e.preventDefault();if(currentAccess?.role!=='admin'||digiPilotEpoch!==authEpoch)return;const epoch=authEpoch;$('#digiPilotSave').disabled=true;
 try{await sbRequest('/rest/v1/rpc/manage_digimais_pilot',{method:'POST',body:JSON.stringify({p_mode:$('#digiPilotMode').value,p_paused:$('#digiPilotPaused').checked,p_max:Number($('#digiPilotMax').value)})});if(epoch===authEpoch)$('#digiPilotStatus').textContent='Salvo. Novas consultas usarão o executor escolhido. A pausa vale para as consultas API ainda aguardando.';}
 catch(e){if(epoch===authEpoch)$('#digiPilotStatus').textContent=e.message||'Não foi possível salvar.';}
 finally{if(epoch===authEpoch)$('#digiPilotSave').disabled=false;}
};
const digiPilotAccess=applyAccessUi;applyAccessUi=function(){digiPilotAccess();digiPilot.hidden=!(authenticated&&currentAccess?.active&&currentAccess.role==='admin');if(!digiPilot.hidden&&digiPilotEpoch!==authEpoch)loadDigiPilot();};
const digiPilotSettings=switchSettings;switchSettings=function(id){digiPilotSettings(id);if(id==='robots')loadDigiPilot();};
const digiPilotReset=resetApiSettings;resetApiSettings=function(){digiPilotReset();digiPilotEpoch=-1;digiPilot.hidden=true;$('#digiPilotMetrics').textContent='';};
const digiPilotMonitoring=renderMonitoring;renderMonitoring=function(){digiPilotMonitoring();if(digiPilot.hidden)return;const r=monitoringSnapshot?.payload?.robots,slots=r?.api_slots||[];
 const sum=k=>slots.reduce((n,s)=>n+(Number(s[k])||0),0),total=sum('finished_last_hour');
 const average=total?slots.reduce((n,s)=>n+(s.average_seconds||0)*(s.finished_last_hour||0),0)/total:null;
 const stale=Date.now()-Date.parse(r?.updated_at||'')>20000||!r;
 $('#digiPilotMetrics').textContent=(stale?'Métricas indisponíveis ou desatualizadas. ':'')+`Capacidade da VPS: ${r?.api_capacity||0}/12 · Em execução: ${slots.filter(s=>['consulting','saving'].includes(s.state)).length} · Última hora: ${total} clientes · Saldo e parcela preenchidos: ${sum('complete_values_last_hour')} · Sem ambos os valores: ${sum('missing_values_last_hour')} · HTTP 429: ${sum('rate_limited_last_hour')} · Revisão: ${sum('review_last_hour')} · Tempo médio: ${robotDuration(average)}. Métricas globais do piloto desde o reinício do executor.`;
};
