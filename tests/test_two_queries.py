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
  self.assertEqual(parse_response('Obrigado pelo contato',kind='parcela',cpf_sent=True,ended=True)['status'],'revisao')
if __name__=='__main__':unittest.main()
