import sys, unittest, threading
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vps'))
import amigoz_queue as q

JOB=dict(id='job',lease='lease',cpf='00000000101',convenio='amigoz_33',modo='ambos',numero_matricula='TESTE')
class QueueTests(unittest.TestCase):
 def test_modes_and_partial_result_preserved(self):
  result={'margem':{'status':'erro','mensagem':'Falha'},'saque':{'status':'respondido','dados':{'ofertas':[]}}}
  with patch.object(q.amigoz_api,'consultation',return_value=result) as call:
   status,data,_=q.process(JOB,{})
   self.assertEqual(status,'revisao');self.assertEqual(data,result)
   self.assertEqual(call.call_args.args[1]['convenio_id'],33)
   self.assertEqual(call.call_args.args[1]['numero_matricula'],'TESTE')
 def test_database_retry_does_not_repeat_provider(self):
  stop=threading.Event();saves=[]
  def db(path,payload):
   if 'claim_' in path:return [JOB]
   saves.append(payload)
   if len(saves)==1:raise RuntimeError('database unavailable')
   stop.set();return True
  with patch.object(q.amigoz_api,'configuration',return_value={'configured':True}),patch.object(q,'process',return_value=('concluida',{},'OK')) as provider,patch.object(stop,'wait',return_value=False):
   q.run(db,stop)
   self.assertEqual(provider.call_count,1);self.assertEqual(len(saves),2)
   self.assertEqual(saves[0],saves[1])
 def test_missing_config_does_not_claim_or_call_provider(self):
  stop=threading.Event()
  with patch.object(q.amigoz_api,'configuration',return_value=None),patch.object(stop,'wait',side_effect=lambda _:stop.set()),patch.object(q,'process') as provider:
   calls=[];q.run(lambda *args:calls.append(args),stop)
   self.assertEqual(calls,[]);provider.assert_not_called()
if __name__=='__main__':unittest.main()
