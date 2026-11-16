"""Supabase queue worker. Service key remains exclusively on the VPS."""
import asyncio,hashlib,json,os,random,time,urllib.request,urllib.error
from pathlib import Path
from datetime import datetime,timezone
from collections import defaultdict
from robot_failures import diagnose, label
from robot_metrics import DIGIMAIS_API_MAX_CONCURRENCY
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

async def dispatch_robot_jobs(capacity, waiting):
 """Reserve ConsigX work before offering Digi+ to the remaining idle robots."""
 idle_rounds=0
 while True:
  # Each robot registers only after finishing and saving its previous job.
  batch=sorted(waiting.items())
  consigx_active=any(slot.service=='consigx' and slot.state in ('consulting','saving')
                     for slot in robot_metrics.slots)
  for service,route in (('tjba','rpc/claim_tjba_job_for_robot'),
                        ('digimais','rpc/claim_consulta_job_for_robot')):
   candidates=reversed(batch) if service=='digimais' and consigx_active else batch
   for index,(future,retry_after) in candidates:
    if future.done() or index>=capacity.target or time.monotonic()<retry_after.get(service,0):
     continue
    try:
     jobs=await asyncio.to_thread(request,route,{'p_slot':index+1})
    except Exception as error:
     if not future.done():future.set_exception(error)
     continue
    if jobs and not future.done():
     future.set_result((service,jobs[0]))
     if service=='tjba':
      consigx_active=True
  claimed=False
  for _,(future,_) in batch:
   if not future.done():
    future.set_result(None)
   elif not future.cancelled() and future.exception() is None and future.result():
    claimed=True
  # Idle robots back off from 3 s to 15 s while both queues stay empty.
  idle_rounds=0 if claimed or not batch else idle_rounds+1
  await asyncio.sleep(min(15,3*(1+idle_rounds//5)))

async def robot_loop(index, capacity, sessions, waiting):
 from robot import DigiSession
 adapter=sessions[index]
 digi=DigiSession()
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
    assignment=asyncio.get_running_loop().create_future()
    waiting[index]=(assignment,retry_after)
    try:
     selected=await assignment
    finally:
     waiting.pop(index,None)
    if selected is None:
     if index >= capacity.target:
      continue
     if slot.state=='queue_error':slot.state='idle'
     await adapter.close_idle();await digi.close_idle()
     continue
    service,job=selected
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
     retry_after[service]=time.monotonic()+30
    if slot:slot.saving(result)
    save_started=time.monotonic()
    result['consultado_em']=datetime.now(timezone.utc).isoformat()
    # Only the attempt that reserved the job may save it: a job requeued meanwhile is left alone.
    route=(('tjba_jobs' if job.get('servico')=='tjba_margem' else 'consulta_jobs')+'?id=eq.'+job['id']
           +'&status=eq.processando&attempts=eq.'+str(job['attempts']))
    await save_result(route,result,slot.name+' · gravar resultado')
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
 def __init__(self,maximum=DIGIMAIS_API_MAX_CONCURRENCY):
  super().__init__(maximum)
  self.target=maximum

def digimais_api_handoff(job, result, finished_at):
 balance = result.get('resultado_saldo') or {}
 installment = result.get('resultado_parcela') or {}
 if not any(part.get('codigo') in ('FORA_HORARIO_ATENDIMENTO', 'TENTATIVAS_ESGOTADAS') for part in (balance, installment)):
  return None
 message = 'API indisponível após tentativas ou fora do horário · encaminhada ao robô'
 return {
  'execution_mode': 'robot', 'status': 'aguardando', 'progress': 0,
  'stage': 'Aguardando robô · falha na API', 'message': message,
  'locked_at': None, 'consultado_em': None, 'robot_slot': None, 'api_slot': None,
  'saldo_liquidacao': None, 'total_parcelas': None, 'valor_parcela': None,
  'resultado_saldo': None, 'resultado_parcela': None,
  'api_handoff': {
   'date': finished_at, 'api_slot': job['api_slot'], 'message': message,
   'resultado_saldo': balance or None, 'resultado_parcela': installment or None,
  },
 }

class QueueIdleGate:
 """Lets one idle executor probe an empty queue instead of every slot polling at once.

 With 100 API slots polling every 5 s the empty queue alone produced ~20 requests/s and
 exhausted the database's disk budget. While the queue is empty only one probe runs, with
 a delay that grows from 5 s to 30 s; any successful claim wakes every slot again."""
 MIN_DELAY=5;MAX_DELAY=30;BUSY_WINDOW=10
 def __init__(self):self.until=0.0;self.delay=0.0;self.last_found=0.0
 def remaining(self):return max(0.0,self.until-time.monotonic())
 def reserve(self):self.until=time.monotonic()+self.MIN_DELAY
 def found(self):self.delay=0.0;self.until=0.0;self.last_found=time.monotonic()
 def empty(self):
  now=time.monotonic()
  if now-self.last_found<self.BUSY_WINDOW:
   # Recent claims succeeded: an empty answer is lock contention, not an empty queue.
   self.until=now+random.uniform(1,3);return
  self.delay=min(self.MAX_DELAY,max(self.MIN_DELAY,self.delay*2))
  self.until=now+self.delay*random.uniform(.8,1.2)

class ApiDispatcher:
 """Reserves work for every idle API slot in one database call.

 Slots wait on a future; the dispatcher asks the queue once per round for all of them
 (claim_consulta_jobs_for_api) and hands each job to the slot it was reserved for.
 While the queue is empty only this loop talks to the database, with the idle gate's
 5 s to 30 s backoff."""
 def __init__(self,capacity,gate=None):
  self.capacity=capacity;self.gate=gate or QueueIdleGate();self.waiting={};self.batch_supported=True
 async def next_job(self,index,timeout=5):
  # The future survives a timeout so a job reserved in the meantime is never dropped.
  future=self.waiting.get(index)
  if future is None or future.done():
   future=asyncio.get_running_loop().create_future();self.waiting[index]=future
  done,_=await asyncio.wait({future},timeout=timeout)
  if not done:return None
  if self.waiting.get(index) is future:del self.waiting[index]
  return future.result()
 def idle(self):
  return sorted(i for i,f in self.waiting.items() if not f.done() and i<self.capacity.target)
 async def claim(self,idle):
  if self.batch_supported:
   try:
    return await asyncio.to_thread(request,'rpc/claim_consulta_jobs_for_api',{'p_slots':[i+1 for i in idle]}) or []
   except urllib.error.HTTPError as error:
    if error.code!=404:raise
    self.batch_supported=False
    print('API DigiMais: reserva em lote ainda não instalada no banco; usando reserva por vaga.',flush=True)
  return await asyncio.to_thread(request,'rpc/claim_consulta_job_for_api',{'p_slot':idle[0]+1}) or []
 async def run(self):
  while True:
   idle=self.idle() if MODE=='live' else []
   wait=self.gate.remaining()
   if not idle or wait>0:
    await asyncio.sleep(min(wait,1) if wait>0 else .2);continue
   try:jobs=await self.claim(idle)
   except Exception as error:
    log_failure('API DigiMais · reservar consultas',diagnose(error,'supabase'),'Nova tentativa em 10 s.')
    self.gate.until=time.monotonic()+10;continue
   if not jobs:
    self.gate.empty();continue
   self.gate.found()
   for job in jobs:
    future=self.waiting.get((job.get('api_slot') or 0)-1)
    if future is not None and not future.done():future.set_result(job)
    else:print(f"API DigiMais: consulta {job.get('id')} reservada sem vaga à espera; volta à fila pelo prazo de reserva.",flush=True)

SPOOL_DIR=Path(os.environ.get('STATE_DIRECTORY') or os.environ.get('APOIARCRED_STATE','/var/lib/apoiarcred'))/'spool'

def spool_write(route,payload):
 """Keep a result on disk until the database confirms it (survives restarts and crashes)."""
 try:
  SPOOL_DIR.mkdir(parents=True,exist_ok=True)
  path=SPOOL_DIR/(hashlib.sha1(route.encode()).hexdigest()[:20]+'.json')
  temporary=path.with_suffix('.tmp')
  temporary.write_text(json.dumps({'route':route,'payload':payload}))
  os.replace(temporary,path)
  return path
 except OSError as error:
  print(f'Resultados: não foi possível gravar cópia local ({type(error).__name__}); seguindo só com o banco.',flush=True)
  return None

async def save_result(route,payload,context):
 path=spool_write(route,payload)
 while True:
  try:
   await asyncio.to_thread(request,route,payload,'PATCH');break
  except Exception as error:
   log_failure(context,diagnose(error,'supabase'),'Repetindo apenas a gravação em 10 s.')
   await asyncio.sleep(10)
 if path:path.unlink(missing_ok=True)

async def replay_spool():
 """Save results left on disk by a previous run. Returns True when nothing is pending."""
 if not SPOOL_DIR.is_dir():return True
 pending=0
 for path in sorted(SPOOL_DIR.glob('*.json')):
  try:
   item=json.loads(path.read_text())
   await asyncio.to_thread(request,item['route'],item['payload'],'PATCH')
   path.unlink(missing_ok=True)
   print('Resultados: gravação pendente concluída após reinício.',flush=True)
  except (ValueError,KeyError) as error:
   print(f'Resultados: cópia local ilegível ignorada ({path.name}).',flush=True);path.rename(path.with_suffix('.bad'))
  except Exception as error:
   pending+=1;log_failure('Resultados · regravar cópia local',diagnose(error,'supabase'))
 return pending==0

async def release_previous_reservations():
 """On start, jobs still 'processando' were held by this VPS before it stopped: requeue them."""
 if not await replay_spool():
  print('Resultados pendentes ainda não gravados; liberação adiada para a rotina de prazo do banco.',flush=True)
  return
 try:
  summary=await asyncio.to_thread(request,'rpc/release_stale_jobs',{'p_older_seconds':0})
  print('Fila: reservas anteriores ao reinício devolvidas '+json.dumps(summary,ensure_ascii=False),flush=True)
 except urllib.error.HTTPError as error:
  if error.code!=404:log_failure('Fila · devolver reservas anteriores',diagnose(error,'supabase'))
 except Exception as error:
  log_failure('Fila · devolver reservas anteriores',diagnose(error,'supabase'))

async def api_loop(index,capacity,slot,config,dispatcher):
 from digimais_api import ApiSession
 adapter=ApiSession(config);adapter.telemetry=slot
 while True:
  try:
   if MODE!='live' or index>=capacity.target:
    slot.state='resource_paused';await asyncio.sleep(5);continue
   if slot.state=='resource_paused':slot.state='idle'
   job=await dispatcher.next_job(index)
   if job is None:
    slot.state='idle';continue
   slot.begin('digimais_api')
   try:result=await process_digimais(job,adapter)
   except Exception as error:
    diagnostic=diagnose(error,'digimais_api')
    log_failure('API DigiMais · execução ou checkpoint',diagnostic)
    result={'status':'revisao','stage':'API interrompida durante execução ou gravação parcial','message':'Motivo da interrupção: '+diagnostic['codigo']+'. Confira o resultado parcial antes de tentar novamente.'}
   finished_at = datetime.now(timezone.utc).isoformat()
   handoff = digimais_api_handoff(job, result, finished_at)
   if handoff is not None:
    result = handoff
   else:
    result['consultado_em'] = finished_at
   slot.saving(result)
   route = (f"consulta_jobs?id=eq.{job['id']}&execution_mode=eq.api&status=eq.processando"
            f"&api_slot=eq.{index+1}&attempts=eq.{job['attempts']}")
   await save_result(route,result,'API DigiMais · gravar resultado')
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
 capacity=ApiCapacity()
 slots=[Slot(f'api-{i+1}') for i in range(capacity.maximum)]
 robot_metrics.api_slots=slots;robot_metrics.api_capacity=capacity
 dispatcher=ApiDispatcher(capacity)
 tasks=[asyncio.create_task(api_loop(i,capacity,slot,config,dispatcher)) for i,slot in enumerate(slots)]
 tasks.append(asyncio.create_task(dispatcher.run()))
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
 if MODE=='live':await release_previous_reservations()
 background=[asyncio.create_task(robot_metrics.publish_loop()),asyncio.create_task(capacity.watch()),asyncio.create_task(api_supervisor())]
 waiting={}
 tasks=[asyncio.create_task(robot_loop(index,capacity,sessions,waiting)) for index in range(maximum)]
 background.append(asyncio.create_task(dispatch_robot_jobs(capacity,waiting)))
 try:
  await asyncio.gather(*tasks,*background)
 finally:
  for task in tasks+background:
   task.cancel()
  await asyncio.gather(*tasks,*background,return_exceptions=True)

def main():asyncio.run(main_async())
if __name__=='__main__':main()
