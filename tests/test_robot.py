import sys,unittest
sys.path.insert(0,'vps')
from robot import parse_response,format_cpf,RobotError
class ResponseTests(unittest.TestCase):
 def test_saldo(self):
  r=parse_response('Saldo para quitação hoje: R$ 6.014,63. Total de parcelas: 89')
  self.assertEqual(r['saldo_liquidacao'],6014.63);self.assertEqual(r['total_parcelas'],89)
 def test_missing_not_zero(self):
  r=parse_response('Desculpe, o seu documento não foi localizado para esse produto.')
  self.assertEqual(r['status'],'nao_cliente');self.assertNotIn('saldo_liquidacao',r)
 def test_partial_response(self):
  self.assertIsNone(parse_response('Saldo para quitação hoje: R$ 6.014,63'))
 def test_unrecognized_not_success(self):self.assertIsNone(parse_response('Aguarde um momento.'))
 def test_expired(self):self.assertEqual(parse_response('Seu atendimento foi encerrado por falta de interação.')['status'],'erro')
 def test_formatted_cpf(self):
  self.assertEqual(format_cpf('00123456789'),'001.234.567-89')
  self.assertEqual(format_cpf('001.234.567-89'),'001.234.567-89')
 def test_invalid_cpf(self):
  with self.assertRaises(RobotError):format_cpf('123')
 def test_silent_closure_is_not_non_client(self):
  self.assertEqual(parse_response('A sessão de chat acabou',ended=True,cpf_sent=True)['status'],'revisao')
 def test_technical_failure_is_not_non_client(self):
  self.assertEqual(parse_response('Não foi possível consultar. Tente novamente.',ended=True,cpf_sent=True)['status'],'revisao')
 def test_nonbreaking_whitespace(self):
  self.assertEqual(parse_response('Saldo para quitação hoje: R$ 1.234,56. Total de\u00a0parcelas: 12')['total_parcelas'],12)
if __name__=='__main__':unittest.main()
