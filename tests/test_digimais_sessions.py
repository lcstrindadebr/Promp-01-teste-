"""No bank traffic: exercise browser reuse with the existing chat flow fixtures."""
import asyncio,sys,types,unittest
from unittest.mock import AsyncMock,patch
sys.path.insert(0,'vps')
from robot import DigiSession
from test_robot_flow import Browser,Engine,Timeout

CLIENT={'user_id':'owner-a','nome':'TESTE','cpf':'00123456789','telefone':'11999999999'}
class SessionsTests(unittest.IsolatedAsyncioTestCase):
 def engines(self,fail=False):
  self.actions=[];self.browsers=[]
  def factory():
   browser=Browser(self.actions,fail);self.browsers.append(browser);return Engine(browser)
  fake=types.ModuleType('playwright.async_api');fake.async_playwright=factory;fake.TimeoutError=Timeout
  return patch.dict(sys.modules,{'playwright':types.ModuleType('playwright'),'playwright.async_api':fake})
 async def test_reuse_across_customers_but_each_chat_is_clean(self):
  with self.engines('positive'):
   session=DigiSession()
   try:
    for cpf in ['00123456789','00000000191']:
     result=await session.run({**CLIENT,'cpf':cpf},on_checkpoint=AsyncMock())
     self.assertEqual(result['status'],'concluida');self.assertEqual(result['valor_parcela'],123.4)
    self.assertEqual(len(self.browsers),1)
    contexts=self.browsers[0].contexts
    self.assertEqual(len(contexts),4);self.assertEqual(len({id(c) for c in contexts}),4)
    self.assertTrue(all(c.closed for c in contexts))
    self.assertEqual(sum(a[0]=='launch' for a in self.actions),1)
    self.assertTrue(self.browsers[0].connected)
   finally:await session.close()
   self.assertFalse(self.browsers[0].connected)
 async def test_nonclient_skips_parcela_and_reuses_browser(self):
  with self.engines():
   session=DigiSession()
   try:
    for _ in range(2):self.assertEqual((await session.run(CLIENT))['status'],'nao_cliente')
    self.assertEqual(len(self.browsers),1);self.assertEqual(len(self.browsers[0].contexts),2)
   finally:await session.close()
 async def test_isolation_when_owner_changes_and_browser_disconnects(self):
  with self.engines():
   session=DigiSession()
   try:
    await session.run(CLIENT)
    await session.run({**CLIENT,'user_id':'owner-b'})
    self.assertEqual(len(self.browsers),2);self.assertFalse(self.browsers[0].connected)
    self.browsers[-1].connected=False
    await session.run({**CLIENT,'user_id':'owner-b'})
    self.assertEqual(len(self.browsers),3)
   finally:await session.close()
 async def test_idle_age_and_job_limit_recycle(self):
  with self.engines():
   session=DigiSession(max_jobs=1)
   try:
    await session.run(CLIENT);await session.run(CLIENT)
    self.assertEqual(len(self.browsers),2)
    session.last_used-=91;await session.close_idle();self.assertIsNone(session.browser)
    await session.run(CLIENT);session.max_jobs=100;session.started-=601;await session.run(CLIENT)
    self.assertEqual(len(self.browsers),4)
   finally:await session.close()
 async def test_failure_discards_browser_without_repeating_cpf(self):
  with self.engines(True):
   session=DigiSession()
   try:
    result=await session.run(CLIENT)
    self.assertEqual(result['status'],'erro');self.assertIsNone(session.browser)
    self.assertEqual(len(self.browsers),1)
    self.assertEqual(sum(a==('click','button.send[type="submit"]') for a in self.actions),0)
   finally:await session.close()
 async def test_failure_after_sending_cpf_never_repeats_query(self):
  with self.engines():
   session=DigiSession()
   try:
    with patch('robot.parse_response',side_effect=OSError('lost connection')):
     result=await session.run(CLIENT)
    self.assertEqual(result['status'],'erro');self.assertIsNone(session.browser)
    self.assertEqual(sum(a==('click','button.send[type="submit"]') for a in self.actions),1)
    self.assertEqual(len(self.browsers),1)
   finally:await session.close()
 async def test_busy_executor_rejects_overlap_and_cancellation_cleans_up(self):
  with self.engines():
   session=DigiSession();entered=asyncio.Event()
   async def running(*args,**kwargs):entered.set();await asyncio.Event().wait()
   with patch('robot.run',side_effect=running):
    task=asyncio.create_task(session.run(CLIENT));await entered.wait()
    with self.assertRaises(RuntimeError):await session.run(CLIENT)
    task.cancel()
    with self.assertRaises(asyncio.CancelledError):await task
   self.assertFalse(session.busy);self.assertIsNone(session.browser)
