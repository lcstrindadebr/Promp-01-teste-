import asyncio,importlib.util,sys,unittest
from pathlib import Path
from unittest.mock import AsyncMock,MagicMock,patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'vps'));import tjba
class ParseTests(unittest.TestCase):
 def test_decimal_values(self):
  for raw,want in [('R$ 1.234,56','1234.56'),('0,00','0.00'),('-10,25','-10.25'),('-R$ 28,85','-28.85'),('(15,50)','-15.50'),('1.234','1234.00'),('',''),('—','')]:self.assertEqual(tjba.parse_brl(raw),want or None)
 def test_available_header_not_fixed_index(self):
  self.assertEqual(tjba.available_index(['Serviço','Margem Disponível (R$)','Margem Total']),1)
  with self.assertRaises(tjba.Review):tjba.available_index(['Serviço','Total','Utilizada'])
 def test_only_one_verified_active(self):
  self.assertEqual(tjba.active_index(['Matrícula','Situação'],[['001','Inativo'],['002','Ativo']]),1)
  self.assertIsNone(tjba.active_index(['Matrícula','Situação'],[['001','Ativo'],['002','Ativo']]))
  self.assertIsNone(tjba.active_index(['Matrícula','Outro'],[['001','Ativo']]))
 def test_cpf_and_status(self):
  self.assertEqual(tjba.normalize_cpf('123'), '00000000123')
  result=tjba.job_result({'status':'consultado','emprestimo_disponivel':'0.00','cartao_disponivel':'-10.25','matricula':'00001'})
  self.assertEqual(result['emprestimo_disponivel'],'0.00');self.assertNotIn('saldo_liquidacao',result)
  self.assertEqual(tjba.job_result({'status':'revisao_matricula'})['status'],'revisao')
class SessionTests(unittest.IsolatedAsyncioTestCase):
 async def test_disabled_never_opens_browser(self):
  s=tjba.Session();r=await s.run({'cpf':'123','user_id':'u'},{'enabled':False},AsyncMock())
  self.assertEqual(r['status'],'revisao');self.assertIsNone(s.browser)
 async def test_same_session_for_three_cpfs_and_isolated_error(self):
  s=tjba.Session();s.identity=('u','rev');s.browser=MagicMock();s.browser.close=AsyncMock();s.page=MagicMock();s.page.is_closed.return_value=False
  with patch.object(tjba,'consult',new_callable=AsyncMock) as consult:
   consult.side_effect=[{'status':'consultado','emprestimo_disponivel':'0.00','cartao_disponivel':'-1.00'},tjba.Review('revisao_matricula','Revisar'),{'status':'nao_encontrado'}]
   result=[]
   for cpf in ('1','2','3'):result.append(await s.run({'cpf':cpf,'user_id':'u'},{'enabled':True,'revision':'rev'},AsyncMock()))
   self.assertEqual([r['status'] for r in result],['concluida','revisao','nao_encontrado']);self.assertEqual(consult.await_count,3);s.browser.close.assert_not_called()
 async def test_expiration_blocks_repeated_login_until_new_revision(self):
  s=tjba.Session();s.identity=('u','rev');s.browser=MagicMock();s.browser.close=AsyncMock();s.page=MagicMock();s.page.is_closed.return_value=False
  with patch.object(tjba,'consult',new_callable=AsyncMock,side_effect=tjba.Review('sessao_expirada','Sessão expirada')) as consult:
   a=await s.run({'cpf':'1','user_id':'u'},{'enabled':True,'revision':'rev'},AsyncMock())
   b=await s.run({'cpf':'2','user_id':'u'},{'enabled':True,'revision':'rev'},AsyncMock())
   self.assertEqual(a['tjba_status'],'sessao_expirada');self.assertEqual(b['tjba_status'],'sessao_expirada');self.assertEqual(consult.await_count,1)
