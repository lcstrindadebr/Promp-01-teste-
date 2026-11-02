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
  return (s=='#entendi-cookies' and p.cookie) or (p.state=='login' and s in ('#txtLogin','#txtSenha','#Entrar','#chkMostrarSenha')) or (p.state=='grid' and s in ('#gvOrgao','#gvOrgao tr','[id^="gvOrgao_imgEntrar_"]')) or (p.state in ('initial','form') and s=='#descricaoOrgaoLabel') or (p.state=='form' and s in (tjba.CPF,tjba.SEARCH))
 async def wait_for(self,**kwargs):
  if not await self.is_visible():raise TimeoutError('expected control missing')
 async def all(self):return [self]
 async def all_inner_texts(self):return ['TRIBUNAL JUSTICA DA BAHIA']
 async def count(self):return 1 if await self.is_visible() else 0
 def locator(self,selector):return FakeLoginLocator(self.page, '#gvOrgao tr' if self.selector=='#gvOrgao' and selector=='tr' else selector)
 def filter(self,**kwargs):return self
 async def inner_text(self):return 'TRIBUNAL JUSTICA DA BAHIA'
 async def press(self,key):self.page.events.append(('press',self.selector))
 async def check(self,**kwargs):self.page.events.append(('check',self.selector))
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
 def expect_response(self,*args,**kwargs):
  response=MagicMock();response.finished=AsyncMock()
  context=FakeNavigation(self)
  async def value():return response
  context.value=value();return context
 async def wait_for_load_state(self,*args):pass
 async def wait_for_function(self,*args,**kwargs):pass
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
  self.assertEqual(calls,[]);self.assertEqual(page.state,'form')

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
  self.assertIn('não preservado',result.exception.message)
  self.assertNotIn(('click','#Entrar'),page.events)

class LoginRetryTests(unittest.IsolatedAsyncioTestCase):
 async def test_retry_then_success_same_page(self):
  page=object();failure=tjba.Review('sessao_expirada','form',{'retryable_login':True})
  with patch.object(tjba,'login',new=AsyncMock(side_effect=[failure,None])) as login, patch.object(tjba,'challenge',new=AsyncMock()), patch.object(tjba,'inspect_login_notice',new=AsyncMock()), patch.object(tjba.asyncio,'sleep',new=AsyncMock()):
   await tjba.login_with_retries(page,{'password':'fake'})
   self.assertEqual(login.await_count,2)
   self.assertTrue(all(c.args[0] is page for c in login.await_args_list))
 async def test_stops_at_three(self):
  with patch.object(tjba,'login',new=AsyncMock(side_effect=TimeoutError())) as login, patch.object(tjba,'challenge',new=AsyncMock()), patch.object(tjba,'inspect_login_notice',new=AsyncMock()), patch.object(tjba.asyncio,'sleep',new=AsyncMock()):
   with self.assertRaises(TimeoutError):await tjba.login_with_retries(object(),{})
   self.assertEqual(login.await_count,3)
 async def test_explicit_rejection_never_retries(self):
  with patch.object(tjba,'login',new=AsyncMock(side_effect=tjba.Review('sessao_expirada','Senha inválida'))) as login:
   with self.assertRaises(tjba.Review):await tjba.login_with_retries(object(),{})
   self.assertEqual(login.await_count,1)
 async def test_timeout_with_challenge_stops_before_retry(self):
  with patch.object(tjba,'login',new=AsyncMock(side_effect=TimeoutError())) as login, patch.object(tjba,'challenge',new=AsyncMock(side_effect=tjba.Review('sessao_expirada','Verificação humana'))):
   with self.assertRaises(tjba.Review):await tjba.login_with_retries(object(),{})
   self.assertEqual(login.await_count,1)

