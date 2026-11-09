import asyncio,importlib.util,os,sys,threading,unittest
from pathlib import Path
from unittest.mock import AsyncMock,patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))

class ConcurrentDigiTests(unittest.IsolatedAsyncioTestCase):
 async def test_four_slots_share_both_queues_and_save_retry_never_requeries(self):
  path=Path(__file__).resolve().parents[1]/'vps/worker.py'
  with patch.dict(os.environ,{'SUPABASE_URL':'https://example.invalid','SUPABASE_SERVICE_ROLE_KEY':'fake','ROBOT_WORKERS':'4'}):
   spec=importlib.util.spec_from_file_location('worker_parallel_test',path);worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
  jobs=[{'id':'a','cpf':'00000000191','servico':'digimais_saldo_parcela'},{'id':'b','cpf':'00000000272','servico':'digimais_saldo_parcela'}]
  consigx=[{'id':key,'cpf':'00000000191','servico':'tjba_margem','user_id':key} for key in ('c','d')]
  lock=threading.Lock();barrier=asyncio.Event();processed=[];saved=set();fail_once=True
  def request(route,data=None,method='POST',timeout=30):
   nonlocal fail_once
   with lock:
    if route=='rpc/claim_tjba_job_for_robot':return [consigx.pop(0)] if consigx else []
    if route=='rpc/claim_consulta_job_for_robot':return [jobs.pop(0)] if jobs else []
    if method=='PATCH':
     if fail_once:fail_once=False;raise OSError('temporary database outage')
     saved.add(route);return None
   raise AssertionError(route)
  adapters=[]
  async def process(job,adapter):
   adapters.append(adapter);processed.append(job['id'])
   if len(processed)==4:barrier.set()
   await asyncio.wait_for(barrier.wait(),3)
   return {'status':'concluida'}
  original_sleep=asyncio.sleep
  async def short_sleep(seconds):await original_sleep(.001)
  async def full_capacity(capacity):
   capacity.target=capacity.maximum
   await asyncio.Future()
  with patch.object(worker.RobotCapacity,'watch',full_capacity),patch('robot_metrics.RobotMetrics.publish_loop',new=AsyncMock()),patch.object(worker,'request',side_effect=request),patch.object(worker,'process_digimais',side_effect=process),patch.object(worker,'process_tjba',side_effect=process),patch.object(worker.asyncio,'sleep',side_effect=short_sleep),patch.dict(os.environ,{'ROBOT_WORKERS':'4'}):
   task=asyncio.create_task(worker.main_async())
   try:
    async with asyncio.timeout(5):
     while len(saved)<4 or sum(s.snapshot()['finished_last_hour'] for s in worker.robot_metrics.slots)<4:await original_sleep(.005)
   finally:
    task.cancel()
    with self.assertRaises(asyncio.CancelledError):await task
  self.assertCountEqual(processed,['a','b','c','d']);self.assertEqual(saved,{'consulta_jobs?id=eq.a','consulta_jobs?id=eq.b','tjba_jobs?id=eq.c','tjba_jobs?id=eq.d'});self.assertEqual(len({id(adapter) for adapter in adapters}),4);self.assertEqual([s.snapshot()['finished_last_hour'] for s in worker.robot_metrics.slots],[1,1,1,1])
 async def test_single_worker_setting_does_not_start_extra_executor(self):
  path=Path(__file__).resolve().parents[1]/'vps/worker.py'
  with patch.dict(os.environ,{'SUPABASE_URL':'https://example.invalid','SUPABASE_SERVICE_ROLE_KEY':'fake','ROBOT_WORKERS':'1'}):
   spec=importlib.util.spec_from_file_location('worker_serial_test',path);worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
   with patch.object(worker,'robot_loop',new=AsyncMock()) as loop,patch.object(worker.RobotCapacity,'watch',new=AsyncMock()),patch('robot_metrics.RobotMetrics.publish_loop',new=AsyncMock()):
    await worker.main_async()
   loop.assert_awaited_once()
   self.assertEqual(len(worker.robot_metrics.slots),1)

 async def test_capacity_pauses_and_recovers_one_slot_at_a_time(self):
  path=Path(__file__).resolve().parents[1]/'vps/worker.py'
  with patch.dict(os.environ,{'SUPABASE_URL':'https://example.invalid','SUPABASE_SERVICE_ROLE_KEY':'fake'}):
   spec=importlib.util.spec_from_file_location('worker_capacity_test',path);worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
  cap=worker.RobotCapacity(3)
  healthy={'total':2048*1024**2,'available':800*1024**2}
  low={'total':healthy['total'],'available':200*1024**2}
  for _ in range(12):cap.observe(healthy,30)
  self.assertEqual(cap.target,3)
  cap.observe(low,30)
  self.assertEqual(cap.target,2)
  for _ in range(3):cap.observe(healthy,99)
  self.assertEqual(cap.target,1)
  for _ in range(6):cap.observe(healthy,30)
  self.assertEqual(cap.target,2)