class WorkerRouteTests(unittest.IsolatedAsyncioTestCase):
 async def test_tjba_progress_uses_tjba_table_and_credentials_stay_worker_only(self):
  import importlib.util,os
  with patch.dict(os.environ,{'SUPABASE_URL':'https://test.invalid','SUPABASE_SERVICE_ROLE_KEY':'sb_secret_fake','ROBOT_MODE':'live'}):
   spec=importlib.util.spec_from_file_location('worker_tjba_test',ROOT/'vps/worker.py');worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
  calls=[]
  def request(path,payload=None,method='POST',timeout=30):
   calls.append((path,payload,method))
   if path=='rpc/get_tjba_credentials':return {'enabled':True,'revision':'rev','username':'TESTE','password':'FAKE'}
  class Adapter:
   async def run(self,job,credentials,on_progress):
    await on_progress(35,'Consultar');return {'status':'concluida','emprestimo_disponivel':'0.00'}
  with patch.object(worker,'request',side_effect=request):
   result=await worker.process_tjba({'id':'j','user_id':'u','cpf':'123'},Adapter())
  self.assertEqual(result['status'],'concluida');self.assertTrue(any(p=='tjba_jobs?id=eq.j' for p,_,_ in calls));self.assertFalse(any('consulta_jobs' in p for p,_,_ in calls));self.assertNotIn('FAKE',str(result))

class FakeNavigation:
 def __init__(self,page):self.page=page
 async def __aenter__(self):return self
 async def __aexit__(self,*args):return False
class FakeLoginLocator:
 def __init__(self,page,selector):self.page=page;self.selector=selector
 @property
 def first(self):return self
 async def is_visible(self):
  p=self.page;s=self.selector
  return (s=='#entendi-cookies' and p.cookie) or (p.state=='login' and s in ('#txtLogin','#txtSenha','#Entrar')) or (p.state=='grid' and s in ('#gvOrgao','#gvOrgao tr','[id^="gvOrgao_imgEntrar_"]')) or (p.state in ('initial','form') and s=='#descricaoOrgaoLabel') or (p.state=='form' and s in (tjba.CPF,tjba.SEARCH))
 async def wait_for(self,**kwargs):
  if not await self.is_visible():raise TimeoutError('expected control missing')
 async def count(self):return 1 if await self.is_visible() else 0
 def locator(self,selector):return FakeLoginLocator(self.page, '#gvOrgao tr' if self.selector=='#gvOrgao' and selector=='tr' else selector)
 def filter(self,**kwargs):return self
 async def inner_text(self):return 'TRIBUNAL JUSTICA DA BAHIA'
 async def input_value(self):return getattr(self.page,'values',{}).get(self.selector,'')
 async def fill(self,value):
  if not hasattr(self.page,'values'):self.page.values={}
  self.page.values[self.selector]=value;self.page.events.append(('fill',self.selector))
 async def click(self,**kwargs):
  self.page.events.append(('click',self.selector))
  if self.selector=='#entendi-cookies':self.page.cookie=False
  elif self.selector=='#Entrar':
   if self.page.cookie:raise TimeoutError('cookie overlay intercepts action')
   self.page.state='grid';self.page.url=tjba.BASE+'/LoginSelecao.aspx'
  elif self.selector=='[id^="gvOrgao_imgEntrar_"]':self.page.state='initial';self.page.authenticated=True;self.page.url=tjba.BASE+'/Inicial/Inicial.aspx'
class FakeLoginPage:
 def __init__(self):self.state='blank';self.cookie=True;self.authenticated=False;self.events=[];self.url='about:blank'
 async def goto(self,url,**kwargs):
  self.events.append(('goto',url));self.url=url
  if url==tjba.BASE+'/':self.state='login'
  elif url==tjba.BASE+tjba.PATH:
   if not self.authenticated:raise AssertionError('Protected route before login')
   self.state='form'
  return type('Response',(),{'status':200})()
 def locator(self,selector):return FakeLoginLocator(self,selector)
 def expect_navigation(self,**kwargs):return FakeNavigation(self)
 async def wait_for_load_state(self,*args):pass
