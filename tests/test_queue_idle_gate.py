import asyncio,io,json,os,sys,tempfile,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch
os.environ.setdefault('SUPABASE_URL','http://localhost');os.environ.setdefault('SUPABASE_SERVICE_ROLE_KEY','test')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
import worker
from robot_metrics import Slot

class Capacity:
 target=100

def not_found():
 return urllib.error.HTTPError('http://localhost/rest/v1/rpc/claim_consulta_jobs_for_api',404,'Not Found',{},io.BytesIO(b'{}'))

class QueueIdleGateTests(unittest.TestCase):
 def test_empty_queue_backs_off_to_thirty_seconds(self):
  gate=worker.QueueIdleGate()
  for _ in range(10):gate.empty()
  self.assertEqual(gate.delay,30)
  gate.found();self.assertEqual(gate.remaining(),0)

 def test_empty_answer_right_after_a_claim_is_treated_as_contention(self):
  gate=worker.QueueIdleGate();gate.found();gate.empty()
  self.assertEqual(gate.delay,0);self.assertLessEqual(gate.remaining(),3)

class ApiDispatcherTests(unittest.IsolatedAsyncioTestCase):
 async def asyncSetUp(self):
  self.spool=tempfile.TemporaryDirectory()
  self.patches=[patch.object(worker,'SPOOL_DIR',Path(self.spool.name)/'spool'),patch.object(worker,'MODE','live')]
  for p in self.patches:p.start()
 async def asyncTearDown(self):
  for p in self.patches:p.stop()
  self.spool.cleanup()

 async def run_slots(self,request,seconds=.4,process=None):
  real_sleep=asyncio.sleep
  async def quick(_):await real_sleep(.001)
  async def done(job,adapter):return {'status':'concluida'}
  capacity=Capacity();dispatcher=worker.ApiDispatcher(capacity)
  with patch.object(worker,'request',side_effect=request),patch.object(worker.asyncio,'sleep',side_effect=quick),\
       patch.object(worker,'process_digimais',side_effect=process or done):
   tasks=[asyncio.create_task(worker.api_loop(i,capacity,Slot(f'api-{i+1}'),{},dispatcher)) for i in range(100)]
   tasks.append(asyncio.create_task(dispatcher.run()))
   await real_sleep(seconds)
   for task in tasks:task.cancel()
   await asyncio.gather(*tasks,return_exceptions=True)
  return dispatcher

 async def test_hundred_idle_slots_send_a_single_batch_probe(self):
  calls=[]
  def request(path,payload=None,method='POST',timeout=30):calls.append((path,payload));return []
  await self.run_slots(request)
  self.assertEqual(len(calls),1)
  self.assertEqual(calls[0][0],'rpc/claim_consulta_jobs_for_api')
  self.assertEqual(calls[0][1]['p_slots'],list(range(1,101)))

 async def test_batch_jobs_reach_their_slots_and_are_saved_with_the_attempt_filter(self):
  pending=list(range(30));saved=[]
  def request(path,payload=None,method='POST',timeout=30):
   if method=='PATCH':saved.append(path);return None
   jobs=[]
   for slot in payload['p_slots']:
    if not pending:break
    jobs.append({'id':str(pending.pop(0)),'attempts':1,'api_slot':slot})
   return jobs
  await self.run_slots(request,1)
  self.assertEqual(len(saved),30)
  self.assertTrue(all('&attempts=eq.1' in route and 'status=eq.processando' in route for route in saved))
  self.assertEqual(list((Path(self.spool.name)/'spool').glob('*.json')),[])

 async def test_falls_back_to_per_slot_claim_before_the_migration(self):
  pending=list(range(5));calls=[]
  def request(path,payload=None,method='POST',timeout=30):
   calls.append(path)
   if method=='PATCH':return None
   if path=='rpc/claim_consulta_jobs_for_api':raise not_found()
   return [{'id':str(pending.pop(0)),'attempts':1,'api_slot':payload['p_slot']}] if pending else []
  dispatcher=await self.run_slots(request,1)
  self.assertFalse(dispatcher.batch_supported)
  self.assertEqual(calls.count('rpc/claim_consulta_jobs_for_api'),1)
  self.assertEqual(sum(1 for c in calls if c.startswith('consulta_jobs?')),5)

 async def test_result_stays_on_disk_until_the_database_confirms_and_is_replayed(self):
  route='consulta_jobs?id=eq.1&status=eq.processando&attempts=eq.1'
  path=worker.spool_write(route,{'status':'concluida'})
  self.assertTrue(path.exists())
  saved=[]
  with patch.object(worker,'request',side_effect=lambda r,p=None,m='POST',t=30:saved.append((r,p,m))):
   self.assertTrue(await worker.replay_spool())
  self.assertEqual(saved,[(route,{'status':'concluida'},'PATCH')]);self.assertFalse(path.exists())

 async def test_start_releases_previous_reservations_only_after_pending_results(self):
  worker.spool_write('consulta_jobs?id=eq.9',{'status':'concluida'})
  calls=[]
  def failing(path,payload=None,method='POST',timeout=30):
   calls.append(path);raise OSError('offline')
  with patch.object(worker,'request',side_effect=failing):await worker.release_previous_reservations()
  self.assertNotIn('rpc/release_stale_jobs',calls)
  calls.clear()
  with patch.object(worker,'request',side_effect=lambda path,payload=None,method='POST',timeout=30:calls.append(path) or {}):
   await worker.release_previous_reservations()
  self.assertEqual(calls,['consulta_jobs?id=eq.9','rpc/release_stale_jobs'])

if __name__=='__main__':unittest.main()
