import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
import amigoz_api as amigoz
import api

CONFIG={'url':'https://api.example.com','usuario':'fixture','senha':'fixture-secret','corban_id':7}


class AmigozTests(unittest.TestCase):
 def test_catalog_and_non_operational_record(self):
  self.assertEqual(len(amigoz.CATALOG),113)
  self.assertEqual({i:amigoz.CATALOG[i]['uf'] for i in (4,52,131,156,157,16,33)},
                   {4:'MG',52:'MG',131:'AM',156:'PA',157:'PA',16:'BR',33:'SP'})
  self.assertNotIn(150,amigoz.CATALOG)
  self.assertIsNone(amigoz.CATALOG[131]['averbadora'])

 def test_saved_password_is_private_and_cannot_follow_a_changed_host(self):
  with tempfile.TemporaryDirectory() as directory,patch.dict(os.environ,STATE_DIRECTORY=directory):
   summary=amigoz.save_configuration(CONFIG)
   self.assertNotIn('senha',summary)
   self.assertEqual(amigoz.credentials_path().stat().st_mode & 0o777,0o600)
   self.assertEqual(amigoz.configuration(),CONFIG)
   amigoz.save_configuration({**CONFIG,'senha':'','corban_id':8})
   self.assertEqual(amigoz.configuration()['senha'],CONFIG['senha'])
   with self.assertRaises(amigoz.AmigozError):
    amigoz.save_configuration({**CONFIG,'url':'https://other.example.com','senha':''})

 def test_auth_login_corban_and_refresh(self):
  with patch.object(amigoz,'SESSION',None),patch.object(amigoz,'request',side_effect=[
   {'access':'initial','refresh':'renew'},
   {'access_token':'scoped'},
   amigoz.AmigozError(401,'expired','Token expirado'),
   {'data':{'access':'renewed'}},
   {},
   [],
  ]) as transport:
   self.assertEqual(amigoz.call(CONFIG,'/api/simulacao/v2/saque-complementar',{'cpf':'00000000001'}),[])
  calls=[call.args for call in transport.call_args_list]
  self.assertEqual(calls[1][1:],('/api/login/seleciona-corban',{'corban_id':7},'initial'))
  self.assertEqual(calls[3][1:],('/api/login/refresh',{'refresh':'renew'}))
  self.assertEqual(calls[-1][-1],'renewed')

 def test_both_modes_preserve_success_and_match_only_selected_convenio(self):
  with patch.object(amigoz,'call',side_effect=[
   [{'convenio_cliente':'GOVERNO DE SAO PAULO','valor_saque_disponivel':123,'numero_cartao_cliente':1234},
    {'convenio_cliente':'SP','valor_saque_disponivel':999},
    {'convenio_cliente':'Polícia Militar - São Paulo','valor_saque_disponivel':888}],
   amigoz.AmigozError(502,'fixture','Falha na margem'),
  ]) as call:
   result=amigoz.consultation(CONFIG,{'modo':'ambos','cpf':'000.000.000-01','convenio_id':23,'numero_matricula':'00001'})
  self.assertEqual(result['saque']['dados']['total_sem_correspondencia'],2)
  self.assertEqual(result['saque']['dados']['ofertas'][0]['valor_saque_disponivel'],123)
  self.assertNotIn('numero_cartao_cliente',result['saque']['dados']['ofertas'][0])
  self.assertEqual(result['margem']['status'],'erro')
  self.assertEqual(call.call_args_list[0].args[-1],{'cpf':'00000000001'})
  self.assertEqual(call.call_args_list[1].args[-1],{'cpf':'00000000001','convenio':23,'averbadora':9,'numero_matricula':'00001'})

 def test_missing_averbadora_does_not_contact_provider(self):
  with patch.object(amigoz,'call') as call:
   result=amigoz.consultation(CONFIG,{'modo':'margem','cpf':'00000000001','convenio_id':131})
  self.assertEqual(result['margem']['status'],'indisponivel')
  call.assert_not_called()

 def test_admin_denial_precedes_provider_access(self):
  from urllib.error import HTTPError
  with patch.object(api,'supabase_call',side_effect=[{'id':'fixture'},HTTPError('',403,'Forbidden',{},None)]),patch.object(amigoz,'configuration') as config:
   with self.assertRaises(api.AdminError) as caught:
    api.amigoz_admin('Bearer fixture','POST','/api/admin/amigoz/consultar',{})
  self.assertEqual(caught.exception.status,403)
  config.assert_not_called()

 def test_private_address_is_rejected_before_dial(self):
  with patch.object(amigoz.socket,'getaddrinfo',return_value=[(None,None,None,None,('127.0.0.1',443))]),patch.object(amigoz.socket,'create_connection') as dial:
   with self.assertRaises(amigoz.AmigozError):
    amigoz.PublicHTTPS('private.example.com').connect()
  dial.assert_not_called()


if __name__=='__main__':
 unittest.main()
