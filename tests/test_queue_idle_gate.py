import asyncio,os,sys,unittest
from pathlib import Path
from unittest.mock import patch
os.environ.setdefault('SUPABASE_URL','http://localhost');os.environ.setdefault('SUPABASE_SERVICE_ROLE_KEY','test')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
import worker
from robot_metrics import Slot

class Capacity:
 target=100

class QueueIdleGateTests(unittest.IsolatedAsyncioTestCase):
 def test_empty_queue_backs_off_to_thirty_seconds(self):
  gate=worker.QueueIdleGate()
  for _ in range(10):gate.empty()
  self.assertEqual(gate.delay,30)
  gate.found();self.assertEqual(gate.remaining(),0)

 def test_empty_answer_right_after_a_claim_is_treated_as_contention(self):
  gate=worker.QueueIdleGate();gate.found();gate.empty()
  self.assertEqual(gate.delay,0);self.assertLessEqual(gate.remaining(),3)

 async def run_slots(self,request,seconds=.3):
  gate=worker.QueueIdleGate();real_sleep=asyncio.sleep
  async def quick(_):await real_sleep(.001)
  with patch.object(worker,'MODE','live'),patch.object(worker,'request',side_effect=request),patch.object(worker.asyncio,'sleep',side_effect=quick):
   tasks=[asyncio.create_task(worker.api_loop(i,Capacity(),Slot(f'api-{i+1}'),{},gate)) for i in range(100)]
   await real_sleep(seconds)
   for task in tasks:task.cancel()
   await asyncio.gather(*tasks,return_exceptions=True)

 async def test_hundred_idle_slots_send_a_single_probe(self):
  calls=[]
  def request(path,payload=None,method='POST'):calls.append(path);return []
  await self.run_slots(request)
  self.assertEqual(calls,['rpc/claim_consulta_job_for_api'])

 async def test_claims_keep_flowing_while_the_queue_has_work(self):
  jobs=iter(range(30));saved=[]
  def request(path,payload=None,method='POST'):
   if method=='PATCH':saved.append(path);return None
   job=next(jobs,None)
   return [] if job is None else [{'id':str(job),'attempts':1,'api_slot':payload['p_slot']}]
  async def process(job,adapter):return {'status':'concluida'}
  with patch.object(worker,'process_digimais',side_effect=process):
   await self.run_slots(request,1)
  self.assertEqual(len(saved),30)

if __name__=='__main__':unittest.main()
