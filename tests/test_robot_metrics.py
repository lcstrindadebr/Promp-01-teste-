import json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,'vps')
from robot_metrics import Slot,RobotMetrics
from monitor import robot_activity

class MetricsTests(unittest.TestCase):
 def test_saved_only_counts_once_and_classifies_results(self):
  slot=Slot('principal')
  with patch('robot_metrics.time.monotonic',return_value=100):slot.begin('digimais')
  with patch('robot_metrics.time.monotonic',return_value=130):
   slot.report(50);slot.saving({'status':'concluida','cpf':'not-exported'})
   self.assertEqual(slot.snapshot()['finished_last_hour'],0)
  with patch('robot_metrics.time.monotonic',return_value=135):
   slot.saved();data=slot.snapshot()
  self.assertEqual(data['state'],'idle');self.assertEqual(data['average_seconds'],30)
  self.assertEqual(data['conclusive_last_hour'],1);self.assertNotIn('cpf',json.dumps(data))
  with patch('robot_metrics.time.monotonic',return_value=140):
   for status in ['nao_cliente','revisao','erro']:
    slot.begin('digimais');slot.saving({'status':status});slot.saved();slot.saved()
   self.assertEqual(slot.snapshot()['finished_last_hour'],4)
   self.assertEqual(slot.snapshot()['errors_last_hour'],1)
   self.assertEqual(slot.snapshot()['review_last_hour'],1)
 def test_hourly_window_and_empty_averages(self):
  slot=Slot('second');slot.events.extend([(1,'concluida',10),(3599,'nao_cliente',20)])
  with patch('robot_metrics.time.monotonic',return_value=3602):
   data=slot.snapshot();self.assertEqual(data['finished_last_hour'],1);self.assertEqual(data['average_seconds'],20)
  with patch('robot_metrics.time.monotonic',return_value=7200):
   data=slot.snapshot();self.assertEqual(data['finished_last_hour'],0);self.assertIsNone(data['average_seconds'])
 def test_atomic_aggregate_file_and_missing_invalid_collector(self):
  with tempfile.TemporaryDirectory() as directory:
   path=Path(directory)/'state.json';metrics=RobotMetrics(2,path)
   self.assertIsNone(robot_activity(path))
   metrics.slots[0].begin('digimais');metrics.slots[1].begin('digimais')
   metrics.write(metrics.payload());data=robot_activity(path)
   self.assertEqual(len(data['slots']),2);self.assertEqual(data['slots'][0]['state'],'consulting')
   self.assertEqual(path.stat().st_mode&0o777,0o600)
   self.assertFalse(path.with_suffix('.tmp').exists())
   self.assertNotIn('user_id',json.dumps(data));self.assertNotIn('job_id',json.dumps(data))
   path.write_text('{');self.assertIsNone(robot_activity(path))
 def test_single_executor(self):self.assertEqual(len(RobotMetrics(1).slots),1)