class InvalidPasswordRetryTests(unittest.IsolatedAsyncioTestCase):
 async def test_invalid_password_repeated_once(self):
  page=MagicMock();button=MagicMock();button.is_visible=AsyncMock(return_value=True);button.click=AsyncMock();page.locator.return_value=button
  error=tjba.Review('sessao_expirada','Senha inválida',{'invalid_password':True})
  with patch.object(tjba,'login',new=AsyncMock(side_effect=error)) as login,patch.object(tjba,'challenge',new=AsyncMock()),patch.object(tjba.asyncio,'sleep',new=AsyncMock()):
   with self.assertRaises(tjba.Review):await tjba.login_with_retries(page,{})
   self.assertEqual(login.await_count,2);button.click.assert_awaited_once()
 async def test_invalid_password_second_attempt_succeeds(self):
  page=MagicMock();button=MagicMock();button.is_visible=AsyncMock(return_value=False);page.locator.return_value=button
  error=tjba.Review('sessao_expirada','Senha inválida',{'invalid_password':True})
  with patch.object(tjba,'login',new=AsyncMock(side_effect=[error,None])) as login,patch.object(tjba,'challenge',new=AsyncMock()),patch.object(tjba.asyncio,'sleep',new=AsyncMock()):
   await tjba.login_with_retries(page,{});self.assertEqual(login.await_count,2)

class ShowPasswordTests(unittest.IsolatedAsyncioTestCase):
 async def test_show_password_checked_before_fill_and_submit(self):
  page=FakeLoginPage()
  await tjba.login(page,{'username':'TEST','password':'FAKE'})
  check=page.events.index(('check','#chkMostrarSenha'))
  self.assertLess(check,page.events.index(('fill','#txtSenha')))
  self.assertLess(check,page.events.index(('click','#Entrar')))
  self.assertEqual(page.values['#txtSenha'],'FAKE')

class LoginDiagnosticTests(unittest.IsolatedAsyncioTestCase):
 def test_redaction(self):
  text=tjba.safe_login_text('Erro MinhaSenha USER senha: abc 000.430.645-74 email@site.com https://site/x?token=xyz',{'username':'USER','password':'MinhaSenha'})
  for value in ['MinhaSenha','USER','abc','430','email@','xyz']:self.assertNotIn(value,text)
 async def test_empty_popup_is_ignored(self):
  page=MagicMock();loc=MagicMock();loc.is_visible=AsyncMock(side_effect=[True,False,False,False]);loc.inner_text=AsyncMock(return_value='OK');page.locator.return_value=loc
  await tjba.inspect_login_notice(page,{})

class DisconnectConfirmationTests(unittest.IsolatedAsyncioTestCase):
 def test_only_specific_confirmation_allowed(self):
  self.assertTrue(tjba.is_disconnect_confirmation('Usuário já logado, deseja desconectar seu usuário dos outros terminais?\nConfirmar\nCancelar'))
  for text in ['Confirmar alteração de senha','Usuário já logado','Deseja confirmar reserva?','Usuário já logado, deseja desconectar todos os usuários?']:
   self.assertFalse(tjba.is_disconnect_confirmation(text))
 async def test_keyboard_confirm_with_overlay_and_waits_for_authenticated_state(self):
  page=MagicMock();message=MagicMock();message.is_visible=AsyncMock(return_value=False)
  confirm=MagicMock();confirm.is_visible=AsyncMock(return_value=True);confirm.inner_text=AsyncMock(return_value='Usuário já logado, deseja desconectar seu usuário dos outros terminais?')
  button=MagicMock();button.click=AsyncMock(side_effect=TimeoutError('overlay intercepts pointer'));button.press=AsyncMock();confirm.locator.return_value=button
  destination=MagicMock();destination.first.wait_for=AsyncMock()
  def locate(selector):
   if selector=='#ucAjaxModalPopupConfirmacao1_PanelPopup':return confirm
   if selector=='#gvOrgao:visible, #descricaoOrgaoLabel:visible':return destination
   return message
  page.locator.side_effect=locate
  await tjba.inspect_login_notice(page,{})
  confirm.locator.assert_called_once_with('#ucAjaxModalPopupConfirmacao1_btnConfirmarPopup')
  button.press.assert_awaited_once_with('Enter',timeout=10000,no_wait_after=True);button.click.assert_not_awaited();destination.first.wait_for.assert_awaited_once()

