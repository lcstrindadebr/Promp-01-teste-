import importlib.util,io,json,uuid,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('api_company_users_test',Path(__file__).resolve().parents[1]/'vps/api.py');api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
ACTOR=str(uuid.uuid4());MEMBER=str(uuid.uuid4())
NEW={'name':'Operador','email':'Op@Empresa.invalid','password':'Provisoria-2027','role':'operador','overrides':{'clientes.exportar':True}}

def http_error(code,message=''):
 return urllib.error.HTTPError('url',code,'error',{},io.BytesIO(json.dumps({'message':message}).encode()))

class CompanyUsersTests(unittest.TestCase):
 def test_api_token_cannot_manage_users(self):
  with patch.object(api,'supabase_call') as call:
   with self.assertRaises(api.AdminError) as err:api.company_users('Bearer apc_'+'a'*64,'GET','/api/admin/usuarios',{})
   self.assertEqual(err.exception.status,401);call.assert_not_called()

 def test_creates_auth_account_with_temporary_password_then_member(self):
  calls=[]
  def upstream(path,payload=None,**kwargs):
   calls.append((path,payload,kwargs))
   if path=='/auth/v1/user':return {'id':ACTOR}
   if path=='/auth/v1/admin/users':
    self.assertTrue(payload['email_confirm']);self.assertEqual(payload['email'],'op@empresa.invalid');return {'id':MEMBER,'email':payload['email']}
   if payload['p_action']=='check':return {'actor_role':'administrador'}
   self.assertEqual(payload['p_action'],'create');self.assertNotIn('password',payload['p_input'])
   self.assertEqual(payload['p_input']['user_id'],MEMBER);self.assertEqual(payload['p_input']['overrides'],{'clientes.exportar':True})
   return {'user_id':MEMBER,'must_change_password':True}
  with patch.object(api,'supabase_call',side_effect=upstream):
   status,body=api.company_users('Bearer jwt','POST','/api/admin/usuarios',NEW)
  self.assertEqual(status,201);self.assertTrue(body['data']['must_change_password'])

 def test_rejected_member_removes_the_new_account(self):
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   if path=='/auth/v1/admin/users':return {'id':MEMBER}
   if kwargs.get('method')=='DELETE':return None
   if payload['p_action']=='check':return {}
   raise http_error(403,'Apenas administradores criam outros administradores.')
  with patch.object(api,'supabase_call',side_effect=upstream) as call:
   with self.assertRaises(api.AdminError) as err:api.company_users('Bearer jwt','POST','/api/admin/usuarios',{**NEW,'role':'administrador'})
  self.assertEqual(err.exception.message,'Apenas administradores criam outros administradores.')
  self.assertTrue(any(c.args[0]=='/auth/v1/admin/users/'+MEMBER and c.kwargs.get('method')=='DELETE' for c in call.call_args_list))

 def test_without_permission_no_account_is_created(self):
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   raise http_error(403,'Apenas quem gerencia usuários da empresa pode fazer isso.')
  with patch.object(api,'supabase_call',side_effect=upstream) as call:
   with self.assertRaises(api.AdminError) as err:api.company_users('Bearer jwt','POST','/api/admin/usuarios',NEW)
  self.assertEqual(err.exception.status,403)
  self.assertFalse(any(c.args[0]=='/auth/v1/admin/users' for c in call.call_args_list))

 def test_invalid_input_rejected_before_any_call_but_session(self):
  for broken in [{**NEW,'password':'curta'},{**NEW,'email':'sem-arroba'},{**NEW,'role':'supervisor'},{**NEW,'overrides':{'x':'sim'}}]:
   with self.subTest(broken=broken),patch.object(api,'supabase_call',side_effect=[{'id':ACTOR}]) as call:
    with self.assertRaises(api.AdminError) as err:api.company_users('Bearer jwt','POST','/api/admin/usuarios',broken)
    self.assertEqual(err.exception.status,422);self.assertEqual(call.call_count,1)

 def test_deactivation_also_blocks_login(self):
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   if path.startswith('/auth/v1/admin/users/'):self.assertEqual(payload,{'ban_duration':'876000h'});self.assertEqual(kwargs['method'],'PUT');return {}
   return {'user_id':MEMBER,'active':False}
  with patch.object(api,'supabase_call',side_effect=upstream) as call:
   api.company_users('Bearer jwt','POST','/api/admin/usuarios/'+MEMBER,{'active':False})
  self.assertTrue(any(c.args[0]=='/auth/v1/admin/users/'+MEMBER for c in call.call_args_list))

 def test_reset_sets_temporary_password_after_database_check(self):
  order=[]
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   if path=='/auth/v1/admin/users/'+MEMBER:order.append('auth');self.assertEqual(payload,{'password':'Nova-provisoria-1'});return {}
   order.append(payload['p_action']);return {'user_id':MEMBER,'must_change_password':True}
  with patch.object(api,'supabase_call',side_effect=upstream):
   api.company_users('Bearer jwt','POST','/api/admin/usuarios/'+MEMBER+'/senha',{'password':'Nova-provisoria-1'})
  self.assertEqual(order,['reset_password','auth'])

 def test_first_access_password_change_uses_the_user_session(self):
  seen=[]
  def upstream(path,payload=None,**kwargs):
   seen.append(path)
   if path=='/auth/v1/user' and kwargs.get('method')=='GET':return {'id':MEMBER}
   if path=='/auth/v1/user':self.assertEqual(kwargs['bearer'],'jwt');self.assertEqual(kwargs['method'],'PUT');return {}
   self.assertEqual(payload,{'p_actor':MEMBER});return None
  with patch.object(api,'supabase_call',side_effect=upstream):
   status,_=api.company_users('Bearer jwt','POST','/api/admin/minha-senha',{'password':'Minha-senha-2027'})
  self.assertEqual(status,200);self.assertEqual(seen[-1],'/rest/v1/rpc/tenant_password_changed')

 def test_rejected_new_password_keeps_the_flag(self):
  def upstream(path,payload=None,**kwargs):
   if kwargs.get('method')=='GET':return {'id':MEMBER}
   raise http_error(422,'New password should be different from the old password.')
  with patch.object(api,'supabase_call',side_effect=upstream) as call:
   with self.assertRaises(api.AdminError) as err:api.company_users('Bearer jwt','POST','/api/admin/minha-senha',{'password':'Provisoria-2027'})
  self.assertEqual(err.exception.status,422)
  self.assertFalse(any(c.args[0]=='/rest/v1/rpc/tenant_password_changed' for c in call.call_args_list))

