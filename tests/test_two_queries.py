import sys,unittest
from unittest.mock import AsyncMock,patch
sys.path.insert(0,'vps')
from robot import run,parse_response
CLIENT={'nome':'TESTE','cpf':'00123456789','telefone':'11999999999'}
SALDO={'status':'concluida','saldo_liquidacao':1234.56,'total_parcelas':24,'progress':100,'stage':'Concluída'}
class TwoQueriesTests(unittest.IsolatedAsyncioTestCase):
 async def test_nonclient_never_starts_second_session(self):
  first={'status':'nao_cliente','progress':100,'stage':'Não é cliente'}
  with patch('robot.run_once',new=AsyncMock(return_value=first)) as one:
   result=await run(CLIENT)
  self.assertEqual(one.await_count,1);self.assertEqual(result['status'],'nao_cliente');self.assertEqual(result['progress'],100)
  self.assertNotIn('valor_parcela',result)
 async def test_balance_saved_before_parcela_then_complete(self):
  saved=[];percentages=[]
  async def one(client,timeout,report,kind):
   await report(10,'Abrir');await report(100,'Concluída')
   if kind=='saldo':return SALDO.copy()
   self.assertEqual(saved[0]['saldo_liquidacao'],1234.56)
   self.assertEqual(saved[0]['status'],'processando')
   return {'status':'concluida','valor_parcela':123.4,'progress':100,'stage':'Concluída'}
  with patch('robot.run_once',side_effect=one) as mocked:
   result=await run(CLIENT,on_checkpoint=lambda data:saved.append(data),on_progress=lambda p,s:percentages.append(p))
  self.assertEqual(mocked.await_count,2);self.assertEqual(result['valor_parcela'],123.4)
  self.assertEqual(result['saldo_liquidacao'],1234.56);self.assertEqual(result['total_parcelas'],24)
  self.assertEqual(result['status'],'concluida');self.assertEqual(percentages,sorted(percentages))
  self.assertEqual(result['resultado_parcela']['status'],'concluida')
 async def test_second_failure_preserves_first_result(self):
  second={'status':'erro','progress':40,'stage':'Menu','message':'Tempo excedido'}
  with patch('robot.run_once',new=AsyncMock(side_effect=[SALDO,second])):
   result=await run(CLIENT,on_checkpoint=AsyncMock())
  self.assertEqual(result['status'],'revisao');self.assertEqual(result['saldo_liquidacao'],1234.56)
  self.assertEqual(result['progress'],70);self.assertNotIn('valor_parcela',result)
 async def test_transient_parcela_failure_retries_only_parcela(self):
  fail={'status':'erro','diagnostico':{'categoria':'portal','codigo':'TEMPO_EXCEDIDO','repetir':True}}
  success={'status':'concluida','valor_parcela':99}
  with patch('robot.run_once',new=AsyncMock(side_effect=[SALDO,fail,success])) as one,patch('robot.asyncio.sleep',new=AsyncMock()):
   result=await run(CLIENT)
  self.assertEqual([call.kwargs['kind'] for call in one.await_args_list],['saldo','parcela','parcela'])
  self.assertEqual(result['saldo_liquidacao'],1234.56)
  self.assertEqual(result['valor_parcela'],99)
  self.assertIn('Recuperação automática',result['message'])
 async def test_interrupted_after_cpf_is_distinct_and_keeps_balance(self):
  interrupted=parse_response('Esse atendimento foi encerrado.',ended=True,cpf_sent=True,kind='parcela')
  self.assertEqual(interrupted['status'],'interrompida')
  self.assertEqual(parse_response('Esse atendimento foi encerrado.',ended=True,cpf_sent=True)['status'],'interrompida')
  self.assertEqual(parse_response('Seu documento não foi localizado para esse produto.',ended=True,cpf_sent=True)['status'],'nao_cliente')
  with patch('robot.run_once',new=AsyncMock(side_effect=[SALDO,interrupted])):
   result=await run(CLIENT)
  self.assertEqual(result['status'],'interrompida')
  self.assertEqual(result['message'],'Saldo obtido. Consulta da parcela interrompida.')
  self.assertEqual(result['saldo_liquidacao'],1234.56)
 async def test_interrupted_saldo_switches_route_and_stops_on_confirmed_nonclient(self):
  first={'status':'interrompida','rota':'central_cobranca','progress':85}
  second={'status':'nao_cliente','rota':'emprestimo_consignado','progress':100}
  with patch('robot.run_once',new=AsyncMock(side_effect=[first,second])) as one:
   result=await run(CLIENT)
  self.assertEqual([call.kwargs for call in one.await_args_list],[
   {'kind':'saldo'},{'kind':'saldo','route':'emprestimo_consignado'}])
  self.assertEqual(result['status'],'nao_cliente')
  self.assertEqual(result['resultado_saldo']['tentativa_anterior'],first)
  self.assertNotIn('rota',result)

 async def test_parcela_uses_other_route_on_error_and_keeps_saldo(self):
  fail={'status':'erro','rota':'emprestimo_consignado','diagnostico':{'categoria':'portal','codigo':'TEMPO_EXCEDIDO','repetir':True}}
  success={'status':'concluida','rota':'central_cobranca','valor_parcela':99}
  with patch('robot.run_once',new=AsyncMock(side_effect=[SALDO,fail,success])) as one:
   result=await run(CLIENT)
  self.assertEqual([call.kwargs for call in one.await_args_list],[
   {'kind':'saldo'},{'kind':'parcela'},{'kind':'parcela','route':'central_cobranca'}])
  self.assertEqual(result['valor_parcela'],99)
  self.assertEqual(result['saldo_liquidacao'],1234.56)

 async def test_failed_alternate_preserves_interruption_and_disables_job_retry(self):
  first={'status':'interrompida','rota':'central_cobranca','progress':85}
  second={'status':'erro','rota':'emprestimo_consignado','diagnostico':{'categoria':'portal','codigo':'TEMPO_EXCEDIDO','repetir':True}}
  with patch('robot.run_once',new=AsyncMock(side_effect=[first,second])) as one:
   result=await run(CLIENT)
  self.assertEqual(one.await_count,2)
  self.assertEqual(result['status'],'interrompida')
  self.assertEqual(result['message'],'Consulta interrompida.')
  self.assertFalse(result['resultado_saldo']['diagnostico']['repetir'])

 async def test_partial_balance_is_preserved_when_alternate_cannot_confirm_it(self):
  partial=parse_response('Valor Saldo: R$ 1234.56',ended=True,cpf_sent=True)
  partial['rota']='central_cobranca'
  with patch('robot.run_once',new=AsyncMock(side_effect=[partial,{'status':'nao_cliente'}])) as one:
   result=await run(CLIENT)
  self.assertEqual(one.await_count,2)
  self.assertEqual(result['status'],'revisao')
  self.assertEqual(result['saldo_liquidacao'],1234.56)
  self.assertNotIn('total_parcelas',result)

 async def test_route_does_not_retry_refused_cpf_or_human_verification(self):
  for code in ('CPF_RECUSADO','VERIFICACAO_HUMANA'):
   result={'status':'revisao','rota':'central_cobranca','diagnostico':{'codigo':code}}
   with self.subTest(code=code),patch('robot.run_once',new=AsyncMock(return_value=result)) as one:
    await run(CLIENT)
    self.assertEqual(one.await_count,1)

 async def test_failed_checkpoint_prevents_second_call(self):
  with patch('robot.run_once',new=AsyncMock(return_value=SALDO)) as one:
   result=await run(CLIENT,on_checkpoint=AsyncMock(side_effect=OSError()))
  self.assertEqual(one.await_count,1);self.assertEqual(result['status'],'revisao')
  self.assertEqual(result['saldo_liquidacao'],1234.56)
 async def test_inconclusive_first_call_is_not_repeated(self):
  with patch('robot.run_once',new=AsyncMock(return_value={'status':'revisao','progress':10,'message':'Verificação adicional'})) as one:
   result=await run(CLIENT)
  self.assertEqual(one.await_count,1);self.assertEqual(result['status'],'revisao')
 def test_observed_single_decimal_parcela(self):
  result=parse_response('Segue o valor da Parcela: R$ 123.4 O Banco Digimais agradece seu contato e até breve!',kind='parcela',cpf_sent=True)
  self.assertEqual(result['valor_parcela'],123.4)
 def test_brazilian_parcela_and_no_mixing_saldo(self):
  self.assertEqual(parse_response('Valor da Parcela: R$ 1.234,56',kind='parcela')['valor_parcela'],1234.56)
  self.assertIsNone(parse_response('Valor Saldo: R$ 1234.56 Total de parcelas: 24',kind='parcela'))
 def test_missing_parcela_is_not_zero(self):
  self.assertEqual(parse_response('Obrigado pelo contato',kind='parcela',cpf_sent=True,ended=True)['status'],'interrompida')
if __name__=='__main__':unittest.main()
