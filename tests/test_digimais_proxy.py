import json,sys,tempfile,unittest,urllib.request
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'vps'))
import digimais_proxy
from tjba_proxy import ProxyConfigError
# Sem arquivo, o urllib segue só o proxy do ambiente (o mesmo comportamento de urlopen antes).
def extra_proxies(opener):
 env=urllib.request.getproxies()
 return [h.proxies for h in opener.handlers if isinstance(h,urllib.request.ProxyHandler) and h.proxies and h.proxies!=env]

class DigimaisProxyTests(unittest.TestCase):
 def test_missing_file_is_direct(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'missing'
   self.assertEqual(digimais_proxy.launch_options(path),{})
   opener=digimais_proxy.opener(path)
   self.assertEqual(extra_proxies(opener),[])
   self.assertIn('acesso direto',digimais_proxy.describe(path))
 def test_api_and_browser_use_the_same_proxy_with_quoted_credentials(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'config';data={'server':'http://proxy.example:8080','username':'user@br','password':'p@ss:w/rd'}
   path.write_text(json.dumps(data))
   self.assertEqual(digimais_proxy.launch_options(path),{'proxy':data})
   proxies=extra_proxies(digimais_proxy.opener(path))[0]
   self.assertEqual(proxies['https'],'http://user%40br:p%40ss%3Aw%2Frd@proxy.example:8080')
   self.assertEqual(proxies['http'],proxies['https'])
   self.assertNotIn('p@ss',digimais_proxy.describe(path));self.assertIn('proxy.example:8080',digimais_proxy.describe(path))
 def test_invalid_file_stops_without_leaking_or_going_direct(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'config'
   for value in ['SECRET',json.dumps({'server':'http://user:SECRET@proxy:80'}),json.dumps({'server':'socks5://proxy:80'})]:
    path.write_text(value)
    for call in (digimais_proxy.launch_options,digimais_proxy.opener):
     with self.assertRaises(ProxyConfigError) as error:call(path)
     self.assertNotIn('SECRET',str(error.exception))
 def test_new_file_is_picked_up_without_restart(self):
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'config'
   self.assertEqual(extra_proxies(digimais_proxy.opener(path)),[])
   path.write_text(json.dumps({'server':'http://proxy.example:3128'}))
   proxies=extra_proxies(digimais_proxy.opener(path))
   self.assertEqual(proxies[0]['https'],'http://proxy.example:3128')
 def test_api_robot_and_diagnostic_use_the_digimais_proxy(self):
  vps=ROOT/'vps'
  self.assertIn('digimais_proxy.urlopen(req,timeout=45)',(vps/'digimais_api.py').read_text())
  self.assertNotIn('urllib.request.urlopen(',(vps/'digimais_api.py').read_text())
  self.assertIn('**launch_options()',(vps/'robot.py').read_text())
  self.assertIn('**(options or {})',(vps/'diagnose.py').read_text())
  self.assertIn('8) Configurar ou remover proxy Digi+',(ROOT/'instalar.sh').read_text())
 def test_api_request_goes_through_the_opener(self):
  import asyncio,digimais_api
  seen=[]
  class Opener:
   def open(self,req,timeout):
    seen.append(req.full_url);raise OSError('stop')
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'config';path.write_text(json.dumps({'server':'http://proxy.example:3128'}))
   with patch.object(digimais_proxy,'CONFIG',path),patch.object(digimais_proxy,'opener',return_value=Opener()),\
    patch.object(urllib.request,'urlopen',side_effect=AssertionError('direct access with a proxy configured')):
    self.run_flow()
  self.assertTrue(seen and seen[0].startswith('https://c1webchatapi.voltdigital.com.br/api/auth/login-public'))
 def run_flow(self):
  import asyncio,digimais_api
  if True:
   session=digimais_api.ApiSession({'baseUrl':'https://c1webchatapi.voltdigital.com.br/api','code':'c','accountUid':'a'})
   with patch.object(asyncio,'sleep',new=lambda *_:asyncio.sleep(0)):
    try:asyncio.run(session.flow({'nome':'Teste','telefone':'11999999999','cpf':'00000000191'},'saldo'))
    except Exception:pass

if __name__=='__main__':unittest.main()
