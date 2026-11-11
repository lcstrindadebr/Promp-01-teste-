import asyncio,sys,unittest,json
from pathlib import Path
from unittest.mock import AsyncMock,patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
from digimais_api import ApiSession,parse_result,money,format_cpf,CpfFormatError,messages,assert_service_available,FlowStopped
from robot_metrics import Slot

class PilotTests(unittest.IsolatedAsyncioTestCase):
 def test_original_false_success_is_preserved_and_observable(self):
  r=parse_result([{'contentText':'Saldo para quitação não disponível'}],'saldo')
  self.assertTrue(r['sucesso']);self.assertIsNone(r['valorSaldo'])
  slot=Slot('api-1');slot.begin('digimais_api');slot.saving({'status':'concluida','saldo_liquidacao':None,'valor_parcela':10});slot.saved()
  self.assertEqual(slot.snapshot()['missing_values_last_hour'],1)
 def test_cpf_chat_format_is_idempotent(self):
  self.assertEqual(format_cpf('00000000191'),'000.000.001-91')
  self.assertEqual(format_cpf('000.000.001-91'),'000.000.001-91')
  for value in ['123',None,'0000000019a','000000001910']:
   with self.assertRaises(CpfFormatError):format_cpf(value)

 def test_values(self):
  r=parse_result([{'contentText':'Valor Saldo: *R$ 12761.8*\nTotal de parcelas: *85*'}],'saldo')
  self.assertEqual(money(r['valorSaldo']),12761.8);self.assertEqual(r['totalParcelas'],'85')
  self.assertEqual(money('7.906,79'),7906.79)
 async def test_http_timeout_and_menu_failures_are_persistable_and_sanitized(self):
  import urllib.error
  api=ApiSession({'baseUrl':'https://example.invalid/api','code':'PRIVATE_CODE','accountUid':'PRIVATE_ACCOUNT'})
  job={'nome':'Fixture','cpf':'00000000000','telefone':'11999999999'}
  for error,reason in [(urllib.error.HTTPError('https://secret.invalid?code=PRIVATE_CODE',429,'private',{},None),'HTTP_429'),(TimeoutError('PRIVATE_CODE'),'TEMPO_EXCEDIDO')]:
   with patch('digimais_api.urllib.request.urlopen',side_effect=error):
    result=await api.run(job)
   self.assertEqual(result['status'],'revisao')
   self.assertEqual(result['resultado_saldo']['etapa'],'autenticação')
   self.assertEqual(result['resultado_saldo']['motivo_interrupcao'],reason)
   self.assertEqual(result['resultado_saldo']['eventos'][-1]['status'],'interrompida')
   self.assertIn(reason,result['message'])
   self.assertNotIn('PRIVATE_CODE',json.dumps(result))
   self.assertNotIn('secret.invalid',json.dumps(result))
  with patch('digimais_api.urllib.request.urlopen',side_effect=json.JSONDecodeError('private','x',0)):
   result=await api.flow(job,'saldo')
  self.assertEqual(result['motivo_interrupcao'],'Resposta JSON inválida do atendimento')

 async def test_missing_menu_records_exact_stage(self):
  class Headers:
   def get_all(self,*args):return []
  class Response:
   headers=Headers()
   def __init__(self,data):self.data=data
   def __enter__(self):return self
   def __exit__(self,*args):pass
   def read(self):return json.dumps(self.data).encode()
  api=ApiSession({'baseUrl':'https://example.invalid','code':'private','accountUid':'fixture'})
  with patch('digimais_api.urllib.request.urlopen',side_effect=[Response({'userId':'fixture'}),Response({}),Response([])]),patch('digimais_api.asyncio.sleep',new_callable=AsyncMock):
   result=await api.flow({'nome':'Fixture','cpf':'00000000000','telefone':'11999999999'},'saldo')
  self.assertFalse(result['sucesso'])
  self.assertEqual(result['etapa'],'menu de cobrança')
  self.assertIn('Opção esperada não encontrada',result['motivo_interrupcao'])
  self.assertEqual([e['etapa'] for e in result['eventos'][:-1]],['autenticação','criação da sessão','menu de cobrança'])

 def test_wrapped_messages_and_incoming_text(self):
  self.assertEqual(messages({'body':{'items':[{'contentText':'fixture'}]}}),[{'contentText':'fixture'}])
  self.assertEqual(messages(None),[])
  assert_service_available([{'direction':'I','contentText':'fora do horário de atendimento'}])
  with self.assertRaises(FlowStopped):assert_service_available([{'direction':'O','contentText':'Estamos fora do horário de atendimento.'}])

 async def test_closed_service_stops_after_saldo_and_rotates_session_cookies(self):
  requests=[];reads=0
  class Headers:
   def __init__(self,cookies):self.cookies=cookies
   def get_all(self,*args):return self.cookies
  class Response:
   def __init__(self,data,cookies=[]):self.data=data;self.headers=Headers(cookies)
   def __enter__(self):return self
   def __exit__(self,*args):pass
   def read(self):return json.dumps(self.data).encode()
  def request(req,timeout):
   nonlocal reads
   requests.append(req);path=req.full_url.split('?')[0]
   if path.endswith('login-public'):return Response({'userId':'fixture'},['auth=login; Secure','session=before; Secure'])
   if path.endswith('/sessions'):return Response({'id':'fixture-session'},['session=after; Secure'])
   if req.data:return Response({})
   reads+=1
   if reads==1:return Response({'body':{'items':[{'options':[{'id':'central','title':'Central de cobrança'}]}]}})
   return Response([{'direction':'O','contentText':'Oi! No momento estamos fora do horário de atendimento. Funcionamos de segunda a sexta, das 9h às 18h, exceto feriados.'},
    {'options':[{'id':'stale-option','title':'Saldo Liquidação'}]}])
  api=ApiSession({'baseUrl':'https://example.invalid','code':'private','accountUid':'fixture'})
  progress=AsyncMock();checkpoint=AsyncMock()
  with patch('digimais_api.urllib.request.urlopen',side_effect=request),patch('digimais_api.asyncio.sleep',new_callable=AsyncMock):
   result=await api.run({'nome':'Fixture','cpf':'00000000191','telefone':'11999999999'},on_progress=progress,on_checkpoint=checkpoint)
  self.assertEqual(len(requests),6)
  self.assertEqual(result['status'],'revisao')
  self.assertEqual(result['resultado_saldo']['codigo'],'FORA_HORARIO_ATENDIMENTO')
  self.assertEqual(result['resultado_saldo']['etapa'],'seleção de saldo')
  self.assertTrue(result['resultado_parcela']['nao_executada'])
  self.assertIsNone(result['valor_parcela'])
  self.assertIn('fora do horário',result['stage'])
  self.assertNotIn('Opção esperada não encontrada',result['message'])
  self.assertIn('session=after',requests[2].get_header('Cookie'))
  self.assertIn('auth=login',requests[2].get_header('Cookie'))
  self.assertNotIn('session=before',requests[2].get_header('Cookie'))
  self.assertEqual(progress.await_count,1);checkpoint.assert_awaited_once()

 async def test_definitive_chat_replies_before_option_lookup(self):
  cases=[
   ('Desculpe, não consegui localizar o seu documento. Este canal é exclusivo para clientes.', 'nao_cliente', 'DOCUMENTO_NAO_LOCALIZADO'),
   ('Informamos que seu contrato está sob a responsabilidade da nossa assessoria de cobrança,**MZ ASSESSORIA E COBRANÇA - (11)4293-0260**.', 'ja_vendeu', 'CONTRATO_EM_ASSESSORIA'),
  ]
  for message,status,code in cases:
   with self.subTest(status=status):
    requests=[]
    class Headers:
     def get_all(self,*args):return []
    class Response:
     headers=Headers()
     def __init__(self,data):self.data=data
     def __enter__(self):return self
     def __exit__(self,*args):pass
     def read(self):return json.dumps(self.data).encode()
    def request(req,timeout):
     requests.append(req)
     path=req.full_url.split('?')[0]
     if path.endswith('login-public'):return Response({'userId':'fixture'})
     if path.endswith('/sessions'):return Response({'id':'fixture-session'})
     if req.data:return Response({})
     if len(requests)==3:return Response([{'options':[{'id':'central','title':'Central de cobrança'}]}])
     return Response([{'direction':'O','contentText':message}])
    api=ApiSession({'baseUrl':'https://example.invalid','code':'fixture','accountUid':'fixture'})
    job={'nome':'Fixture','cpf':'00000000000','telefone':'11999999999'}
    with patch('digimais_api.urllib.request.urlopen',side_effect=request),patch('digimais_api.asyncio.sleep',new_callable=AsyncMock):
     result=await api.run(job)
    self.assertEqual(result['status'],status)
    self.assertEqual(result['resultado_saldo']['codigo'],code)
    self.assertIn(message,result['resultado_saldo']['todasMensagens'])
    self.assertNotIn('resultado_parcela',result)
    self.assertEqual(len(requests),6)

 async def test_sequential_checkpoint_and_referral(self):
  api=ApiSession({});events=[]
  async def flow(job,kind):
   events.append(kind)
   return {'sucesso':False,'todasMensagens':['Contrato em assessoria de cobrança MAXISERV']}
  api.flow=flow
  async def save(data):events.append('saved')
  r=await api.run({},on_checkpoint=save)
  self.assertEqual(events,['saldo','saved','parcela']);self.assertEqual(r['status'],'revisao');self.assertIn('assessoria',r['message'])
 async def test_failed_checkpoint_does_not_start_parcela(self):
  api=ApiSession({});api.flow=AsyncMock(return_value={'sucesso':True,'valorSaldo':'12.3'})
  with self.assertRaises(OSError):await api.run({},on_checkpoint=AsyncMock(side_effect=OSError()))
  self.assertEqual(api.flow.await_count,1)
 async def test_protocol_waits_and_session_isolation(self):
  requests=[];cookies=[]
  class Headers:
   def get_all(self,*args):return ['session=isolated; Secure']
  class Response:
   headers=Headers()
   def __init__(self,data):self.data=data
   def __enter__(self):return self
   def __exit__(self,*args):pass
   def read(self):return json.dumps(self.data).encode()
  def request(req,timeout):
   requests.append(req)
   path=req.full_url.split('?')[0]
   if path.endswith('login-public'):return Response({'userId':'returned-user'})
   if path.endswith('/sessions'):return Response({'id':json.loads(req.data)['id']})
   if req.data:return Response({})
   return Response([{'options':[{'id':'central','title':'Central de cobrança'},{'id':'saldo','title':'Saldo Liquidação'},{'id':'parcela','title':'Valor de Parcela'}],'contentText':'Valor Saldo: R$ 10.00\nTotal de parcelas: 2\nValor da Parcela: R$ 5.00'}])
  api=ApiSession({'baseUrl':'https://example.invalid/api','code':'test','accountUid':'test'})
  job={'nome':'Fixture','cpf':'00000000000','telefone':'11999999999'}
  with patch('digimais_api.urllib.request.urlopen',side_effect=request),patch('digimais_api.asyncio.sleep',new_callable=AsyncMock) as sleep:
   r=await api.run(job)
  self.assertEqual(r['status'],'concluida');self.assertEqual(len(requests),16)
  self.assertEqual([c.args[0] for c in sleep.await_args_list],[8,5,6,8]*2)
  sessions=[json.loads(r.data)['id'] for r in requests if r.full_url.split('?')[0].endswith('/sessions')]
  self.assertNotEqual(*sessions)
  self.assertEqual(requests[0].get_header('Cookie'),'');self.assertEqual(requests[8].get_header('Cookie'),'')
  cpf_messages=[json.loads(request.data)['contentText'] for request in requests if request.data and 'contentText' in json.loads(request.data) and not json.loads(request.data).get('customData')]
  self.assertEqual(cpf_messages,['000.000.000-00','000.000.000-00'])
  self.assertEqual(job['cpf'],'00000000000')


