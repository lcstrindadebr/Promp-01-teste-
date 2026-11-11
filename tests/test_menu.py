import os,pathlib,pty,select,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class MenuTests(unittest.TestCase):
 def exercise(self,installed,choice):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);app=root/'app';(root/'scripts').mkdir();(app/'vps').mkdir(parents=True);(app/'.venv/bin').mkdir(parents=True)
   if installed:
    (app/'.env').write_text('secret');(app/'vps/worker.py').touch();(app/'.venv/bin/python').touch();(app/'.venv/bin/python').chmod(0o755)
   (root/'instalar.sh').write_text((ROOT/'instalar.sh').read_text().replace('/opt/apoiarcred',str(app)))
   (root/'atualizar.sh').write_text('echo UPDATE_ONLY\n');(root/'scripts/install-core.sh').write_text('echo INSTALL_NEW\n')
   m,s=pty.openpty();p=subprocess.Popen(['bash',str(root/'instalar.sh')],stdin=s,stdout=s,stderr=s);os.close(s);out=b''
   try:
    while p.poll() is None:
     if select.select([m],[],[],2)[0]:
      try:out+=os.read(m,65536)
      except OSError:break
      if b'Escolha uma' in out:os.write(m,(choice+'\n').encode());break
    p.wait(timeout=5)
    try:
     while select.select([m],[],[],.1)[0]:out+=os.read(m,65536)
    except OSError:pass
   finally:
    if p.poll() is None:p.kill();p.wait()
    os.close(m)
   return out.decode(),p.returncode
 def test_existing_instance_only_updates(self):
  out,code=self.exercise(True,'1');self.assertEqual(code,0,out);self.assertIn('UPDATE_ONLY',out);self.assertNotIn('INSTALL_NEW',out);self.assertNotIn('Subdomínio',out)
 def test_new_instance_installs(self):
  out,code=self.exercise(False,'1');self.assertEqual(code,0,out);self.assertIn('INSTALL_NEW',out);self.assertNotIn('UPDATE_ONLY',out)
 def test_exit_does_not_mutate(self):
  out,code=self.exercise(True,'0');self.assertEqual(code,0,out);self.assertNotIn('UPDATE_ONLY',out)
if __name__=='__main__':unittest.main()
