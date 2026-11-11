import importlib.util,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('drain',Path(__file__).resolve().parents[1]/'scripts/drain_queue.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class DrainTests(unittest.TestCase):
 def test_waits_for_saved_results_and_releases_same_token(self):
  calls=[];pending=iter([2,1,0])
  def call(app,token,release=False):calls.append((token,release));return 0 if release else next(pending)
  with tempfile.TemporaryDirectory() as d:
   app=Path(d);module.drain(app,call=call,wait=lambda n:None)
   self.assertEqual(len(calls),3);self.assertTrue((app/'.update-queue-token').exists())
   module.drain(app,release=True,call=call)
   self.assertFalse((app/'.update-queue-token').exists());self.assertEqual(len({t for t,_ in calls}),1);self.assertTrue(calls[-1][1])
 def test_timeout_unpauses_without_requeueing_jobs(self):
  calls=[];times=iter([0,601])
  def call(app,token,release=False):calls.append(release);return 1
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(RuntimeError):module.drain(Path(d),call=call,clock=lambda:next(times),wait=lambda n:None)
   self.assertEqual(calls,[False,True]);self.assertFalse((Path(d)/'.update-queue-token').exists())