class LoginFlowTests(unittest.IsolatedAsyncioTestCase):
 async def test_public_login_cookie_convenio_then_protected_route(self):
  page=FakeLoginPage();progress=[]
  async def report(p,label):progress.append(p)
  await tjba.login(page,{'username':'TEST','password':'FAKE'},on_step=report)
  self.assertEqual(page.state,'form');self.assertEqual(page.events[0],('goto',tjba.BASE+'/'))
  self.assertLess(page.events.index(('click','#entendi-cookies')),page.events.index(('click','#Entrar')))
  self.assertLess(page.events.index(('click','[id^="gvOrgao_imgEntrar_"]')),page.events.index(('goto',tjba.BASE+tjba.PATH)))
  self.assertEqual(progress,[12,15,18,22,23,24,25,28,32])
 async def test_failure_keeps_stage_and_percent_without_leaking_exception_text(self):
  session=tjba.Session();session.identity=('u','rev');session.browser=MagicMock();session.browser.close=AsyncMock();session.page=MagicMock();session.page.is_closed.return_value=False;session.page.url=tjba.BASE+tjba.PATH+'?password=SECRET'
  async def broken(page,cpf,on_step=None):
   await on_step(45,'Preencher CPF no formulário TJBA');raise TimeoutError('SECRET CPF=123 token=hidden net::ERR_CONNECTION_CLOSED')
  with patch.object(tjba,'consult',side_effect=broken):result=await session.run({'user_id':'u','cpf':'123'},{'enabled':True,'revision':'rev'},AsyncMock())
  self.assertEqual(result['progress'],45);self.assertIn('Preencher CPF',result['stage']);self.assertNotIn('SECRET',str(result));self.assertNotIn('token=',str(result));self.assertEqual(result['resultado_tjba']['diagnostico']['codigo'],'ERR_CONNECTION_CLOSED');self.assertEqual(result['resultado_tjba']['diagnostico']['rota'],tjba.PATH)
 def test_chromium_transport_is_not_digimais_specific(self):
  self.assertNotIn('--disable-http2',tjba.CHROMIUM_ARGS)
  self.assertEqual(tjba.failure_details(RuntimeError("Executable doesn't exist. SECRET"))['codigo'],'CHROMIUM_AUSENTE')

class LoginOutcomeTests(unittest.IsolatedAsyncioTestCase):
 async def test_rejected_login_does_not_wait_for_grid(self):
  original=FakeLoginLocator.click
  async def rejected(loc,**kwargs):
   if loc.selector=='#Entrar':loc.page.state='login'
   else:await original(loc,**kwargs)
  page=FakeLoginPage()
  with patch.object(FakeLoginLocator,'click',rejected):
   with self.assertRaises(tjba.Review) as error:await tjba.login(page,{'username':'TEST','password':'FAKE'})
  self.assertIn('Autenticação não confirmada',error.exception.message)
  self.assertNotIn(('goto',tjba.BASE+tjba.PATH),page.events)
 async def test_login_directly_to_agreement(self):
  original=FakeLoginLocator.click
  async def direct(loc,**kwargs):
   if loc.selector=='#Entrar':loc.page.state='initial';loc.page.authenticated=True
   else:await original(loc,**kwargs)
  page=FakeLoginPage()
  with patch.object(FakeLoginLocator,'click',direct):await tjba.login(page,{'username':'TEST','password':'FAKE'})
  self.assertEqual(page.state,'form')
  self.assertNotIn(('click','[id^="gvOrgao_imgEntrar_"]'),page.events)
 async def test_agreement_does_not_require_document_navigation(self):
  page=FakeLoginPage();calls=[]
  def expect(**kwargs):
   calls.append(page.state)
   if page.state=='grid':raise AssertionError('Do not require document navigation for agreement selection')
   return FakeNavigation(page)
  page.expect_navigation=expect
  await tjba.login(page,{'username':'TEST','password':'FAKE'})
  self.assertEqual(calls,['login']);self.assertEqual(page.state,'form')

class LoginNoticeTests(unittest.IsolatedAsyncioTestCase):
 def test_classification_does_not_return_raw_secrets(self):
  self.assertEqual(tjba.login_notice('Senha incorreta SECRET'), 'O portal informou usuário ou senha inválidos.')
  self.assertIn('sessão já ativa',tjba.login_notice('Usuário já conectado SECRET'))
  self.assertNotIn('SECRET',tjba.login_notice('Mensagem desconhecida SECRET'))
 async def test_confirmation_is_not_accepted(self):
  page=MagicMock();loc=MagicMock();loc.is_visible=AsyncMock(return_value=True);loc.inner_text=AsyncMock(return_value='Usuário já conectado SECRET');page.locator.return_value=loc
  with self.assertRaises(tjba.Review) as result:await tjba.inspect_login_notice(page)
  self.assertNotIn('SECRET',result.exception.message);loc.click.assert_not_called()
 async def test_cleared_password_stops_before_submit(self):
  page=FakeLoginPage()
  with patch.object(FakeLoginLocator,'input_value',new=AsyncMock(return_value='')):
   with self.assertRaises(tjba.Review) as result:await tjba.login(page,{'username':'TEST','password':'FAKE'})
  self.assertIn('limpos',result.exception.message)
  self.assertNotIn(('click','#Entrar'),page.events)