class CompanyUserDeleteTests(unittest.TestCase):
 def test_delete_requires_typed_confirmation(self):
  with patch.object(api,'supabase_call',side_effect=[{'id':ACTOR}]) as call:
   with self.assertRaises(api.AdminError) as err:api.company_users('Bearer jwt','POST','/api/admin/usuarios/'+MEMBER+'/excluir',{'confirmacao':'sim'})
  self.assertEqual(err.exception.status,422);self.assertEqual(call.call_count,1)

 def test_database_first_then_login_removed(self):
  order=[]
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   if path=='/rest/v1/rpc/tenant_user_delete':order.append('db');self.assertEqual(payload,{'p_actor':ACTOR,'p_user':MEMBER});return {'registros':12,'user_id':MEMBER}
   if path=='/auth/v1/admin/users/'+MEMBER:order.append('auth');self.assertEqual(kwargs['method'],'DELETE');return None
   raise AssertionError(path)
  with patch.object(api,'supabase_call',side_effect=upstream):
   status,body=api.company_users('Bearer jwt','POST','/api/admin/usuarios/'+MEMBER+'/excluir',{'confirmacao':'EXCLUIR'})
  self.assertEqual(order,['db','auth']);self.assertTrue(body['data']['conta_removida']);self.assertEqual(body['data']['registros'],12)

 def test_refused_in_database_keeps_login(self):
  def upstream(path,payload=None,**kwargs):
   if path=='/auth/v1/user':return {'id':ACTOR}
   if path=='/rest/v1/rpc/tenant_user_delete':raise http_error(403,'O responsável pela empresa não pode ser excluído.')
   raise AssertionError('Login removed after a refusal')
  with patch.object(api,'supabase_call',side_effect=upstream):
   with self.assertRaises(api.AdminError) as err:api.company_users('Bearer jwt','POST','/api/admin/usuarios/'+MEMBER+'/excluir',{'confirmacao':'EXCLUIR'})
  self.assertEqual(err.exception.message,'O responsável pela empresa não pode ser excluído.')

if __name__=='__main__':unittest.main()
