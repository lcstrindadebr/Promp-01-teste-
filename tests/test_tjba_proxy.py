import json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
from tjba_proxy import launch_options,validate

class ProxyTests(unittest.TestCase):
 def test_missing_is_direct(self):
  with tempfile.TemporaryDirectory() as d:self.assertEqual(launch_options(Path(d)/'missing'),{})
 def test_private_credentials_are_passed(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'config';data={'server':'http://proxy.example:8080','username':'test','password':'fake $ special " value'}
   p.write_text(json.dumps(data));self.assertEqual(launch_options(p),{'proxy':data})
 def test_invalid_never_falls_back_or_leaks(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'config'
   for value in ['SECRET',json.dumps({'server':'http://user:SECRET@proxy:80'}),json.dumps({'server':'socks5://proxy:80'})]:
    p.write_text(value)
    with self.assertRaises(ValueError) as error:launch_options(p)
    self.assertNotIn('SECRET',str(error.exception))
 def test_bad_port_and_incomplete_auth(self):
  for data in [{'server':'http://proxy:99999'},{'server':'http://proxy:80','username':'test'},{'server':'http://proxy:80/path'}]:
   with self.assertRaises(ValueError):validate(data)
 def test_both_tjba_launches_use_options_and_digi_does_not(self):
  root=Path(__file__).resolve().parents[1]/'vps'
  self.assertIn('**launch_options()', (root/'tjba.py').read_text())
  self.assertIn('**options', (root/'diagnose_tjba.py').read_text())
  self.assertNotIn('tjba_proxy', (root/'robot.py').read_text())
