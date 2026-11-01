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
