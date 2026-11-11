"""Supabase queue worker. Service key remains exclusively on the VPS."""
import asyncio,json,os,time,urllib.request,urllib.error
from datetime import datetime,timezone
from collections import defaultdict
from robot_failures import diagnose, label
URL=os.environ['SUPABASE_URL'].rstrip('/')
KEY=os.environ['SUPABASE_SERVICE_ROLE_KEY']
MODE=os.environ.get('ROBOT_MODE','disabled')
robot_metrics=None
def request(path,payload=None,method='POST',timeout=30):
 data=json.dumps(payload).encode() if payload is not None else None
 headers={'apikey':KEY,'Content-Type':'application/json'}
 if not KEY.startswith('sb_secret_'):headers['Authorization']='Bearer '+KEY
 req=urllib.request.Request(URL+'/rest/v1/'+path,data=data,method=method,headers=headers)
 with urllib.request.urlopen(req,timeout=timeout) as res:
  text=res.read().decode();return json.loads(text) if text else None

async def process_digimais(job,adapter):
 if job.get('servico','digimais_saldo_parcela')!='digimais_saldo_parcela':return {'status':'revisao','message':'Tipo de higienização sem robô disponível.'}
 if MODE=='demo':return {'status':'revisao','message':'Worker em modo demo. Nenhuma consulta realizada; use a demonstração local para valores fictícios.'}
 if MODE!='live':return {'status':'revisao','message':'Robô desativado. Ative somente após homologação.'}
 # Only the latest pending progress matters; database latency must not pause chat clicks.
 queue=asyncio.Queue(maxsize=1)
 started=time.monotonic()
 executor=getattr(getattr(adapter,'telemetry',None),'name','Digi+')
 async def report(percent,stage):
  if getattr(adapter,'telemetry',None):adapter.telemetry.report(percent)
  print(f"ETAPA | {executor} | {percent}% | {time.monotonic()-started:.1f}s | {stage}",flush=True)
  if queue.full():queue.get_nowait();queue.task_done()
  queue.put_nowait({'progress':percent,'stage':stage})
 async def flush():
  while True:
   data=await queue.get()
   try:await asyncio.to_thread(request,'consulta_jobs?id=eq.'+job['id'],data,'PATCH',4)
   except Exception as error:log_failure(executor+' · Digi+ · gravar progresso',diagnose(error,'supabase'))
   finally:queue.task_done()
 writer=asyncio.create_task(flush())
 try:
  async def checkpoint(data):
   await queue.join()
   await asyncio.to_thread(request,'consulta_jobs?id=eq.'+job['id'],data,'PATCH',10)
  result=await adapter.run(job,on_progress=report,on_checkpoint=checkpoint)
  await queue.join() # Finish progress writes before saving the final result.
  return result
 finally:
  writer.cancel()
  try:await writer
  except asyncio.CancelledError:pass
async def process_tjba(job,adapter):
 from tjba import job_result
 if MODE!='live':return job_result({'status':'sessao_expirada','observacoes':'Robô desativado. Ative somente após homologação.'})
 payload={'p_user_id':job['user_id']}
 route='rpc/get_tjba_credentials'
 if job.get('robot_slot'):
  route='rpc/get_tjba_robot_credentials'
  payload['p_slot']=job['robot_slot']
 try:
  credentials=await asyncio.to_thread(request,route,payload)
 except Exception as error:
  diagnostic=diagnose(error,'supabase')
  diagnostic['repetir']=diagnostic['transitorio']
  return job_result({'status':'erro','diagnostico':diagnostic,
                     'observacoes':f'{label(diagnostic)} Falha ao carregar o acesso ConsigX.'})
 executor=getattr(getattr(adapter,'telemetry',None),'name','ConsigX')
 queue=asyncio.Queue(maxsize=1)
 async def report(percent,stage):
  print(f'ETAPA | {executor} | {percent}% | {stage}',flush=True)
  if getattr(adapter,'telemetry',None):adapter.telemetry.report(percent)
  if queue.full():queue.get_nowait();queue.task_done()
  queue.put_nowait({'progress':percent,'stage':stage})
 async def flush():
  while True:
   data=await queue.get()
   try:await asyncio.to_thread(request,'tjba_jobs?id=eq.'+job['id'],data,'PATCH',4)
   except Exception as error:log_failure(executor+' · ConsigX · gravar progresso',diagnose(error,'supabase'))
   finally:queue.task_done()
 writer=asyncio.create_task(flush())
 try:
  username=(credentials or {}).get('username','').strip().casefold()
  if username and credentials.get('enabled') and hasattr(adapter,'login_locks'):
   # Keep the portal login exclusive even if credentials change after queue reservation.
   async with adapter.login_locks[username]:
    adapter.portal_user=username
    for peer in adapter.peers:
     if peer is not adapter and getattr(peer,'portal_user',None)==username:
      peer.portal_user=None
      await peer.close()
    result=await adapter.run(job,credentials,report)
  else:
   result=await adapter.run(job,credentials,report)
  await queue.join()
  return result
 finally:
  credentials=None;writer.cancel()
  try:await writer
  except asyncio.CancelledError:pass

