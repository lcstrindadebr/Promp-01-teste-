let monitoringSnapshot=null,monitoringLoading=false,monitoringError='';
const metricPercent=v=>v!=null&&Number.isFinite(Number(v))?Math.max(0,Math.min(100,Number(v))):null;
function metricBytes(v){return v!=null&&Number.isFinite(Number(v))?(Number(v)/1073741824).toLocaleString('pt-BR',{maximumFractionDigits:2})+' GB':'—';}
function renderMonitoring(){
 const data=monitoringSnapshot?.payload,stamp=Date.parse(monitoringSnapshot?.updated_at||''),age=(Date.now()-stamp)/1000;
 const fresh=Boolean(data)&&Number.isFinite(age)&&age>=-60&&age<=20&&!monitoringError;
 $('#monitorStatus').textContent=monitoringError?'Sem conexão':!data?'Aguardando coletor':fresh?'Atualizado':'Dados desatualizados';
 $('#monitorStatus').className='pill '+(fresh?'ok':'err');
 $('#monitorUpdated').textContent=Number.isFinite(stamp)?'Última coleta: '+new Date(stamp).toLocaleString('pt-BR'):'As métricas aparecem após atualizar o auto instalador na VPS.';
 $('#monitorError').textContent=monitoringError||(!fresh&&data?'O coletor não está enviando dados recentes. Confira o serviço apoiarcred-monitor na VPS.':'');
 const mem=data?.memory,disk=data?.disk;
 const metrics=[['CPU',data?.cpu_percent,data?.cpu_count?data.cpu_count+' vCPU':'—'],['Memória RAM',mem?.percent,mem?metricBytes(mem.used)+' de '+metricBytes(mem.total):'—'],['Disco',disk?.percent,disk?metricBytes(disk.used)+' de '+metricBytes(disk.total):'—'],['Swap',mem?.swap_total>0?100*mem.swap_used/mem.swap_total:null,mem?.swap_total===0?'Não configurada':mem?metricBytes(mem.swap_used)+' de '+metricBytes(mem.swap_total):'—']];
 $('#monitorMetrics').innerHTML=metrics.map(([label,value,detail])=>{const pct=metricPercent(value);return `<div class="monitor-metric"><span>${label}</span><strong>${pct==null?'—':pct.toLocaleString('pt-BR',{maximumFractionDigits:1})+'%'}</strong><progress max="100" value="${pct??0}" aria-label="${label}"${pct==null?' hidden':''}></progress><small>${escapeHTML(detail)}</small></div>`;}).join('');
 $('#monitorWorker').textContent=({active:'Ativo',inactive:'Parado',failed:'Falhou',activating:'Iniciando',deactivating:'Parando',reloading:'Recarregando',unknown:'Indisponível'})[data?.worker]||'—';
 $('#monitorMode').textContent=({live:'Consultas habilitadas',disabled:'Consultas desativadas',demo:'Demonstração',unknown:'Modo indisponível'})[data?.robot_mode]||'—';
 const seconds=Number(data?.uptime_seconds);$('#monitorUptime').textContent=Number.isFinite(seconds)?`${Math.floor(seconds/86400)}d ${Math.floor(seconds%86400/3600)}h ${Math.floor(seconds%3600/60)}min`:'—';
 renderRobotHealth(data,fresh);
 $('#monitorAvailable').textContent=metricBytes(mem?.available);$('#monitorMetrics').classList.toggle('monitor-stale',!fresh);
}
function resetMonitoring(){monitoringSnapshot=null;monitoringError='';renderMonitoring();}
async function tickMonitoring(){
 if(!authenticated||currentPage!=='settings'||document.visibilityState==='hidden')return;
 renderMonitoring();if(monitoringLoading)return;monitoringLoading=true;const epoch=authEpoch;
 try{const rows=await sbRequest('/rest/v1/vps_monitoramento?id=eq.principal&select=updated_at,payload&limit=1');if(epoch!==authEpoch)return;monitoringSnapshot=rows[0]||null;monitoringError='';}
 catch(e){if(epoch===authEpoch)monitoringError='Não foi possível atualizar as métricas. Verifique a conexão e a atualização do coletor na VPS.';}
 finally{monitoringLoading=false;if(epoch===authEpoch&&authenticated)renderMonitoring();}
}
$('#refreshMonitor').onclick=tickMonitoring;renderMonitoring();setInterval(tickMonitoring,5000);

