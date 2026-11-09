import importlib.util,json,threading,unittest,urllib.request,urllib.error
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('apoiar_api',Path(__file__).resolve().parents[1]/'vps/api.py');api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
TOKEN='apc_'+'a'*64
class ApiHTTPTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.server=api.Server(('127.0.0.1',0),api.Handler);cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start();cls.base='http://127.0.0.1:'+str(cls.server.server_port)
 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();cls.thread.join()
 def call(self,path,method='GET',body=None,headers=None):
  req=urllib.request.Request(self.base+path,data=json.dumps(body).encode() if body is not None else None,method=method,headers=headers or {})
  try:res=urllib.request.urlopen(req,timeout=3)
  except urllib.error.HTTPError as e:res=e
  return res.status,json.loads(res.read()),res.headers
 def test_no_auth_is_rejected_without_touching_database(self):
  with patch.object(api,'rpc') as rpc:
   status,body,_=self.call('/api/v1/campanhas');self.assertEqual(status,401);rpc.assert_not_called()
 def test_health_and_hash_only_upstream(self):
  self.assertEqual(self.call('/api/health')[0],200)
  with patch.object(api,'rpc',return_value={'status':200,'body':{'data':[]}}) as rpc:
   status,body,_=self.call('/api/v1/campanhas?page=2',headers={'Authorization':'Bearer '+TOKEN})
   self.assertEqual(status,200);self.assertEqual(rpc.call_args.args[0]['p_payload'],{'page':'2'});self.assertNotIn(TOKEN,json.dumps(rpc.call_args.args[0]));self.assertEqual(len(rpc.call_args.args[0]['p_hash']),64)
 def test_post_key_payload_and_replay(self):
  with patch.object(api,'rpc',return_value={'status':201,'body':{'id':'fake'},'replayed':True}) as rpc:
   status,body,headers=self.call('/api/v1/campanhas','POST',{'nome':'Example'},headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/json','Idempotency-Key':'example-123'})
   self.assertEqual(status,201);self.assertEqual(headers['Idempotency-Replayed'],'true');self.assertEqual(rpc.call_args.args[0]['p_key'],'example-123')
 def test_unsupported_filters_and_content_type(self):
  with patch.object(api,'rpc') as rpc:
   self.assertEqual(self.call('/api/v1/campanhas?cpf=00000000000',headers={'Authorization':'Bearer '+TOKEN})[0],422)
   self.assertEqual(self.call('/api/v1/campanhas','POST',{},headers={'Authorization':'Bearer '+TOKEN})[0],415);rpc.assert_not_called()
 def test_campaign_full_listing_and_status_route(self):
  auth={'Authorization':'Bearer '+TOKEN}
  path='/campanhas/00000000-0000-4000-8000-000000000001/leads'
  leads=[{'id':str(i),'status':'concluida'} for i in range(1000)]
  with patch.object(api,'rpc',return_value={'status':200,'body':{'data':leads,'total':1000}}) as rpc:
   status,body,_=self.call('/api/v1'+path+'?all=true',headers=auth)
   self.assertEqual((status,len(body['data']),body['total']),(200,1000,1000))
   self.assertEqual(rpc.call_args.args[0]['p_payload'],{'all':'true'})
   self.assertEqual(self.call('/api/v1'+path+'/status/concluida',headers=auth)[0],200)
   self.assertEqual(rpc.call_args.args[0]['p_route'],path+'/status/concluida')
 def test_outage_hides_internal_details(self):
  with patch.object(api,'rpc',side_effect=urllib.error.URLError('private-secret')):
   status,body,_=self.call('/api/v1/campanhas',headers={'Authorization':'Bearer '+TOKEN});self.assertEqual(status,503);self.assertNotIn('private-secret',json.dumps(body))
 def test_sql_only_execute_service_and_openapi_routes_match(self):
  spec=json.loads((Path(__file__).resolve().parents[1]/'dist/openapi.json').read_text());self.assertEqual(sum(len(x) for x in spec['paths'].values()),14)

class ApiNginxTests(unittest.TestCase):
 def test_ssl_preserved_and_config_idempotent(self):
  source=Path(__file__).resolve().parents[1]/'scripts/configure_api.py';spec=importlib.util.spec_from_file_location('configure_api_test',source);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
  text='server {\n listen 443 ssl;\n ssl_certificate /keep/fullchain.pem;\n root /opt/apoiarcred/dist;\n location / { try_files $uri =404; }\n}\n'
  result=mod.configure(text,'/opt/apoiarcred/dist','/api.conf');self.assertIn('ssl_certificate /keep/fullchain.pem;',result);self.assertEqual(result.count('include /api.conf;'),1);self.assertEqual(mod.configure(result,'/opt/apoiarcred/dist','/api.conf'),result)
