"""Supabase queue worker. Service key remains exclusively on the VPS."""
import asyncio,json,os,time,urllib.request,urllib.error
from datetime import datetime,timezone
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
 async def report(percent,stage):
  if getattr(adapter,'telemetry',None):adapter.telemetry.report(percent)
  print(f"ETAPA | {percent}% | {time.monotonic()-started:.1f}s | {stage}",flush=True)
  if queue.full():queue.get_nowait();queue.task_done()
  queue.put_nowait({'progress':percent,'stage':stage})
 async def flush():
  while True:
   data=await queue.get()
   try:await asyncio.to_thread(request,'consulta_jobs?id=eq.'+job['id'],data,'PATCH',4)
   except Exception:print('Não foi possível registrar progresso desta etapa.',flush=True)
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
 credentials=await asyncio.to_thread(request,'rpc/get_tjba_credentials',{'p_user_id':job['user_id']})
 queue=asyncio.Queue(maxsize=1)
 async def report(percent,stage):
  if getattr(adapter,'telemetry',None):adapter.telemetry.report(percent)
  if queue.full():queue.get_nowait();queue.task_done()
  queue.put_nowait({'progress':percent,'stage':stage})
 async def flush():
  while True:
   data=await queue.get()
   try:await asyncio.to_thread(request,'tjba_jobs?id=eq.'+job['id'],data,'PATCH',4)
   except Exception:print('Falha ao salvar progresso TJBA.',flush=True)
   finally:queue.task_done()
 writer=asyncio.create_task(flush())
 try:
  result=await adapter.run(job,credentials,report);await queue.join();return result
 finally:
  credentials=None;writer.cancel()
  try:await writer
  except asyncio.CancelledError:pass

async def primary_loop():
 from tjba import Session
 from robot import DigiSession
 adapter=Session();digi=DigiSession();last_queue="tjba"
 slot=robot_metrics.slots[0] if robot_metrics else None
 adapter.telemetry=slot;digi.telemetry=slot
 try:
  while True:
   try:
    queues=['digimais','tjba'] if last_queue=='tjba' else ['tjba','digimais']
    jobs=[]
    for queue_name in queues:
     jobs=await asyncio.to_thread(request,'rpc/claim_tjba_job' if queue_name=='tjba' else 'rpc/claim_consulta_job',{})
     if jobs:last_queue=queue_name;break
    if not jobs:
     if slot and slot.state=='queue_error':slot.state='idle'
     await adapter.close_idle();await digi.close_idle();await asyncio.sleep(3);continue
    job=jobs[0]
    if slot:slot.begin('consigx' if job.get('servico')=='tjba_margem' else 'digimais')
    try:
     if job.get('servico')=='tjba_margem':
      await digi.close();result=await process_tjba(job,adapter)
     else:
      await adapter.close();result=await process_digimais(job,digi)
    except Exception:result={'status':'erro','message':'Falha interna no robô. Verificar a instalação e conectividade da VPS.'}
    if slot:slot.saving(result)
    result['consultado_em']=datetime.now(timezone.utc).isoformat()
    while True:
     try:await asyncio.to_thread(request,('tjba_jobs' if job.get('servico')=='tjba_margem' else 'consulta_jobs')+'?id=eq.'+job['id'],result,'PATCH');break
     except Exception:print('Falha ao salvar resultado; tentando novamente.',flush=True);await asyncio.sleep(10)
    if slot:slot.saved()
   except Exception:
    if slot:slot.state='queue_error'
    print('Fila indisponível; nova tentativa em 10 segundos.',flush=True);await asyncio.sleep(10)
 finally:
  await adapter.close();await digi.close()

async def digimais_loop():
 """Second executor claims Digi+ only. No shared Playwright/browser state."""
 from robot import DigiSession
 digi=DigiSession()
 slot=robot_metrics.slots[1] if robot_metrics and len(robot_metrics.slots)>1 else None
 digi.telemetry=slot
 try:
  while True:
   try:
    jobs=await asyncio.to_thread(request,'rpc/claim_consulta_job',{})
    if not jobs:
     if slot and slot.state=='queue_error':slot.state='idle'
     await digi.close_idle();await asyncio.sleep(3);continue
    job=jobs[0]
    if slot:slot.begin('consigx' if job.get('servico')=='tjba_margem' else 'digimais')
    try:result=await process_digimais(job,digi)
    except Exception:result={'status':'erro','message':'Falha interna no robô. Verificar a instalação e conectividade da VPS.'}
    if slot:slot.saving(result)
    result['consultado_em']=datetime.now(timezone.utc).isoformat()
    # Hold this slot until persistence succeeds. Never repeat the bank query.
    while True:
     try:
      await asyncio.to_thread(request,'consulta_jobs?id=eq.'+job['id'],result,'PATCH');break
     except Exception:
      print('Falha ao salvar resultado Digi+; tentando somente a gravação.',flush=True)
      await asyncio.sleep(10)
    if slot:slot.saved()
   except Exception:
    if slot:slot.state='queue_error'
    print('Fila Digi+ indisponível; nova tentativa em 10 segundos.',flush=True)
    await asyncio.sleep(10)

 finally:await digi.close()

async def main_async():
 global robot_metrics
 from robot_metrics import RobotMetrics
 workers=os.environ.get('DIGIMAIS_WORKERS','2')
 if workers not in ('1','2'):raise ValueError('DIGIMAIS_WORKERS deve ser 1 ou 2.')
 robot_metrics=RobotMetrics(int(workers))
 print('Executores Digi+: '+workers+'; ConsigX permanece serial; máximo de 2 navegadores.',flush=True)
 heartbeat=asyncio.create_task(robot_metrics.publish_loop())
 tasks=[asyncio.create_task(primary_loop())]
 if workers=='2':tasks.append(asyncio.create_task(digimais_loop()))
 try:await asyncio.gather(*tasks)
 finally:
  for task in tasks+[heartbeat]:task.cancel()
  await asyncio.gather(*tasks,heartbeat,return_exceptions=True)

def main():asyncio.run(main_async())
if __name__=='__main__':main()
