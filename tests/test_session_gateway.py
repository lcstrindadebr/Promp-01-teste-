import sys,unittest,json,threading,urllib.request,urllib.error
from unittest.mock import patch,MagicMock
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
import api,auth_session

class SessionTests(unittest.TestCase):
 def test_public_key_and_timeout(self):
  response=MagicMock()
  response.__enter__.return_value=response
  response.status=200
  response.read.return_value=b'{"access_token":"test"}'
  with patch.object(auth_session,'configuration',return_value=('https://project.supabase.co','sb_publishable_test')),patch.object(auth_session,'urlopen',return_value=response) as call:
   status,data=auth_session.exchange('/api/session/login',{'email':'test@example.com','password':'test'},'')
   self.assertEqual(status,200)
   self.assertEqual(call.call_args.kwargs['timeout'],55)
   self.assertEqual(call.call_args.args[0].headers['Apikey'],'sb_publishable_test')
   self.assertNotIn('Authorization',call.call_args.args[0].headers)
 def test_public_configuration(self):
  import tempfile,os
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);(root/'dist').mkdir()
   (root/'dist/supabase-config.js').write_text('window.SUPABASE_CONFIG = '+json.dumps({'url':'https://project.supabase.co','key':'sb_publishable_test'})+';')
   with patch.dict(os.environ,{'APOIARCRED_APP':directory,'SUPABASE_URL':'https://project.supabase.co'}):
    self.assertEqual(auth_session.configuration(),('https://project.supabase.co','sb_publishable_test'))
 def test_timeout(self):
  with patch.object(auth_session,'configuration',return_value=('https://project.supabase.co','public')),patch.object(auth_session,'urlopen',side_effect=TimeoutError()):
   self.assertEqual(auth_session.exchange('/api/session/login',{},'')[0],504)
 def test_missing_token(self):
  with patch.object(auth_session,'configuration',return_value=('https://project.supabase.co','public')):
   self.assertEqual(auth_session.exchange('/api/session/access',{},'')[0],401)
 def test_http_entrypoint(self):
  import io
  class Socket:
   def __init__(self,request):self.request=request;self.response=b''
   def makefile(self,*args):return io.BytesIO(self.request)
   def settimeout(self,*args):pass
   def sendall(self,data):self.response+=data
  def request(path,body=b'',extra=''):
   method='POST' if body else 'GET'
   data=(method+' '+path+' HTTP/1.0\r\nContent-Type: application/json\r\nContent-Length: '+str(len(body))+'\r\n'+extra+'\r\n').encode()+body
   sock=Socket(data)
   api.Handler(sock,('127.0.0.1',1),MagicMock())
   return sock.response
  with patch.object(auth_session,'exchange',return_value=(200,{'access_token':'example'})) as exchange:
   result=request('/api/session/login',b'{"email":"test@example.com","password":"test"}')
   self.assertIn(b'200 OK',result)
   self.assertIn(b'Cache-Control: no-store',result)
   self.assertEqual(exchange.call_args.args[0],'/api/session/login')
   result=request('/api/session/login',b'{"email":"test@example.com","password":"test"}','Sec-Fetch-Site: cross-site\r\n')
   self.assertIn(b'403',result)
  self.assertIn(b'"session_gateway": true',request('/api/health'))
if __name__=='__main__':unittest.main()
