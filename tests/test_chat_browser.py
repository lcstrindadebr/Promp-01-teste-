import sys,unittest,types
sys.path.insert(0,'vps')
from chat_browser import open_bank,open_chat,open_direct_chat,describe_error,check_access,NavigationIssue,BANK_URL,CHAT_HOST
class Loc:
 def __init__(self,page,name):self.page=page;self.name=name
 async def count(self):
  if self.name=='body':return 1
  return 2 if self.name.startswith('input') and self.page.url.startswith('https://'+CHAT_HOST) else 0
 async def inner_text(self,**kw):return self.page.text
 async def click(self,**kw):
  if self.name=='button.v-chat-button':self.page.context.opened()
class Page:
 def __init__(self,url,context):self.url=url;self.context=context;self.frames=[];self.main_frame=object();self.text='Página normal';self.handlers=[];self.before_navigation=[]
 def set_default_timeout(self,*a):pass
 def is_closed(self):return False
 def locator(self,name):return Loc(self,name)
 def get_by_role(self,role,**kw):return Loc(self,str(kw.get('name')))
 async def add_locator_handler(self,loc,handler):self.handlers.append((loc.name,handler))
 async def goto(self,*a,**kw):self.url=a[0];self.before_navigation=list(self.handlers);return types.SimpleNamespace(status=200)
class Ctx:
 def __init__(self,variant):self.variant=variant;self.home=Page(BANK_URL,self);self.chat=Page('https://'+CHAT_HOST+'/chat',self);self.pages=[self.home]
 async def new_page(self):return self.home
 def opened(self):
  if self.variant=='new-tab':self.pages.append(self.chat)
  elif self.variant=='same-tab':self.home.url=self.chat.url
  elif self.variant=='iframe':self.home.frames=[self.chat]
class BrowserTests(unittest.IsolatedAsyncioTestCase):
 async def test_direct_chat_does_not_open_bank_or_click_widget(self):
  c=Ctx('missing');scope=await open_direct_chat(c,timeout=200)
  self.assertIs(scope,c.home);self.assertIn(CHAT_HOST,c.home.url)
  self.assertEqual(c.pages,[c.home])
 async def test_bank_failure_does_not_affect_direct_chat(self):
  c=Ctx('missing');original=c.home.goto
  async def guarded(url,**kwargs):
   if url==BANK_URL:raise Exception('net::ERR_EMPTY_RESPONSE')
   return await original(url,**kwargs)
  c.home.goto=guarded
  self.assertIs(await open_direct_chat(c,timeout=200),c.home)
 async def test_new_tab(self):
  c=Ctx('new-tab');self.assertIs(await open_chat(c,c.home,timeout=200),c.chat)
 async def test_same_tab(self):
  c=Ctx('same-tab');self.assertIs(await open_chat(c,c.home,timeout=200),c.home)
 async def test_embedded_frame(self):
  c=Ctx('iframe');self.assertIs(await open_chat(c,c.home,timeout=200),c.chat)
 async def test_notice_and_cookie_handlers_before_navigation(self):
  c=Ctx('new-tab');await open_bank(c,timeout=200)
  names=[name for name,handler in c.home.before_navigation];self.assertIn('Fechar',names);self.assertIn('Aceitar cookies',names)
 async def test_missing_form_is_diagnostic_not_non_client(self):
  c=Ctx('missing')
  with self.assertRaisesRegex(NavigationIssue,'formulário'):await open_chat(c,c.home,timeout=1)
 def test_network_errors_keep_actual_code(self):
  self.assertEqual(describe_error(Exception('Page.goto: net::ERR_HTTP2_PROTOCOL_ERROR at https://bank/')),'net::ERR_HTTP2_PROTOCOL_ERROR')
  self.assertIn('ERR_CERT_AUTHORITY_INVALID',describe_error(Exception('net::ERR_CERT_AUTHORITY_INVALID')))
  self.assertIn('ERR_NAME_NOT_RESOLVED',describe_error(Exception('net::ERR_NAME_NOT_RESOLVED')))
 def test_unknown_exception_does_not_publish_client_data(self):
  self.assertNotIn('private-cpf',describe_error(Exception('fill value private-cpf')))
 def test_http_error_stops_without_alternate_route(self):
  with self.assertRaisesRegex(NavigationIssue,'HTTP 403'):check_access('Forbidden',403)
 def test_verification_stops(self):
  with self.assertRaisesRegex(NavigationIssue,'verificação'):check_access('Checking your browser. Verify you are human')
if __name__=='__main__':unittest.main()

