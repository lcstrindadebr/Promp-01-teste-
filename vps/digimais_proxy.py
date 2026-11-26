"""Proxy privado do Digi+ (API do chat e robô com navegador); nunca registra credenciais.

Arquivo próprio (digimais-proxy.json), separado do proxy do ConsigX (tjba-proxy.json), com a mesma
validação. Sem arquivo, o Digi+ acessa direto. Arquivo inválido interrompe a consulta com aviso,
sem cair silenciosamente para o acesso direto.
"""
import json
import urllib.request
from pathlib import Path
from urllib.parse import quote, urlsplit
from tjba_proxy import CONFIG as TJBA_CONFIG, ProxyConfigError, validate

CONFIG = Path(__file__).resolve().parent.parent / 'digimais-proxy.json'
INVALID = 'Configuração privada do proxy Digi+ inválida ou inacessível; reconfigure no instalador.'

def load(path=None):
    path = CONFIG if path is None else Path(path)
    if not path.exists():
        return {}
    try:
        return validate(json.loads(path.read_text()))
    except Exception:
        raise ProxyConfigError(INVALID) from None

def launch_options(path=None):
    """Opções do Chromium (Playwright) do robô Digi+."""
    data = load(path)
    return {'proxy': data} if data else {}

_openers = {}
def opener(path=None):
    """urllib com o proxy do Digi+ (HTTPS por CONNECT, com usuário e senha quando houver)."""
    path = CONFIG if path is None else Path(path)
    try:
        stamp = path.stat().st_mtime_ns
    except FileNotFoundError:
        stamp = None
    key = (str(path), stamp)
    if key not in _openers:
        data = load(path)
        if not data:
            built = urllib.request.build_opener()
        else:
            url = urlsplit(data['server'])
            auth = ''
            if data.get('username'):
                auth = quote(data['username'], safe='') + ':' + quote(data['password'], safe='') + '@'
            proxy = f'{url.scheme}://{auth}{url.hostname}:{url.port}'
            built = urllib.request.build_opener(urllib.request.ProxyHandler({'http': proxy, 'https': proxy}))
        _openers.clear()
        _openers[key] = built
    return _openers[key]

def urlopen(req, timeout, path=None):
    """Abre uma requisição do Digi+: pelo proxy quando configurado; sem arquivo, urlopen direto, como antes."""
    if not load(path):
        return urllib.request.urlopen(req, timeout=timeout)
    return opener(path).open(req, timeout=timeout)

def describe(path=None):
    """Situação para logs e diagnóstico, sem credenciais."""
    try:
        data = load(path)
    except ProxyConfigError as error:
        return str(error)
    if not data:
        return 'Digi+ sem proxy (acesso direto).'
    url = urlsplit(data['server'])
    return f'Digi+ via proxy {url.hostname}:{url.port}' + (' com autenticação.' if data.get('username') else '.')

def save(data):
    import os, pwd, tempfile
    fd, name = tempfile.mkstemp(prefix='.digimais-proxy-', dir=CONFIG.parent)
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

if __name__ == '__main__':
    import getpass, os
    if os.geteuid() != 0:
        raise SystemExit('Execute pelo instalador como root.')
    print(describe())
    action = input('1) Configurar proxy Digi+  2) Usar o mesmo proxy do ConsigX (TJBA)  3) Remover proxy e usar acesso direto: ').strip()
    if action == '3':
        CONFIG.unlink(missing_ok=True)
        print('Proxy Digi+ removido.')
    elif action in ('1', '2'):
        try:
            if action == '2':
                if not TJBA_CONFIG.exists():
                    raise SystemExit('Não há proxy do ConsigX configurado. Use a opção 1.')
                data = validate(json.loads(TJBA_CONFIG.read_text()))
            else:
                data = validate({'server': input('Endereço (http://HOST:PORTA): ').strip(),
                                 'username': input('Usuário: ').strip(),
                                 'password': getpass.getpass('Senha do proxy: ')})
        except ValueError as e:
            raise SystemExit(str(e))
        save(data)
        print('Proxy Digi+ salvo em arquivo privado. ' + describe())
    else:
        raise SystemExit('Opção inválida; nada alterado.')
