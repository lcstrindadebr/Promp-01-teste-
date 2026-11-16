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

class RobotStateSizeTests(unittest.TestCase):
 def test_state_with_hundred_api_slots_is_published(self):
  import sys;sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
  from robot_metrics import RobotMetrics,Slot
  with tempfile.TemporaryDirectory() as d:
   path=Path(d)/'state.json';metrics=RobotMetrics(4,path=path)
   metrics.api_slots=[Slot(f'api-{i+1}') for i in range(100)]
   for slot in metrics.slots+metrics.api_slots:
    slot.begin('digimais_api');slot.saving({'status':'concluida','saldo_liquidacao':1,'valor_parcela':2});slot.saved()
   metrics.write(metrics.payload())
   self.assertGreater(path.stat().st_size,32768)
   activity=monitor.robot_activity(path)
   self.assertIsNotNone(activity)
   self.assertEqual(len(activity['slots']),4);self.assertEqual(len(activity['api_slots']),100)

