import importlib.util,uuid,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('api_partner_test',Path(__file__).resolve().parents[1]/'vps/api.py');api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
ACTOR=str(uuid.uuid4());PARTNER=str(uuid.uuid4())
PAYLOAD={'name':'Partner','email':'partner@example.invalid','password':'Strong-test-2027','active':True,'permissions':[{'service':'digimais_saldo_parcela','enabled':True,'allow_individual':True,'daily_limit':5,'allow_campaign':False},{'service':'tjba_margem','enabled':False,'allow_individual':False,'daily_limit':0,'allow_campaign':False}]}
class PartnerAdminTests(unittest.TestCase):
 def test_integration_token_cannot_create_account(self):
  with patch.object(api,'supabase_call') as call:
   with self.assertRaises(api.AdminError) as err:api.partner_admin('Bearer apc_'+'a'*64,'POST','/api/admin/parceiros',PAYLOAD)
   self.assertEqual(err.exception.status,401);call.assert_not_called()
 def test_partner_jwt_cannot_create_account(self):
  def upstream(path,*args,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   raise urllib.error.HTTPError(path,403,'Forbidden',{},None)
  with patch.object(api,'supabase_call',side_effect=upstream) as call:
   with self.assertRaises(api.AdminError) as err:api.partner_admin('Bearer test-jwt','POST','/api/admin/parceiros',PAYLOAD)
   self.assertEqual(err.exception.status,403);self.assertFalse(any(c.args[0]=='/auth/v1/admin/users' for c in call.call_args_list))
 def test_admin_creates_auth_user_and_restricts_profile_to_partner(self):
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':self.assertEqual(kwargs['bearer'],'test-jwt');return {'id':ACTOR}
   if path=='/auth/v1/admin/users':self.assertTrue(payload['email_confirm']);return {'id':PARTNER,'email':PAYLOAD['email']}
   if payload['p_action']=='check':return {'admin':True}
   self.assertEqual(payload['p_actor'],ACTOR);self.assertEqual(payload['p_input']['user_id'],PARTNER);self.assertNotIn('password',payload['p_input']);self.assertNotIn('role',payload['p_input']);return {'role':'partner'}
  with patch.object(api,'supabase_call',side_effect=upstream):
   status,result=api.partner_admin('Bearer test-jwt','POST','/api/admin/parceiros',{**PAYLOAD,'role':'admin'});self.assertEqual(status,201);self.assertEqual(result['data']['role'],'partner')
 def test_failed_permission_setup_cleans_up_new_auth_user(self):
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   if path=='/auth/v1/admin/users':return {'id':PARTNER}
   if kwargs.get('method')=='DELETE':return None
   if payload['p_action']=='check':return {'admin':True}
   raise OSError('database unavailable')
  with patch.object(api,'supabase_call',side_effect=upstream) as call:
   with self.assertRaises(api.AdminError):api.partner_admin('Bearer test-jwt','POST','/api/admin/parceiros',PAYLOAD)
   self.assertTrue(any(c.args[0].endswith('/'+PARTNER) and c.kwargs.get('method')=='DELETE' for c in call.call_args_list))
 def test_invalid_quota_rejected_before_creating_auth_user(self):
  with patch.object(api,'supabase_call',side_effect=[{'id':ACTOR},{'admin':True}]) as call:
   broken={**PAYLOAD,'permissions':[{**PAYLOAD['permissions'][0],'daily_limit':-1},PAYLOAD['permissions'][1]]}
   with self.assertRaises(api.AdminError):api.partner_admin('Bearer test-jwt','POST','/api/admin/parceiros',broken)
   self.assertEqual(call.call_count,2)

 def test_integration_flag_is_forwarded_as_boolean(self):
  for allowed in [True,False]:
   with self.subTest(allowed=allowed),patch.object(api,'supabase_call',side_effect=[{'id':ACTOR},{'admin':True},{'role':'partner'}]) as call:
    api.partner_admin('Bearer test-jwt','POST','/api/admin/parceiros/'+PARTNER,{**PAYLOAD,'allow_integrations':allowed})
    self.assertIs(call.call_args.args[1]['p_input']['allow_integrations'],allowed)
 def test_invalid_integration_flag_is_rejected(self):
  with patch.object(api,'supabase_call',side_effect=[{'id':ACTOR},{'admin':True}]) as call:
   with self.assertRaises(api.AdminError) as err:api.partner_admin('Bearer test-jwt','POST','/api/admin/parceiros/'+PARTNER,{**PAYLOAD,'allow_integrations':'true'})
   self.assertEqual(err.exception.status,422);self.assertEqual(call.call_count,2)