class RegistrationRenderingTests(unittest.IsolatedAsyncioTestCase):
 async def test_registration_in_document_does_not_block_login(self):
  page=MagicMock();inactive=MagicMock();inactive.is_visible=AsyncMock(return_value=False)
  registration=MagicMock();registration.is_visible=AsyncMock(return_value=True);registration.inner_text=AsyncMock(return_value='COMPLETE SEU CADASTRO')
  page.locator.side_effect=lambda s:registration if 'Cadastro' in s else inactive
  with patch.object(tjba,'active_registration_modal',new=AsyncMock(return_value=False)):
   await tjba.inspect_login_notice(page,{})
  registration.inner_text.assert_not_awaited()
 async def test_real_foreground_registration_remains_review(self):
  page=MagicMock();inactive=MagicMock();inactive.is_visible=AsyncMock(return_value=False)
  registration=MagicMock();registration.is_visible=AsyncMock(return_value=True);registration.inner_text=AsyncMock(return_value='COMPLETE SEU CADASTRO')
  page.locator.side_effect=lambda s:registration if 'Cadastro' in s else inactive
  with patch.object(tjba,'active_registration_modal',new=AsyncMock(return_value=True)):
   with self.assertRaises(tjba.Review) as result:await tjba.inspect_login_notice(page,{})
  self.assertIn('complementação',result.exception.message)

class ShowPasswordResetTests(unittest.IsolatedAsyncioTestCase):
 async def test_toggle_clearing_password_does_not_break_submit(self):
  original=FakeLoginLocator.check
  async def clearing(loc,**kwargs):
   loc.page.values={'#txtSenha':''}
   await original(loc,**kwargs)
  page=FakeLoginPage()
  with patch.object(FakeLoginLocator,'check',clearing):await tjba.login(page,{'username':'TEST','password':'FAKE'})
  self.assertEqual(page.state,'form')
  self.assertLess(page.events.index(('press','#txtLogin')),page.events.index(('fill','#txtSenha')))

class DefaultVerbaTests(unittest.IsolatedAsyncioTestCase):
 async def test_cpf_reached_without_touching_verba(self):
  page=MagicMock();matricula=MagicMock();matricula.is_visible=AsyncMock(return_value=False)
  cpf=MagicMock();cpf.fill=AsyncMock(side_effect=RuntimeError('stop-before-submit'))
  selectors=[]
  def locate(selector):
   selectors.append(selector)
   if selector=='#body_servicoDropDownList':raise AssertionError('Default verba must remain untouched')
   return cpf if selector==tjba.CPF else matricula
  page.locator.side_effect=locate
  with patch.object(tjba,'prepare',new=AsyncMock()):
   with self.assertRaisesRegex(RuntimeError,'stop-before-submit'):await tjba.consult(page,'123')
  cpf.fill.assert_awaited_once_with('00000000123')
  self.assertNotIn('#body_servicoDropDownList',selectors)

class MultiConvenioTests(unittest.IsolatedAsyncioTestCase):
 async def test_wrong_agreement_never_accepted(self):
  page=MagicMock();label=MagicMock();label.count=AsyncMock(return_value=1);label.inner_text=AsyncMock(return_value='TRIBUNAL JUSTICA DA BAHIA');page.locator.return_value=label
  await tjba.assert_convenio(page,'tjba')
  for convenio in ['dpeba','embasa','saeb','suprev']:
   with self.assertRaises(tjba.Review):await tjba.assert_convenio(page,convenio)
 async def test_verified_active_image_button_with_missing_beneficiary_cell(self):
  page=MagicMock();table=MagicMock();table.is_visible=AsyncMock(return_value=True);page.locator.return_value=table
  rowset=MagicMock();header=MagicMock();header.all_inner_texts=AsyncMock(return_value=['Nome','CPF','Cód. Cliente','Matrícula','Beneficiário','Situação','Selecionar']);rowset.first.locator.return_value=header
  rows=[];buttons=[]
  for status in ['Suspenso','Ativo']:
   row=MagicMock();cells=MagicMock();cells.all_inner_texts=AsyncMock(return_value=['TEST','00000000191','100','00001',status,'']);button=MagicMock();button.count=AsyncMock(return_value=1);button.click=AsyncMock();buttons.append(button)
   row.locator.side_effect=lambda selector,c=cells,b=button:c if selector=='td' else b
   rows.append(row)
  rowset.all=AsyncMock(return_value=[MagicMock(),*rows]);table.locator.return_value=rowset
  await tjba.choose_matricula(page)
  buttons[0].click.assert_not_awaited();buttons[1].click.assert_awaited_once()
