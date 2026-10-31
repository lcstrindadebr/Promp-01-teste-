"""No real bank/network: exercise the full step sequence with a fake Playwright page."""
import sys,types,unittest
from unittest.mock import patch
sys.path.insert(0,'vps')
import robot
class Timeout(Exception):pass
class Locator:
 def __init__(self,page,name):self.page=page;self.name=name
 def nth(self,i):return Locator(self.page,self.name+str(i))
 async def fill(self,value):self.page.actions.append(('fill',self.name,value))
 async def click(self,**kwargs):
  self.page.actions.append(('click',self.name))
  if self.page.fail and 'Boleto' in self.name:raise Timeout()
  if self.name=='button.send[type="submit"]':self.page.sent=True
  if self.name=='button.v-chat-button':self.page.context.pages.append(self.page.context.chat)
 async def count(self):
  if self.name=='body':return 1
  if self.name.startswith('input') and self.page.url.startswith('https://widget.'):return 2
  return 0
 async def is_visible(self):return False
 async def inner_text(self,**kwargs):return 'Desculpe, o seu documento não foi localizado para esse produto.' if self.page.sent else 'CPF'
class Page:
 def __init__(self,actions,fail=False):self.actions=actions;self.sent=False;self.fail=fail;self.url='https://www.bancodigimais.com.br/';self.frames=[];self.main_frame=None
 def is_closed(self):return False
 def set_default_timeout(self,*a):pass
 async def goto(self,*a,**kw):self.url=a[0];self.actions.append(('goto',a[0]));return types.SimpleNamespace(status=200)
 async def wait_for_load_state(self,*a):pass
 async def add_locator_handler(self,*a):pass
 async def wait_for_function(self,*a,**kw):self.actions.append(('wait-cpf',))
 def get_by_role(self,role,**kw):return Locator(self,str(kw.get('name')))
 def get_by_placeholder(self,name,**kw):return Locator(self,name)
 def locator(self,name):return Locator(self,name)
class Opened:
 def __init__(self,page):self.page=page
 async def __aenter__(self):return self
 async def __aexit__(self,*a):pass
 @property
 def value(self):
  async def resolve():return self.page
  return resolve()
class Context:
 def __init__(self,actions,fail):
  self.home=Page(actions);self.chat=Page(actions,fail);self.chat.url='https://widget.voltdigital.com.br/chat';self.pages=[self.home];self.home.context=self;self.chat.context=self
 async def new_page(self):return self.home
 def expect_page(self,**kw):return Opened(self.chat)
 async def close(self):pass
class Browser:
 def __init__(self,actions,fail):self.context=Context(actions,fail)
 async def new_context(self,**kw):return self.context
 async def close(self):pass
class Engine:
 def __init__(self,browser):self.browser=browser;self.chromium=self
 async def __aenter__(self):return self
 async def __aexit__(self,*a):pass
 async def launch(self,**kw):
  self.browser.context.home.actions.append(('launch',tuple(kw.get('args',[]))))
  return self.browser
class FlowTests(unittest.IsolatedAsyncioTestCase):
 async def execute(self,fail=False):
  actions=[];events=[];engine=Engine(Browser(actions,fail))
  fake=types.ModuleType('playwright.async_api');fake.async_playwright=lambda:engine;fake.TimeoutError=Timeout
  async def progress(percent,stage):events.append((percent,stage))
  with patch.dict(sys.modules,{'playwright':types.ModuleType('playwright'),'playwright.async_api':fake}):
   result=await robot.run({'nome':'CLIENTE TESTE','cpf':'00123456789','telefone':'11999999999'},on_progress=progress)
  return result,actions,events
 async def test_complete_negative_flow_and_format(self):
  result,actions,events=await self.execute();self.assertEqual(result['status'],'nao_cliente');self.assertEqual(result['progress'],100)
  self.assertIn(('fill','Digitar...','001.234.567-89'),actions);self.assertIn(('click','button.send[type="submit"]'),actions)
  self.assertEqual([e[0] for e in events],sorted(e[0] for e in events));self.assertIn(('goto',robot.BANK_URL),actions)
  launch=next(a for a in actions if a[0]=='launch')[1]
  self.assertIn('--disable-http2',launch);self.assertIn('--disable-quic',launch);self.assertNotIn('--ignore-certificate-errors',launch)
 async def test_timeout_includes_exact_stage_not_nonclient(self):
  result,actions,events=await self.execute(True);self.assertEqual(result['status'],'erro');self.assertEqual(result['progress'],50);self.assertIn('Selecionar boleto',result['message'])
if __name__=='__main__':unittest.main()