function robotDuration(value){
 if(value==null||!Number.isFinite(Number(value)))return '—';
 const n=Math.max(0,Math.floor(Number(value)));return n>=60?Math.floor(n/60)+'min '+n%60+'s':n+'s';
}
function renderRobotHealth(data,collectorFresh){
 const robots=data?.robots,age=(Date.now()-Date.parse(robots?.updated_at||''))/1000;
 const fresh=collectorFresh&&Number.isFinite(age)&&age>=-60&&age<=20&&data?.worker==='active';
 const enabled=data?.robot_mode==='live';
 $('#robotsStatus').textContent=!data?'Aguardando dados':!fresh?'Sem comunicação':!enabled?'Desativados':'Em operação';
 $('#robotsStatus').className='pill '+(fresh&&enabled?'ok':'err');
 const slots=Array.isArray(robots?.slots)?robots.slots.slice(0,2):[];
 $('#robotsCards').innerHTML=slots.length?slots.map((s,index)=>{
  const label=!fresh?'Sem comunicação':!enabled?'Consultas desativadas':({idle:'Disponível',consulting:'Consultando',saving:'Salvando resultado',queue_error:'Falha de conexão com a fila'})[s.state]||'Estado indisponível';
  const service=s.service==='digimais'?'Digi+':s.service==='consigx'?'ConsigX':index===0?'Digi+ / ConsigX':'Digi+';
  const running=fresh&&enabled&&['consulting','saving'].includes(s.state),pct=metricPercent(s.progress);
  const activity=Date.parse(s.last_activity||''),inactive=Math.max(0,(Date.now()-activity)/1000);
  return `<article class="robot-health-slot"><div class="heading"><h3>Executor ${index+1}</h3><span class="pill ${!fresh||s.state==='queue_error'?'err':running?'run':enabled?'ok':''}">${escapeHTML(label)}</span></div><p>${service}${index===0?' · compartilhado':''}</p>${running?`<strong>${robotDuration(s.elapsed_seconds)} em execução</strong><div class="progress-line"><progress max="100" value="${pct??0}" aria-label="Progresso do executor ${index+1}"></progress><small>${pct??0}%</small></div>`:`<strong>${!fresh?'Estado atual não confirmado':!enabled?'Execução desativada':'Aguardando próxima consulta'}</strong>`}<small>Última consulta: ${robotDuration(s.last_duration_seconds)}</small>${running&&Number.isFinite(inactive)&&inactive>60?`<small class="robot-delay">Sem nova etapa há ${robotDuration(inactive)}. Aguardando resposta ou gravação.</small>`:''}</article>`;
 }).join(''):'<p class="muted">O estado dos executores aparece após atualizar o robô e o coletor pelo instalador.</p>';
 const count=key=>slots.reduce((n,s)=>n+Math.max(0,Number(s[key])||0),0);
 const total=count('finished_last_hour'),conclusive=count('conclusive_last_hour');
 const timed=slots.filter(s=>s.average_seconds!=null&&Number.isFinite(Number(s.average_seconds)));
 const timedCount=timed.reduce((n,s)=>n+Number(s.finished_last_hour||0),0);
 const avg=timedCount?timed.reduce((n,s)=>n+Number(s.average_seconds)*Number(s.finished_last_hour||0),0)/timedCount:null;
 const stats=[['Processadas · última hora',total],['Retornos conclusivos',total?(100*conclusive/total).toLocaleString('pt-BR',{maximumFractionDigits:1})+'%':'—'],['Erros',count('errors_last_hour')],['Revisão',count('review_last_hour')],['Tempo médio por consulta',robotDuration(avg)]];
 $('#robotsStats').innerHTML=slots.length?stats.map(([label,value])=>`<div><span>${label}</span><strong>${escapeHTML(value)}</strong></div>`).join(''):'';
 $('#robotsStats').classList.toggle('monitor-stale',!fresh);
 const start=Date.parse(robots?.started_at||'');
 $('#robotsNote').textContent='Retornos conclusivos incluem resultados concluídos e ausência confirmada de cliente/registro. Contagem após salvar no banco; tempo médio inclui saldo e parcela no Digi+, sem a espera pela gravação final. '+(Number.isFinite(start)?'Janela móvel de até 60 minutos, desde o reinício em '+new Date(start).toLocaleString('pt-BR')+'. ':'')+(!fresh?'Os dados exibidos podem estar desatualizados.':'');
}
