"""Supabase queue worker. Service key remains exclusively on the VPS."""
import asyncio,json,os,time,urllib.request,urllib.error
from datetime import datetime,timezone
URL=os.environ['SUPABASE_URL'].rstrip('/')
KEY=os.environ['SUPABASE_SERVICE_ROLE_KEY']
MODE=os.environ.get('ROBOT_MODE','disabled')
def request(path,payload=None,method='POST'):
 data=json.dumps(payload).encode() if payload is not None else None
 req=urllib.request.Request(URL+'/rest/v1/'+path,data=data,method=method,headers={'apikey':KEY,'Authorization':'Bearer '+KEY,'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=30) as res:
  text=res.read().decode();return json.loads(text) if text else None

def process(job):
 if MODE=='demo':return {'status':'revisao','message':'Worker em modo demo. Nenhuma consulta realizada; use a demonstração local para valores fictícios.'}
 if MODE!='live':return {'status':'revisao','message':'Robô desativado. Ative somente após homologação.'}
 from robot import run
 return asyncio.run(run(job))

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