def log_failure(context, diagnostic, action=''):
 fields=['FALHA',context,label(diagnostic)]
 if diagnostic.get('etapa'):fields.append(diagnostic['etapa'])
 if action:fields.append(action)
 print(' | '.join(fields),flush=True)

def result_diagnostic(result):
 for field in ('resultado_tjba','resultado_parcela','resultado_saldo'):
  diagnostic=(result.get(field) or {}).get('diagnostico')
  if diagnostic:return diagnostic
 return None

async def run_with_recovery(process, job, session, name):
 result=await process(job,session)
 diagnostic=result_diagnostic(result)
 if not diagnostic:return result
 # A second-stage Digi+ error must not replay a balance already queried.
 can_retry=diagnostic.get('repetir') and not result.get('resultado_parcela')
 if not can_retry:
  log_failure(name,diagnostic)
  return result
 log_failure(name,diagnostic,'Recriando sessão; uma nova tentativa antes do envio do CPF.')
 await session.close()
 await asyncio.sleep(3)
 recovered=await process(job,session)
 final_diagnostic=result_diagnostic(recovered)
 if final_diagnostic:log_failure(name,final_diagnostic,'Nova tentativa encerrada.')
 else:print(f'RECUPERAÇÃO | {name} | {label(diagnostic)} | Nova tentativa finalizada.',flush=True)
 previous=f'Recuperação automática após {label(diagnostic)}. Uma nova tentativa realizada.'
 recovered['message']=' '.join(filter(None,[recovered.get('message'),previous]))
 return recovered

async def robot_loop(index, capacity, sessions):
 from robot import DigiSession
 adapter=sessions[index]
 digi=DigiSession()
 last_queue='tjba' if index % 2 == 0 else 'digimais'
 retry_after={}
 slot=robot_metrics.slots[index]
 adapter.telemetry=slot;digi.telemetry=slot
 try:
  while True:
   try:
    if index >= capacity.target:
     slot.state='resource_paused'
     slot.service=None
     await adapter.close()
     await digi.close()
     await asyncio.sleep(3)
     continue
    if slot.state=='resource_paused':
     slot.state='idle'
    queues=['digimais','tjba'] if last_queue=='tjba' else ['tjba','digimais']
    jobs=[]
    for queue_name in queues:
     if index >= capacity.target:
      break
     if time.monotonic()<retry_after.get(queue_name,0):continue
     route='rpc/claim_tjba_job_for_robot' if queue_name=='tjba' else 'rpc/claim_consulta_job_for_robot'
     payload={'p_slot':index+1}
     jobs=await asyncio.to_thread(request,route,payload)
     if jobs:last_queue=queue_name;break
    if not jobs:
     if index >= capacity.target:
      continue
     if slot and slot.state=='queue_error':slot.state='idle'
     await adapter.close_idle();await digi.close_idle();await asyncio.sleep(3);continue
    job=jobs[0]
    if slot:slot.begin('consigx' if job.get('servico')=='tjba_margem' else 'digimais')
    try:
     if job.get('servico')=='tjba_margem':
      await digi.close();result=await run_with_recovery(process_tjba,job,adapter,slot.name+' · ConsigX')
     else:
      await adapter.close();result=await run_with_recovery(process_digimais,job,digi,slot.name+' · Digi+')
    except Exception as error:
     diagnostic=diagnose(error)
     log_failure(slot.name,diagnostic,'Recriando sessão para a próxima consulta.')
     result={'status':'erro','message':f'{label(diagnostic)} Falha interna no executor. Sessão encerrada.'}
     await adapter.close()
     await digi.close()
    diagnostic=result_diagnostic(result)
    if diagnostic and diagnostic.get('transitorio'):
     retry_after[last_queue]=time.monotonic()+30
    if slot:slot.saving(result)
    save_started=time.monotonic()
    result['consultado_em']=datetime.now(timezone.utc).isoformat()
    while True:
     try:await asyncio.to_thread(request,('tjba_jobs' if job.get('servico')=='tjba_margem' else 'consulta_jobs')+'?id=eq.'+job['id'],result,'PATCH');break
     except Exception as error:
      log_failure(slot.name+' · gravar resultado',diagnose(error,'supabase'),'Repetindo apenas a gravação em 10 s.')
      await asyncio.sleep(10)
    if slot:
     print(f"DURAÇÃO | {slot.name} | processamento={slot.duration:.1f}s | gravação={time.monotonic()-save_started:.1f}s",flush=True)
     slot.saved()
   except Exception as error:
    if slot:slot.state='queue_error'
    log_failure(slot.name+' · fila',diagnose(error,'supabase'),'Nova tentativa em 10 s.')
    await asyncio.sleep(10)
 finally:
  await adapter.close();await digi.close()

