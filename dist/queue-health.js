// Saúde da fila (Fase 4, observabilidade): só para a equipe ApoiarCred.
// Quadro em Configurações › Robôs e monitoramento e aviso no Início quando a fila para de andar.
// Atualiza a cada 30 s, apenas com a aba visível e uma dessas telas aberta.
(function(){
 const robots=$('#settings-robots');if(!robots)return;
 const card=document.createElement('section');card.className='card queue-health';card.hidden=true;
 card.setAttribute('aria-labelledby','queueHealthTitle');
 card.innerHTML=`<div class="heading"><div><h2 id="queueHealthTitle">Saúde da fila</h2><p>Consultas esperando, andamento e falhas na última hora. Atualiza a cada 30 segundos.</p></div><span id="queueHealthStatus" class="pill">Aguardando dados</span></div>
<div class="scroll"><table class="queue-health-table"><thead><tr><th>Serviço</th><th>Na fila</th><th>Consultando</th><th>Espera da mais antiga</th><th>Concluídas na última hora</th><th>Falhas na última hora</th><th>Última conclusão</th></tr></thead><tbody id="queueHealthRows"></tbody></table></div>
<p id="queueHealthNote" class="muted"></p>`;
 robots.prepend(card);
 const banner=document.createElement('div');banner.className='queue-stalled-banner';banner.hidden=true;banner.setAttribute('role','alert');
 document.getElementById('dashboard')?.querySelector('.dashboard-header')?.after(banner);

 const names={digimais_saldo_parcela:'Digi+ · Saldo e parcela',tjba_margem:'ConsigX · Margem'};
 const fmt=new Intl.NumberFormat('pt-BR');
 let timer=0,busy=false,last=null;
 const isAdmin=()=>authenticated&&currentAccess?.role==='admin'&&currentAccess.active;
 const visible=()=>isAdmin()&&document.visibilityState!=='hidden'&&(currentPage==='dashboard'||currentPage==='settings'&&!$('#settings-robots').hidden);
 function ago(value){
  if(!value)return 'Nunca';
  const minutes=Math.max(0,Math.round((Date.now()-new Date(value))/60000));
  return minutes<1?'Agora há pouco':minutes<60?`Há ${minutes} min`:minutes<1440?`Há ${Math.floor(minutes/60)} h`:new Date(value).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'});
 }
 function waitLabel(m){return m==null?'—':m<60?`${m} min`:`${Math.floor(m/60)} h ${m%60} min`;}
 function render(data){
  last=data;const services=data?.servicos||[],stalled=services.filter(s=>s.parada);
  $('#queueHealthRows').innerHTML=services.map(s=>`<tr class="${s.parada?'stalled':''}"><td><strong>${escapeHTML(names[s.servico]||s.servico)}</strong>${s.parada?' <span class="pill err">Parada</span>':''}</td><td>${fmt.format(s.na_fila)}</td><td>${fmt.format(s.consultando)}</td><td>${escapeHTML(waitLabel(s.espera_minutos))}</td><td>${fmt.format(s.concluidas_hora)}</td><td>${fmt.format(s.falhas_hora)}</td><td>${escapeHTML(ago(s.ultima_conclusao))}</td></tr>`).join('');
  const status=$('#queueHealthStatus');
  if(data?.manutencao_ate){status.textContent='Em manutenção';status.className='pill';}
  else if(stalled.length){status.textContent='Fila parada';status.className='pill err';}
  else{status.textContent=services.some(s=>s.na_fila||s.consultando)?'Andando':'Sem fila';status.className='pill ok';}
  $('#queueHealthNote').textContent=data?.manutencao_ate?`Fila pausada para manutenção até ${new Date(data.manutencao_ate).toLocaleTimeString('pt-BR',{timeStyle:'short'})}.`
   :'"Parada" quer dizer: há consultas esperando e nenhuma terminou nos últimos 15 minutos. Campanhas pausadas não contam.';
  banner.hidden=!stalled.length;
  if(stalled.length)banner.innerHTML=`<div><strong>Fila parada</strong><p>${stalled.map(s=>`${escapeHTML(names[s.servico]||s.servico)}: ${fmt.format(s.na_fila)} esperando, última conclusão ${escapeHTML(ago(s.ultima_conclusao).toLowerCase())}`).join(' · ')}. Confira os robôs e o coletor da VPS.</p></div><button type="button" data-queue-open>Ver robôs</button>`;
 }
 async function refresh(){
  card.hidden=!isAdmin();
  if(!visible()||busy){if(!isAdmin())banner.hidden=true;return;}
  busy=true;const epoch=authEpoch;
  try{const data=await sbRequest('/rest/v1/rpc/admin_queue_health',{method:'POST',body:'{}'});if(epoch===authEpoch)render(data);}
  catch{if(epoch===authEpoch)$('#queueHealthNote').textContent='Não foi possível ler a saúde da fila agora. Tentando de novo em 30 segundos.';}
  finally{busy=false;}
 }
 function schedule(){clearInterval(timer);timer=setInterval(refresh,30000);refresh();}
 banner.addEventListener('click',e=>{if(e.target.closest('[data-queue-open]')){navigate('settings');switchSettings('robots');}});
 const baseNavigate=navigate;navigate=function(...args){baseNavigate(...args);refresh();};
 if(typeof switchSettings==='function'){const baseSwitch=switchSettings;switchSettings=function(...args){baseSwitch(...args);refresh();};}
 if(typeof applyAccessUi==='function'){const baseApply=applyAccessUi;applyAccessUi=function(...args){baseApply(...args);card.hidden=!isAdmin();if(!isAdmin())banner.hidden=true;};}
 document.addEventListener('visibilitychange',()=>{if(document.visibilityState!=='hidden')refresh();});
 window.queueHealthRefresh=refresh;window.queueHealthLast=()=>last;
 schedule();
})();
