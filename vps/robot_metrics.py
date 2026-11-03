"""Aggregate executor health. No CPF, names, job IDs, portal data or credentials."""
import asyncio,json,os,time
from collections import deque
from datetime import datetime,timezone
from pathlib import Path

STATE_PATH=Path('/run/apoiarcred-robots/state.json')

def stamp():return datetime.now(timezone.utc).isoformat()

class Slot:
 def __init__(self,name):
  self.name=name;self.service=None;self.state='idle';self.progress=0
  self.started=None;self.duration=None;self.last_activity=stamp();self.pending=None
  self.events=deque(maxlen=10000)
 def begin(self,service):
  self.service=service;self.state='consulting';self.progress=0
  self.started=time.monotonic();self.duration=None;self.pending=None;self.last_activity=stamp()
 def report(self,progress):
  self.progress=max(0,min(100,int(progress)));self.last_activity=stamp()
 def saving(self,result):
  self.duration=max(0,time.monotonic()-self.started) if self.started is not None else 0
  self.pending=result.get('status');self.state='saving';self.last_activity=stamp()
 def saved(self):
  if self.pending is None:return
  self.events.append((time.monotonic(),self.pending,self.duration or 0))
  self.state='idle';self.progress=0;self.started=None;self.last_activity=stamp();self.pending=None
 def snapshot(self):
  now=time.monotonic()
  while self.events and now-self.events[0][0]>3600:self.events.popleft()
  events=list(self.events);count=len(events)
  success=sum(status in ('concluida','nao_cliente','nao_encontrado') for _,status,_ in events)
  errors=sum(status=='erro' for _,status,_ in events)
  return dict(id=self.name,service=self.service,state=self.state,progress=self.progress,
   elapsed_seconds=round(now-self.started,1) if self.started is not None else None,
   last_duration_seconds=round(self.duration,1) if self.duration is not None else None,
   last_activity=self.last_activity,finished_last_hour=count,conclusive_last_hour=success,
   errors_last_hour=errors,review_last_hour=sum(status=='revisao' for _,status,_ in events),
   average_seconds=round(sum(duration for _,_,duration in events)/count,1) if count else None)

class RobotMetrics:
 def __init__(self,workers,path=STATE_PATH):
  self.path=Path(path);self.started_at=stamp();self.slots=[Slot('principal')]
  if workers==2:self.slots.append(Slot('digimais-2'))
 def payload(self):return dict(updated_at=stamp(),started_at=self.started_at,slots=[s.snapshot() for s in self.slots])
 def write(self,data):
  self.path.parent.mkdir(parents=True,exist_ok=True)
  temporary=self.path.with_suffix('.tmp')
  temporary.write_text(json.dumps(data));temporary.chmod(0o600);os.replace(temporary,self.path)
 async def publish_loop(self):
  while True:
   try:await asyncio.to_thread(self.write,self.payload())
   except Exception:print('Monitor dos robôs: não foi possível publicar o estado local.',flush=True)
   await asyncio.sleep(5)
