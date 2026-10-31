"""Supabase queue worker. Service key remains exclusively on the VPS."""
import asyncio,json,os,time,urllib.request,urllib.error
from datetime import datetime,timezone
URL=os.environ['SUPABASE_URL'].rstrip('/')
KEY=os.environ['SUPABASE_SERVICE_ROLE_KEY']
MODE=os.environ.get('ROBOT_MODE','disabled')
def request(path,payload=None,method='POST',timeout=30):
 data=json.dumps(payload).encode() if payload is not None else None
 headers={'apikey':KEY,'Content-Type':'application/json'}
 if not KEY.startswith('sb_secret_'):headers['Authorization']='Bearer '+KEY
 req=urllib.request.Request(URL+'/rest/v1/'+path,data=data,method=method,headers=headers)
 with urllib.request.urlopen(req,timeout=timeout) as res:
  text=res.read().decode();return json.loads(text) if text else None

def process(job):
 if job.get('servico','digimais_saldo_parcela')!='digimais_saldo_parcela':return {'status':'revisao','message':'Tipo de higienização sem robô disponível.'}
 if MODE=='demo':return {'status':'revisao','message':'Worker em modo demo. Nenhuma consulta realizada; use a demonstração local para valores fictícios.'}
 if MODE!='live':return {'status':'revisao','message':'Robô desativado. Ative somente após homologação.'}
 from robot import run
 async def execute():
  # Only the latest pending progress matters; database latency must not pause chat clicks.
  queue=asyncio.Queue(maxsize=1)
  started=time.monotonic()
  async def report(percent,stage):
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
   result=await run(job,on_progress=report,on_checkpoint=checkpoint)
   await queue.join() # Finish progress writes before saving the final result.
   return result
  finally:
   writer.cancel()
   try:await writer
   except asyncio.CancelledError:pass
 return asyncio.run(execute())

def main():
 while True:
  try:
   jobs=request('rpc/claim_consulta_job',{})
   if not jobs:time.sleep(3);continue
   job=jobs[0]
   try:result=process(job)
   except Exception:result={'status':'erro','message':'Falha interna no robô. Verificar a instalação e conectividade da VPS.'}
   result['consultado_em']=datetime.now(timezone.utc).isoformat()
   # Retry saving this result, not the bank consultation.
   while True:
    try:request('consulta_jobs?id=eq.'+job['id'],result,method='PATCH');break
    except Exception:print('Falha ao salvar resultado; tentando novamente.',flush=True);time.sleep(10)
  except Exception:
   print('Fila indisponível; nova tentativa em 10 segundos.',flush=True);time.sleep(10)
if __name__=='__main__':main()
