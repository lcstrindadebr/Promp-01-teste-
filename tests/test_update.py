"""Local Git fixture: verify the updater executes downloaded code and preserves settings."""
import json,os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class UpdateTests(unittest.TestCase):
 def test_downloaded_updater_deploys_robot_panel_and_service(self):
  with tempfile.TemporaryDirectory() as d:
   base=pathlib.Path(d);origin=base/'remote';repo=base/'source';app=base/'app';bin=base/'bin';bin.mkdir();origin.mkdir();units=base/'systemd';units.mkdir()
   env={**os.environ,'GIT_AUTHOR_NAME':'Test','GIT_AUTHOR_EMAIL':'test@example.com','GIT_COMMITTER_NAME':'Test','GIT_COMMITTER_EMAIL':'test@example.com'}
   def git(*args,cwd=origin):return subprocess.check_output(['/usr/bin/git',*args],cwd=cwd,env=env,stderr=subprocess.DEVNULL,text=True).strip()
   git('init','-b','apoiarcred-consultas-mvp')
   (origin/'scripts').mkdir();(origin/'scripts/update-core.sh').write_text('echo OLD_UPDATER; exit 55\n');(origin/'README.md').write_text('initial');git('add','.');git('commit','-m','initial')
   subprocess.run(['/usr/bin/git','clone',str(origin),str(repo)],env=env,check=True,capture_output=True)
   def replace_paths(s):return s.replace('/opt/apoiarcred-src',str(repo)).replace('/opt/apoiarcred',str(app)).replace('/run/lock/apoiarcred-instalar.lock',str(base/'lock')).replace('/var/tmp/apoiarcred-update.',str(base/'backup.')).replace('/etc/systemd/system',str(units))
   for f in ['scripts/update-core.sh','scripts/configure_supabase.py','deploy/apoiarcred-robo.service']:
    p=origin/f;p.parent.mkdir(exist_ok=True);p.write_text(replace_paths((ROOT/f).read_text()))
   (origin/'dist').mkdir();(origin/'vps').mkdir()
   (origin/'dist/index.html').write_text('NEW PANEL');(origin/'dist/supabase-config.js').write_text('new repo config')
   (origin/'vps/robot.py').write_text('# NEW ROBOT');(origin/'vps/worker.py').write_text('# NEW WORKER');(origin/'vps/requirements.txt').write_text('')
   (origin/'vps/chat_browser.py').write_text('# NEW NAVIGATION');(origin/'vps/diagnose.py').write_text('# NEW DIAGNOSTIC')
   git('add','.');git('commit','-m','new version')
   (repo/'atualizar.sh').write_text(replace_paths((ROOT/'atualizar.sh').read_text()))
   # Keep the checkout clean, as on a real installation.
   git('add','atualizar.sh',cwd=repo);git('commit','-m','launcher',cwd=repo);git('push','origin','HEAD:launcher',cwd=repo)
   # Clone-only launcher is a fixture outside the tracked tree for a clean ff-only pull.
   launcher=base/'launcher.sh';launcher.write_text((repo/'atualizar.sh').read_text());git('reset','--hard','HEAD~1',cwd=repo)
   for p in ['dist','vps','.venv/bin','browsers']:(app/p).mkdir(parents=True)
   (app/'dist/index.html').write_text('OLD PANEL');(app/'vps/robot.py').write_text('# OLD ROBOT')
   original_env='SUPABASE_URL=https://aaaaaaaaaaaaaaaaaaaa.supabase.co\nSUPABASE_SERVICE_ROLE_KEY=sb_secret_do_not_copy\nROBOT_MODE=live\n';(app/'.env').write_text(original_env)
   public={'url':'https://aaaaaaaaaaaaaaaaaaaa.supabase.co','key':'sb_publishable_custom'};(app/'supabase-public.json').write_text(json.dumps(public))
   def executable(path,content):path.write_text('#!/bin/bash\n'+content);path.chmod(0o755)
   executable(app/'.venv/bin/python','exit 0\n');executable(app/'.venv/bin/pip','exit 0\n');executable(app/'.venv/bin/playwright','exit 0\n')
   executable(bin/'git',f'if [[ "$1 $2 $3" == "remote get-url origin" ]]; then echo https://github.com/lcstrindadebr/Promp-01-teste-.git; else exec /usr/bin/git "$@"; fi\n')
   executable(bin/'python3','if [[ "$1" == - ]]; then cat >/dev/null; exit 0; fi\nif [[ "$*" == *--check-runtime* ]]; then exit 0; fi\nexec /usr/bin/python3 "$@"\n')
   executable(bin/'systemctl',f'echo "$*" >> "{base}/service.log"\nexit 0\n');executable(bin/'nginx','exit 0\n')
   run=subprocess.run(['bash',str(launcher)],env={**env,'PATH':str(bin)+':'+env['PATH']},capture_output=True,text=True)
   self.assertEqual(run.returncode,0,run.stdout+run.stderr);self.assertEqual((app/'dist/index.html').read_text(),'NEW PANEL');self.assertIn('NEW ROBOT',(app/'vps/robot.py').read_text());self.assertTrue((app/'vps/chat_browser.py').exists());self.assertTrue((app/'vps/diagnose.py').exists());self.assertEqual((app/'.env').read_text(),original_env)
   self.assertIn('sb_publishable_custom',(app/'dist/supabase-config.js').read_text());self.assertNotIn('sb_secret',(app/'dist/supabase-config.js').read_text());self.assertTrue((units/'apoiarcred-robo.service').exists());self.assertIn('daemon-reload',(base/'service.log').read_text())
if __name__=='__main__':unittest.main()
