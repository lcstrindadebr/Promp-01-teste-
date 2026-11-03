"""Send aggregate host metrics to Supabase; no customer/process data."""
import json,os,shutil,subprocess,time,urllib.request
from pathlib import Path
from datetime import datetime,timezone

def cpu_ticks(path='/proc/stat'):
 v=[int(x) for x in Path(path).read_text().splitlines()[0].split()[1:9]]
 return sum(v),v[3]+v[4]

def cpu_percent(previous,current):
 total=current[0]-previous[0];idle=current[1]-previous[1]
 return round(max(0,min(100,100*(total-idle)/total)),1) if total>0 else None

def memory(path='/proc/meminfo'):
 d={line.split(':')[0]:int(line.split()[1])*1024 for line in Path(path).read_text().splitlines()}
 total=d['MemTotal'];available=d['MemAvailable'];swap=d.get('SwapTotal',0)
 return dict(total=total,available=available,used=max(0,total-available),percent=round(100*(total-available)/total,1),swap_total=swap,swap_used=max(0,swap-d.get('SwapFree',0)))

def worker_state():
 try:
  r=subprocess.run(['systemctl','show','apoiarcred-robo','--property=ActiveState','--value'],capture_output=True,text=True,timeout=2)
  state=r.stdout.strip()
  return state if r.returncode==0 and state in ('active','inactive','failed','activating','deactivating','reloading') else 'unknown'
 except (OSError,subprocess.TimeoutExpired):return 'unknown'

def robot_activity(path='/run/apoiarcred-robots/state.json'):
 try:
  source=Path(path)
  if source.stat().st_size>32768:return None
  data=json.loads(source.read_text())
  if not isinstance(data,dict) or not isinstance(data.get('slots'),list):return None
  keys=('id','service','state','progress','elapsed_seconds','last_duration_seconds','last_activity',
        'finished_last_hour','conclusive_last_hour','errors_last_hour','review_last_hour','average_seconds')
  return dict(updated_at=data.get('updated_at'),started_at=data.get('started_at'),
   slots=[{key:s.get(key) for key in keys} for s in data['slots'][:2] if isinstance(s,dict)])
 except (OSError,ValueError,TypeError):return None

def snapshot(previous,current):
 disk=shutil.disk_usage('/opt/apoiarcred' if Path('/opt/apoiarcred').exists() else '/')
 mode=os.environ.get('ROBOT_MODE','disabled')
 return dict(cpu_percent=cpu_percent(previous,current),cpu_count=os.cpu_count(),memory=memory(),disk=dict(total=disk.total,used=disk.used,free=disk.free,percent=round(100*disk.used/disk.total,1)),uptime_seconds=int(float(Path('/proc/uptime').read_text().split()[0])),worker=worker_state(),robot_mode=mode if mode in ('live','disabled','demo') else 'unknown',robots=robot_activity())

def publish(payload):
 url=os.environ['SUPABASE_URL'].rstrip('/');key=os.environ['SUPABASE_SERVICE_ROLE_KEY']
 headers={'apikey':key,'Content-Type':'application/json','Prefer':'resolution=merge-duplicates'}
 if not key.startswith('sb_secret_'):headers['Authorization']='Bearer '+key
 body=dict(id='principal',updated_at=datetime.now(timezone.utc).isoformat(),payload=payload)
 req=urllib.request.Request(url+'/rest/v1/vps_monitoramento?on_conflict=id',data=json.dumps(body).encode(),headers=headers,method='POST')
 with urllib.request.urlopen(req,timeout=4) as response:response.read()

def main():
 previous=cpu_ticks();time.sleep(1)
 while True:
  start=time.monotonic()
  try:
   current=cpu_ticks();data=snapshot(previous,current);previous=current;publish(data)
  except Exception:print('Monitor: coleta ou envio indisponível; nova tentativa em 5 segundos.',flush=True)
  time.sleep(max(.1,5-(time.monotonic()-start)))
if __name__=='__main__':main()
