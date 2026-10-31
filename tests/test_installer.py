"""Exercise installer control flow in a temporary filesystem; never install packages."""
import os, pathlib, pty, select, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class InstallerTests(unittest.TestCase):
 def simulate(self,domain='consultas.example.com',dns_ok=True):
  with tempfile.TemporaryDirectory() as td:
   base=pathlib.Path(td);src=base/'source';src.mkdir();bin=base/'bin';bin.mkdir()
   for name in ['dist','vps']:
    (src/name).mkdir()
   for f in ['dist/index.html','dist/app.js','dist/supabase.js','dist/supabase-config.js','vps/worker.py','vps/robot.py','vps/requirements.txt']:
    (src/f).write_text('test')
   replacements={'/opt/apoiarcred':str(base/'app'),'/etc/nginx':str(base/'nginx'),'/etc/systemd/system':str(base/'systemd'),'/var/www/apoiarcred-acme':str(base/'acme'),'/etc/letsencrypt':str(base/'tls'),'/var/lib/apoiarcred':str(base/'home'),'/var/tmp/apoiarcred-install.':str(base/'run.'),'/run/lock/apoiarcred-instalar.lock':str(base/'lock')}
   code=(ROOT/'scripts/install-core.sh').read_text().replace('\"$(dirname -- \"${BASH_SOURCE[0]}\")/..\"','\"$(dirname -- \"${BASH_SOURCE[0]}\")\"')
   code=code.replace('SOURCE=$(cd -- \"$(dirname -- \"${BASH_SOURCE[0]}\")/..\" && pwd)', 'SOURCE='+str(src))
   for old,new in replacements.items():code=code.replace(old,new)
   (src/'instalar.sh').write_text(code)
   (src/'scripts').mkdir()
   (src/'scripts/configure_supabase.py').write_text((ROOT/'scripts/configure_supabase.py').read_text())
   (src/'dist/supabase-config.js').write_text('window.SUPABASE_CONFIG = {\"url\":\"https://aaaaaaaaaaaaaaaaaaaa.supabase.co\",\"key\":\"sb_publishable_test\"};')
   for d in ['nginx/sites-available','nginx/sites-enabled','systemd']:(base/d).mkdir(parents=True)
   def mock(name,text):
    p=bin/name;p.write_text('#!/bin/bash\n'+text);p.chmod(0o755)
   for name in ['apt-get','nginx','id','useradd','ufw']:mock(name,'exit 0\n')
   mock('ss','echo "State Recv-Q Send-Q Local Peer Process"\n')
   mock('systemctl','if [[ "$1" == is-active ]]; then [[ -f "$TEST_ROOT/started" ]]; elif [[ "$1" == restart ]]; then touch "$TEST_ROOT/started"; fi\n')
   mock('python3','if [[ \"$1\" != -m ]]; then exec /usr/bin/python3 \"$@\"; fi\nmkdir -p "$3/bin"\nprintf "#!/bin/bash\\nexit 0\\n" > "$3/bin/pip"\nprintf \'#!/bin/bash\\nmkdir -p "$PLAYWRIGHT_BROWSERS_PATH"\\n\' > "$3/bin/playwright"\nchmod +x "$3/bin/"*\n')
   mock('curl','if [[ "$*" == *apoiarcred-check* ]]; then\n [[ "$DNS_OK" == 1 ]] || exit 22\n cat "$TEST_ROOT/acme/.well-known/acme-challenge/apoiarcred-check"\nfi\n')
   mock('certbot','exit 0\n')
   master,slave=pty.openpty()
   proc=subprocess.Popen(['/bin/bash',str(src/'instalar.sh')],stdin=slave,stdout=slave,stderr=slave,env={**os.environ,'PATH':str(bin)+':'+os.environ['PATH'],'TEST_ROOT':td,'DNS_OK':'1' if dns_ok else '0'})
   os.close(slave);output=b''
   replies=[('Subdomínio',domain),('E-mail para','admin@example.com'),('Chave secreta','sb_secret_'+'x'*40),('Iniciar instalação','s')]
   try:
    import time
    deadline=time.time()+20
    while time.time()<deadline:
     ready,_,_=select.select([master],[],[],.1)
     if ready:
      try:chunk=os.read(master,65536)
      except OSError:break
      if not chunk:break
      output+=chunk
      if replies and replies[0][0].encode() in output:
       _,answer=replies.pop(0);os.write(master,(answer+'\n').encode())
     if proc.poll() is not None:break
    proc.wait(timeout=5)
   finally:
    if proc.poll() is None:proc.kill();proc.wait()
    os.close(master)
   state={'env':(base/'app/.env').exists(),'nginx':(base/'nginx/sites-available/apoiarcred-mvp.conf').exists(),'unit':(base/'systemd/apoiarcred-robo.service').exists(),'temp_secrets':[p.read_text() for p in base.glob('run.*/curl-auth')]}
   return proc.returncode,output.decode(errors='replace'),state
 def test_install_success(self):
  code,out,state=self.simulate();self.assertEqual(code,0,out);self.assertTrue(state['unit']);self.assertTrue(state['nginx']);self.assertNotIn('sb_secret_'+'x'*40,out)
 def test_dns_failure_restores_nginx(self):
  code,out,state=self.simulate(dns_ok=False);self.assertNotEqual(code,0,out);self.assertFalse(state['nginx']);self.assertFalse(state['unit']);self.assertEqual(state['temp_secrets'],[''])
 def test_invalid_domain_rejected_before_changes(self):
  code,out,state=self.simulate(domain='example.com;touch /tmp/bad');self.assertNotEqual(code,0,out);self.assertFalse(state['env'])
if __name__=='__main__':unittest.main()

