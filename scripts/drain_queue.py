"""Pause new claims and wait for persisted results before updater stops the worker."""
import argparse,json,shlex,time,uuid
from pathlib import Path
from urllib.request import Request,urlopen

def rpc(app,token,release=False):
 env={}
 for line in (app/'.env').read_text().splitlines():
  if line.startswith(('SUPABASE_URL=','SUPABASE_SERVICE_ROLE_KEY=')):
   k,v=line.split('=',1);env[k]=shlex.split(v)[0]
 key=env['SUPABASE_SERVICE_ROLE_KEY'];headers={'apikey':key,'Content-Type':'application/json'}
 if not key.startswith('sb_secret_'):headers['Authorization']='Bearer '+key
 req=Request(env['SUPABASE_URL'].rstrip('/')+'/rest/v1/rpc/consulta_queue_maintenance',data=json.dumps({'p_token':token,'p_release':release}).encode(),headers=headers)
 with urlopen(req,timeout=20) as r:return json.load(r)

def drain(app,release=False,call=rpc,wait=time.sleep,clock=time.monotonic):
 marker=app/'.update-queue-token'
 if release:
  if marker.exists():call(app,marker.read_text().strip(),True);marker.unlink()
  return
 token=str(uuid.uuid4());marker.touch(mode=0o600,exist_ok=True);marker.chmod(0o600);marker.write_text(token)
 complete=False
 try:
  deadline=clock()+600
  while True:
   active=call(app,token)
   if active==0:complete=True;print('Fila pausada; consultas em execução já terminaram e foram salvas.',flush=True);return
   print(f'Aguardando {active} consulta(s) em execução antes de atualizar...',flush=True)
   if clock()>=deadline:raise RuntimeError('Consultas ainda em execução; atualização cancelada sem interromper o robô. Confira trabalhos presos em processando.')
   wait(3)
 finally:
  if not complete:
   call(app,token,True);marker.unlink(missing_ok=True)

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,required=True);parser.add_argument('--release',action='store_true');args=parser.parse_args()
 try:drain(args.app,args.release)
 except Exception as error:
  print('Não foi possível preparar/liberar a fila para atualização: '+type(error).__name__,flush=True)
  raise SystemExit(1)