class RobotCapacity:
 """Park secondary slots under pressure, then ramp up after sustained recovery."""
 def __init__(self, maximum):
  self.maximum=maximum
  self.target=1
  self.hot_samples=0
  self.healthy_samples=0

 def observe(self, ram, cpu):
  mib=1024**2
  low=ram['available'] < max(256*mib, ram['total']*.15)
  self.hot_samples=self.hot_samples+1 if cpu is not None and cpu>=95 else 0
  healthy=ram['available'] >= max(512*mib, ram['total']*.25) and cpu is not None and cpu<=75
  self.healthy_samples=self.healthy_samples+1 if healthy else 0
  if low or self.hot_samples>=3:
   self.target=max(1,self.target-1)
   self.hot_samples=0
   self.healthy_samples=0
  elif self.healthy_samples>=6:
   self.target=min(self.maximum,self.target+1)
   self.healthy_samples=0

 async def watch(self):
  from monitor import cpu_ticks, cpu_percent, memory
  previous=None
  while True:
   before=self.target
   try:
    current=cpu_ticks()
    self.observe(memory(),cpu_percent(previous,current) if previous else None)
    previous=current
   except (OSError,ValueError,KeyError,IndexError):
    self.target=1
    self.healthy_samples=self.hot_samples=0
    previous=None
   if self.target!=before:
    print(f"Capacidade {'API experimental' if isinstance(self,ApiCapacity) else 'dos robôs'}: {before} → {self.target}.",flush=True)
   await asyncio.sleep(5)

class ApiCapacity(RobotCapacity):
 def __init__(self,maximum=12):
  super().__init__(maximum)
  self.target=maximum

async def api_loop(index,capacity,slot,config):
 from digimais_api import ApiSession
 adapter=ApiSession(config);adapter.telemetry=slot
 while True:
  try:
   if MODE!='live' or index>=capacity.target:
    slot.state='resource_paused';await asyncio.sleep(5);continue
   jobs=await asyncio.to_thread(request,'rpc/claim_consulta_job_for_api',{'p_slot':index+1})
   if not jobs:
    slot.state='idle';await asyncio.sleep(5);continue
   job=jobs[0];slot.begin('digimais_api')
   try:result=await process_digimais(job,adapter)
   except Exception:
    result={'status':'revisao','message':'API interrompida. Confira o resultado parcial antes de tentar novamente.'}
   slot.saving(result)
   result['consultado_em']=datetime.now(timezone.utc).isoformat()
   while True:
    try:
     await asyncio.to_thread(request,'consulta_jobs?id=eq.'+job['id'],result,'PATCH');break
    except Exception:
     await asyncio.sleep(10) # Retry persistence only, never replay the external consultation.
   slot.saved()
  except Exception:
   slot.state='queue_error';await asyncio.sleep(10)

async def api_supervisor():
 from robot_metrics import Slot
 while True:
  try:
   config=await asyncio.to_thread(request,'rpc/get_digimais_api_config',{})
   if not config:await asyncio.sleep(30);continue
   break
  except Exception:await asyncio.sleep(30)
 capacity=ApiCapacity(12)
 slots=[Slot(f'api-{i+1}') for i in range(12)]
 robot_metrics.api_slots=slots;robot_metrics.api_capacity=capacity
 tasks=[asyncio.create_task(api_loop(i,capacity,slot,config)) for i,slot in enumerate(slots)]
 tasks.append(asyncio.create_task(capacity.watch()))
 try:await asyncio.gather(*tasks)
 finally:
  for task in tasks:task.cancel()
  await asyncio.gather(*tasks,return_exceptions=True)

async def main_async():
 global robot_metrics
 from robot_metrics import RobotMetrics
 from tjba import Session
 workers=os.environ.get('ROBOT_WORKERS',os.environ.get('DIGIMAIS_WORKERS','4'))
 if workers not in ('1','2','3','4'):
  raise ValueError('ROBOT_WORKERS deve ser 1, 2, 3 ou 4.')
 maximum=int(workers)
 capacity=RobotCapacity(maximum)
 robot_metrics=RobotMetrics(maximum)
 sessions=[Session() for _ in range(maximum)]
 login_locks=defaultdict(asyncio.Lock)
 for adapter in sessions:
  adapter.peers=sessions
  adapter.login_locks=login_locks
 print(f'Até {maximum} robôs para Digi+ e ConsigX, com ajuste automático de capacidade.',flush=True)
 background=[asyncio.create_task(robot_metrics.publish_loop()),asyncio.create_task(capacity.watch()),asyncio.create_task(api_supervisor())]
 tasks=[asyncio.create_task(robot_loop(index,capacity,sessions)) for index in range(maximum)]
 try:
  await asyncio.gather(*tasks,*background)
 finally:
  for task in tasks+background:
   task.cancel()
  await asyncio.gather(*tasks,*background,return_exceptions=True)

def main():asyncio.run(main_async())
if __name__=='__main__':main()
