import asyncio,importlib.util,os,threading,unittest
from pathlib import Path
from unittest.mock import AsyncMock,patch

class ConcurrentDigiTests(unittest.IsolatedAsyncioTestCase):
 async def test_two_slots_distinct_jobs_and_save_retry_never_requeries(self):
  path=Path(__file__).resolve().parents[1]/'vps/worker.py'
  with patch.dict(os.environ,{'SUPABASE_URL':'https://example.invalid','SUPABASE_SERVICE_ROLE_KEY':'fake','DIGIMAIS_WORKERS':'2'}):
   spec=importlib.util.spec_from_file_location('worker_parallel_test',path);worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
  jobs=[{'id':'a','cpf':'00000000191','servico':'digimais_saldo_parcela'},{'id':'b','cpf':'00000000272','servico':'digimais_saldo_parcela'}]
  lock=threading.Lock();barrier=asyncio.Event();processed=[];saved=set();fail_once=True
  def request(route,data=None,method='POST',timeout=30):
   nonlocal fail_once
   with lock:
    if route=='rpc/claim_tjba_job':return []
    if route=='rpc/claim_consulta_job':return [jobs.pop(0)] if jobs else []
    if method=='PATCH':
     if fail_once:fail_once=False;raise OSError('temporary database outage')
     saved.add(route);return None
   raise AssertionError(route)
  adapters=[]
  async def process(job,adapter):
   adapters.append(adapter);processed.append(job['id'])
   if len(processed)==2:barrier.set()
   await asyncio.wait_for(barrier.wait(),3)
   return {'status':'concluida'}
  original_sleep=asyncio.sleep
  async def short_sleep(seconds):await original_sleep(.001)
  with patch('robot_metrics.RobotMetrics.publish_loop',new=AsyncMock()),patch.object(worker,'request',side_effect=request),patch.object(worker,'process_digimais',side_effect=process),patch.object(worker.asyncio,'sleep',side_effect=short_sleep),patch.dict(os.environ,{'DIGIMAIS_WORKERS':'2'}):
   task=asyncio.create_task(worker.main_async())
   try:
    async with asyncio.timeout(5):
     while len(saved)<2 or sum(s.snapshot()['finished_last_hour'] for s in worker.robot_metrics.slots)<2:await original_sleep(.005)
   finally:
    task.cancel()
    with self.assertRaises(asyncio.CancelledError):await task
  self.assertCountEqual(processed,['a','b']);self.assertEqual(len(saved),2);self.assertIsNot(adapters[0],adapters[1]);self.assertEqual([s.snapshot()['finished_last_hour'] for s in worker.robot_metrics.slots],[1,1])
 async def test_single_worker_setting_does_not_start_extra_executor(self):
  path=Path(__file__).resolve().parents[1]/'vps/worker.py'
  with patch.dict(os.environ,{'SUPABASE_URL':'https://example.invalid','SUPABASE_SERVICE_ROLE_KEY':'fake','DIGIMAIS_WORKERS':'1'}):
   spec=importlib.util.spec_from_file_location('worker_serial_test',path);worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
   with patch.object(worker,'primary_loop',new=AsyncMock()) as primary,patch.object(worker,'digimais_loop',new=AsyncMock()) as secondary:
    await worker.main_async();primary.assert_awaited_once();secondary.assert_not_awaited()
