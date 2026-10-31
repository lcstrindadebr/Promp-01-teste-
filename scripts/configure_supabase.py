"""Validate and persist server/public Supabase settings without exposing secrets."""
import argparse, base64, json, os, re, sys, tempfile
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

def role(key):
    try: return json.loads(base64.urlsafe_b64decode(key.split('.')[1]+'==='))['role']
    except Exception:return None

def validate(url, public, secret):
    if not re.fullmatch(r'https://[a-z0-9]{20}\.supabase\.co',url):
        raise ValueError('Use a URL HTTPS do projeto: https://REFERENCIA.supabase.co')
    if not (public.startswith('sb_publishable_') or role(public)=='anon'):
        raise ValueError('A chave do painel deve ser publishable ou anon, nunca secret/service_role.')
    if not (secret.startswith('sb_secret_') or role(secret)=='service_role'):
        raise ValueError('A chave do robô deve ser secret ou service_role.')
    for key in (public,secret):
        if not re.fullmatch(r'[A-Za-z0-9_.=-]+',key):raise ValueError('Formato de chave inválido.')

def probe(url, public, secret):
    # Both keys must belong to the same project, and the MVP tables must exist.
    checks=[('/auth/v1/settings',{'apikey':public}),
            ('/rest/v1/consulta_jobs?select=id,lote_id,user_id,nome,cpf,telefone,status,servico,saldo_liquidacao,total_parcelas,valor_parcela,resultado_saldo,resultado_parcela,message,created_at,consultado_em,progress,stage&limit=0',{'apikey':secret}),
            ('/rest/v1/consulta_lotes?select=id,user_id,nome,tipo,servico&limit=0',{'apikey':secret})]
    for path,headers in checks:
        if role(secret)=='service_role' and path.startswith('/rest/'):headers['Authorization']='Bearer '+secret
        with urlopen(Request(url+path,headers=headers),timeout=20) as response:response.read()

def atomic(path,content,mode):
    fd,name=tempfile.mkstemp(prefix='.config-',dir=path.parent)
    try:
        os.fchmod(fd,mode)
        with os.fdopen(fd,'w') as f:f.write(content)
        os.replace(name,path)
    finally:
        if os.path.exists(name):os.unlink(name)

def public_from_js(path):
    text=path.read_text();return json.loads(text[text.index('{'):text.rindex('}')+1])

def configure(app,url,public,secret,check=probe):
    validate(url,public,secret);check(url,public,secret)
    paths=[app/'.env',app/'supabase-public.json',app/'dist/supabase-config.js']
    previous={p:p.read_bytes() if p.exists() else None for p in paths}
    env=(app/'.env').read_text()
    # Retain unrelated runtime configuration and the selected robot mode.
    lines=[line for line in env.splitlines() if not line.startswith(('SUPABASE_URL=','SUPABASE_SERVICE_ROLE_KEY='))]
    env='\n'.join(lines+[f'SUPABASE_URL={url}',f'SUPABASE_SERVICE_ROLE_KEY={secret}'])+'\n'
    config={'url':url,'key':public}
    try:
        atomic(paths[0],env,0o600)
        atomic(paths[1],json.dumps(config)+'\n',0o600)
        atomic(paths[2],'window.SUPABASE_CONFIG = '+json.dumps(config)+';\n',0o644)
    except Exception:
        for p,data in previous.items():
            if data is None:p.unlink(missing_ok=True)
            else:atomic(p,data.decode(),0o644 if p.suffix=='.js' else 0o600)
        raise

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',required=True,type=Path)
    parser.add_argument('--check-runtime',action='store_true');parser.add_argument('--show-url',action='store_true');parser.add_argument('--capture-public',action='store_true');parser.add_argument('--render-only',action='store_true');args=parser.parse_args();app=args.app
    if args.check_runtime:
        env=dict(line.split('=',1) for line in (app/'.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
        config=json.loads((app/'supabase-public.json').read_text())
        if env['SUPABASE_URL']!=config['url']:raise ValueError('A URL do painel e do robô não coincide. Use Trocar conexão no menu.')
        validate(config['url'],config['key'],env['SUPABASE_SERVICE_ROLE_KEY'])
        probe(config['url'],config['key'],env['SUPABASE_SERVICE_ROLE_KEY']);return
    if args.show_url:
        config=json.loads((app/'supabase-public.json').read_text()) if (app/'supabase-public.json').exists() else public_from_js(app/'dist/supabase-config.js')
        print(config['url']);return
    if args.capture_public:
        atomic(app/'supabase-public.json',json.dumps(public_from_js(app/'dist/supabase-config.js'))+'\n',0o600);return
    if args.render_only:
        config=json.loads((app/'supabase-public.json').read_text())
        # Fail closed if the saved public key has an unexpected privileged role.
        if not (config['key'].startswith('sb_publishable_') or role(config['key'])=='anon'):raise ValueError('Configuração pública inválida.')
        atomic(app/'dist/supabase-config.js','window.SUPABASE_CONFIG = '+json.dumps(config)+';\n',0o644);return
    values=[sys.stdin.readline().strip() for _ in range(3)]
    configure(app,*values)

if __name__=='__main__':
    try:main()
    except (HTTPError,URLError,TimeoutError):print('Não foi possível validar URL/chaves ou tabelas do MVP no Supabase. Nenhuma configuração foi alterada.',file=sys.stderr);sys.exit(1)
    except Exception as e:print('Falha ao configurar Supabase: '+str(e) if isinstance(e,ValueError) else 'Falha ao salvar a configuração. Confira permissões e espaço em disco.',file=sys.stderr);sys.exit(1)