if __name__=='__main__':unittest.main()

class ApiPoolTests(unittest.IsolatedAsyncioTestCase):
 async def test_twelve_clients_no_requery_when_saving_fails(self):
  import importlib.util,os,threading
  with patch.dict(os.environ,{'SUPABASE_URL':'https://example.invalid','SUPABASE_SERVICE_ROLE_KEY':'fake','ROBOT_MODE':'live'}):
   spec=importlib.util.spec_from_file_location('pilot_worker',Path(__file__).resolve().parents[1]/'vps/worker.py');worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
  cap=worker.ApiCapacity();self.assertEqual(cap.target,12)
  lock=threading.Lock();claimed=set();saved=set();processed=[];failed=False;barrier=asyncio.Event()
  def request(route,payload=None,method='POST',timeout=30):
   nonlocal failed
   with lock:
    if route.startswith('rpc/claim'):
     i=payload['p_slot']
     if i in claimed:return []
     claimed.add(i);return [{'id':str(i)}]
    if method=='PATCH':
     if not failed:failed=True;raise OSError()
     saved.add(route);return None
  async def process(job,adapter):
   processed.append(job['id'])
   if len(processed)==12:barrier.set()
   await asyncio.wait_for(barrier.wait(),3)
   cap.target=1
   return {'status':'concluida','saldo_liquidacao':1,'valor_parcela':2}
  real_sleep=asyncio.sleep
  async def quick(_):await real_sleep(.001)
  with patch.object(worker,'request',side_effect=request),patch.object(worker,'process_digimais',side_effect=process),patch.object(worker.asyncio,'sleep',side_effect=quick):
   tasks=[asyncio.create_task(worker.api_loop(i,cap,Slot('api-'+str(i)),{})) for i in range(12)]
   try:
    async with asyncio.timeout(5):
     while len(saved)<12:await real_sleep(.005)
   finally:
    for t in tasks:t.cancel()
    await asyncio.gather(*tasks,return_exceptions=True)
  self.assertEqual(len(processed),12);self.assertEqual(len(set(processed)),12)
  low={'total':2048*1024**2,'available':200*1024**2}
  cap=worker.ApiCapacity();cap.observe(low,40);self.assertEqual(cap.target,11)
