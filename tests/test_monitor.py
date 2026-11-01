import importlib.util,json,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('monitor',Path(__file__).resolve().parents[1]/'vps/monitor.py');monitor=importlib.util.module_from_spec(spec);spec.loader.exec_module(monitor)
class MonitorTests(unittest.TestCase):
 def test_cpu_delta(self):
  self.assertEqual(monitor.cpu_percent((100,50),(200,75)),75)
  self.assertIsNone(monitor.cpu_percent((100,50),(100,50)))
 def test_available_memory(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'mem';p.write_text('MemTotal: 1000 kB\nMemAvailable: 600 kB\nSwapTotal: 200 kB\nSwapFree: 150 kB\n')
   v=monitor.memory(p);self.assertEqual(v['used'],409600);self.assertEqual(v['percent'],40);self.assertEqual(v['swap_used'],51200)
 def test_unknown_service(self):
  with patch.object(monitor.subprocess,'run',side_effect=OSError):self.assertEqual(monitor.worker_state(),'unknown')
 def test_publish(self):
  with patch.dict(os.environ,{'SUPABASE_URL':'https://test.invalid','SUPABASE_SERVICE_ROLE_KEY':'sb_secret_test'}),patch.object(monitor.urllib.request,'urlopen') as send:
   monitor.publish({'cpu_percent':42});req=send.call_args.args[0];body=json.loads(req.data)
   self.assertEqual(body['id'],'principal');self.assertEqual(body['payload'],{'cpu_percent':42});self.assertNotIn('sb_secret',req.data.decode());self.assertEqual(send.call_args.kwargs['timeout'],4)
