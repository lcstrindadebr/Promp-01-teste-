"""Model the observed widget: fill does not fire the keyboard-driven validator."""
import sys, unittest
from unittest.mock import AsyncMock, patch
sys.path.insert(0,'vps')
from robot import start_chat, wait_menu, RobotError, CONSIGNADO, parse_response
class Field:
 def __init__(self,chat,index=0):self.chat=chat;self.index=index
 def nth(self,index):return Field(self.chat,index)
 async def fill(self,value):self.chat.values[self.index]=value
 async def press_sequentially(self,value,**kwargs):
  self.chat.values[self.index]=value;self.chat.valid[self.index]=True
 async def press(self,key):pass
 async def inner_text(self,**kwargs):return self.chat.text
class Button:
 def __init__(self,chat,name):self.chat=chat;self.name=name
 async def is_visible(self):return self.chat.ready
 async def click(self,**kwargs):
  self.chat.submissions+=1
  if all(self.chat.valid):self.chat.ready=True
  else:self.chat.text='Campo obrigatório'
class Chat:
 def __init__(self):self.values=['',''];self.valid=[False,False];self.ready=False;self.text='';self.submissions=0
 def locator(self,name):return Field(self)
 def get_by_role(self,role,**kwargs):return Button(self,kwargs.get('name'))
class RegistrationTests(unittest.IsolatedAsyncioTestCase):
 def test_bank_rejects_cpf_is_review_not_nonclient(self):
  result=parse_response('Infelizmente não foi informado um CPF válido. Seu atendimento será encerrado.',cpf_sent=True)
  self.assertEqual(result['status'],'revisao');self.assertIn('inválido',result['message'])
 async def test_keyboard_events_accept_form_once(self):
  c=Chat();await start_chat(c,{'nome':'TESTE','telefone':'(11) 99999-9999'},100)
  self.assertTrue(c.ready);self.assertEqual(c.values,['TESTE','11999999999']);self.assertEqual(c.submissions,1)
 async def test_rejected_form_fails_without_waiting_for_menu(self):
  c=Chat();c.text='Telefone Campo obrigatório'
  with self.assertRaisesRegex(RobotError,'formulário recusou'):await wait_menu(c,CONSIGNADO,100)
 async def test_expired_session_never_restarts_or_resubmits(self):
  c=Chat();c.text='A sessão de chat acabou'
  with self.assertRaisesRegex(RobotError,'encerrou'):await wait_menu(c,CONSIGNADO,100)
  self.assertEqual(c.submissions,0)
 async def test_bank_absent_menu_has_specific_failure(self):
  c=Chat()
  with self.assertRaisesRegex(RobotError,'Nenhum CPF foi enviado'):await wait_menu(c,CONSIGNADO,1,registration=True)
 async def test_delayed_menu_is_observed_without_duplicate_submit(self):
  c=Chat()
  async def become_ready(*args):c.ready=True
  with patch('robot.asyncio.sleep',side_effect=become_ready):await wait_menu(c,CONSIGNADO,100)
  self.assertEqual(c.submissions,0)
if __name__=='__main__':unittest.main()
