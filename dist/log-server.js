// Logs de Configurações vindos do banco (Fase 2c, etapa 3): as consultas encerradas mais recentes,
// filtradas pelo robô ou pela API, por public.painel_log_consultas. O navegador não tem mais a lista
// completa das consultas de campanha. Sem a função no banco, os logs usam as consultas carregadas.
const serverLogs={robo:null,api:null};
let serverLogsOff=false;
const serverLogLimit={robo:500,api:100};
function serverLogEntry(mode,slot){
 if(serverLogsOff||!authenticated)return null;
 const entry=serverLogs[mode];
 const fresh=entry&&entry.epoch===authEpoch&&entry.slot===slot;
 if(!fresh||Date.now()-entry.at>15000)loadServerLog(mode,slot);
 return fresh?entry.rows:null;
}
async function loadServerLog(mode,slot){
 const current=serverLogs[mode];
 if(current?.loading===slot+'@'+authEpoch)return;
 const epoch=authEpoch;
 serverLogs[mode]={...(current||{}),loading:slot+'@'+epoch};
 try{
  const data=await sbRequest('/rest/v1/rpc/painel_log_consultas',{method:'POST',body:JSON.stringify({p_modo:mode,p_slot:slot,p_limite:serverLogLimit[mode]})});
  if(epoch!==authEpoch)return;
  // Linhas iguais às da busca anterior mantêm o mesmo objeto: os detalhes já carregados (log do ConsigX)
  // ficam guardados por linha e não são pedidos de novo a cada atualização.
  const previous=new Map((current?.epoch===epoch?current.rows||[]:[]).map(row=>[row.id,row]));
  const rows=data.map(raw=>{const key=JSON.stringify(raw),old=previous.get(raw.id);
   if(old&&old.__raw===key)return old;const row=normalizeCloudRow(raw);Object.defineProperty(row,'__raw',{value:key});return row;});
  serverLogs[mode]={rows,slot,epoch,at:Date.now(),loading:''};
  if(mode==='robo'&&$('#consultationLogPanel').open)renderLogs();
  if(mode==='api'&&typeof renderDigiApiLogs==='function')renderDigiApiLogs();
 }catch(error){
  if(error?.status===404&&error?.code==='PGRST202')serverLogsOff=true;
  if(serverLogs[mode])serverLogs[mode].loading='';
 }
}
// Log dos robôs (Configurações › Sua conta).
const serverLogBaseRecords=consultationLogRecords;
consultationLogRecords=function(){
 const slot=$('#consultationLogRobot').value;
 const rows=$('#consultationLogPanel').open?serverLogEntry('robo',slot):null;
 return rows||serverLogBaseRecords();
};
// Log da API Digi+ (digimais-pilot.js pergunta por aqui).
function serverApiLogRows(slot){return serverLogEntry('api',slot);}
window.serverLogState=()=>({off:serverLogsOff,robo:serverLogs.robo,api:serverLogs.api});
