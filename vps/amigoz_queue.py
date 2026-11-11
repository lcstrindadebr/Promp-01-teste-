"""Persistent Amigoz import executor, hosted by the API service on the VPS.

One bounded consumer; results survive the browser. An uncertain interrupted call
is held for review instead of blindly issuing another provider request.
"""
import time
import threading
import amigoz_api


def process(job, config):
 payload={'cpf':job['cpf'],'convenio_id':int(job['convenio'].removeprefix('amigoz_')),
          'modo':job['modo'],'numero_matricula':job.get('numero_matricula')}
 result=amigoz_api.consultation(config,payload)
 operations=[result[key] for key in ('saque','margem') if key in result]
 failed=[value for value in operations if value.get('status')!='respondido']
 status='erro' if len(failed)==len(operations) else 'revisao' if failed else 'concluida'
 return status,result,'Resultado parcial; confira os detalhes.' if failed and status=='revisao' else 'Consulta finalizada.'


def run(call, stop):
 while not stop.is_set():
  try:
   config=amigoz_api.configuration()
   if not config:
    stop.wait(10)
    continue # Keep queued work until an administrator supplies credentials.
   jobs=call('/rest/v1/rpc/claim_amigoz_import_job',{})
   if not jobs:
    stop.wait(3)
    continue
   job=jobs[0]
   try:
    status,result,message=process(job,config)
   except amigoz_api.AmigozError as error:
    status,result,message='erro',None,error.message
   except Exception:
    status,result,message='erro',None,'Falha interna no executor Amigoz. Confira a configuração e os dados obrigatórios.'
   payload=dict(p_id=job['id'],p_lease=job['lease'],p_status=status,p_resultado=result,p_message=message)
   # Retry only saving. Never repeat an external call after a database outage.
   while not stop.is_set():
    try:
     call('/rest/v1/rpc/finish_amigoz_import_job',payload)
     break
    except Exception:
     print('Amigoz | falha ao salvar resultado; repetindo somente gravação.',flush=True)
     stop.wait(5)
  except Exception:
   print('Amigoz | fila indisponível; nova tentativa em 10 segundos.',flush=True)
   stop.wait(10)


def start(call):
 stop=threading.Event()
 thread=threading.Thread(target=run,args=(call,stop),name='amigoz-import-queue',daemon=True)
 thread.start()
 return stop
