"""Private TJBA-only proxy configuration; never log credentials."""
import json
from pathlib import Path
from urllib.parse import urlsplit

CONFIG = Path(__file__).resolve().parent.parent / 'tjba-proxy.json'

def validate(data):
    if not isinstance(data, dict):
        raise ValueError('Configuração de proxy inválida.')
    server = data.get('server', '')
    try:
        url = urlsplit(server)
        valid = (url.scheme in ('http', 'https') and url.hostname and url.port
                 and not url.username and not url.password and url.path in ('', '/')
                 and not url.query and not url.fragment)
    except (ValueError, TypeError):
        valid = False
    if not valid:
        raise ValueError('Use http://HOST:PORTA ou https://HOST:PORTA, sem credenciais na URL.')
    for key in ('username', 'password'):
        if not isinstance(data.get(key, ''), str):
            raise ValueError('Credenciais do proxy inválidas.')
    if bool(data.get('username')) != bool(data.get('password')):
        raise ValueError('Informe usuário e senha juntos.')
    return {key: data[key] for key in ('server', 'username', 'password') if data.get(key)}

def launch_options(path=None):
    path = CONFIG if path is None else Path(path)
    if not path.exists():
        return {}
    try:
        return {'proxy': validate(json.loads(path.read_text()))}
    except Exception:
        raise ValueError('Configuração privada do proxy TJBA inválida ou inacessível; reconfigure no instalador.') from None

if __name__ == '__main__':
    import getpass, os, pwd, tempfile
    if os.geteuid() != 0:
        raise SystemExit('Execute pelo instalador como root.')
    action = input('1) Configurar proxy TJBA  2) Remover proxy e usar acesso direto: ').strip()
    if action == '2':
        CONFIG.unlink(missing_ok=True)
        print('Proxy removido.')
    elif action == '1':
        try:
            data = validate({'server': input('Endereço (http://HOST:PORTA): ').strip(),
                             'username': input('Usuário: ').strip(),
                             'password': getpass.getpass('Senha do proxy: ')})
        except ValueError as e:
            raise SystemExit(str(e))
        fd, name = tempfile.mkstemp(prefix='.tjba-proxy-', dir=CONFIG.parent)
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(data, stream)
                stream.flush()
                os.fsync(stream.fileno())
                os.fchown(stream.fileno(), 0, pwd.getpwnam('apoiarcred').pw_gid)
                os.fchmod(stream.fileno(), 0o640)
            os.replace(name, CONFIG)
        finally:
            if os.path.exists(name): os.unlink(name)
        print('Proxy TJBA salvo em arquivo privado.')
    else:
        raise SystemExit('Opção inválida; nada alterado.')
