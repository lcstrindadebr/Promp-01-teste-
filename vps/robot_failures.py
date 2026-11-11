"""Classify observed failures without writing exception text, URLs or credentials."""
import re
import socket
import ssl
from urllib.error import HTTPError, URLError

NETWORK_CODES = {
    'ERR_NAME_NOT_RESOLVED', 'ERR_DNS_TIMED_OUT', 'ERR_CONNECTION_REFUSED',
    'ERR_CONNECTION_RESET', 'ERR_CONNECTION_CLOSED', 'ERR_CONNECTION_TIMED_OUT',
    'ERR_TIMED_OUT', 'ERR_INTERNET_DISCONNECTED', 'ERR_ADDRESS_UNREACHABLE',
    'ERR_NETWORK_CHANGED', 'ERR_EMPTY_RESPONSE', 'ERR_HTTP2_PROTOCOL_ERROR',
    'ERR_SSL_PROTOCOL_ERROR', 'ERR_CERT_AUTHORITY_INVALID', 'ERR_CERT_DATE_INVALID',
    'ERR_CERT_COMMON_NAME_INVALID', 'ERR_PROXY_CONNECTION_FAILED',
    'ERR_TUNNEL_CONNECTION_FAILED', 'ERR_NO_SUPPORTED_PROXIES',
    'ERR_PROXY_AUTH_UNSUPPORTED', 'ERR_INVALID_AUTH_CREDENTIALS',
}
PERMANENT_NETWORK = {
    'ERR_CERT_AUTHORITY_INVALID', 'ERR_CERT_DATE_INVALID', 'ERR_CERT_COMMON_NAME_INVALID',
    'ERR_SSL_PROTOCOL_ERROR', 'ERR_NO_SUPPORTED_PROXIES',
    'ERR_PROXY_AUTH_UNSUPPORTED', 'ERR_INVALID_AUTH_CREDENTIALS',
}

def failure(category, code, transient=False):
    return {'categoria': category, 'codigo': code, 'transitorio': transient}

def diagnose(error, target='portal'):
    original = error
    if isinstance(error, URLError) and not isinstance(error, HTTPError):
        error = error.reason
    status = original.code if isinstance(original, HTTPError) else getattr(original, 'http_status', None)
    if isinstance(status, int) and 400 <= status <= 599:
        category = 'proxy_autenticacao' if status == 407 else (
            target if target != 'portal' or status not in (401, 403) else 'acesso_portal')
        return failure(category, f'HTTP_{status}', status in (408, 500, 502, 503, 504))
    if type(original).__name__ == 'ProxyConfigError':
        return failure('proxy_configuracao', 'PROXY_CONFIG_INVALIDA')
    marker = getattr(original, 'diagnostic_code', None)
    if marker == 'VERIFICACAO_HUMANA':
        return failure('acesso_portal', marker)
    if marker == 'FORMULARIO_INDISPONIVEL':
        return failure('portal', marker, True)
    message = str(error)
    code = next((item for item in re.findall(r'\bERR_[A-Z0-9_]+\b', message) if item in NETWORK_CODES), None)
    if code:
        category = target
        if 'PROXY' in code or 'TUNNEL' in code:category='proxy'
        if code=='ERR_PROXY_AUTH_UNSUPPORTED':category='proxy_autenticacao'
        if code=='ERR_INVALID_AUTH_CREDENTIALS':category='autenticacao_http'
        if code.startswith(('ERR_SSL','ERR_CERT')):category='tls'
        return failure(category, code, code not in PERMANENT_NETWORK)
    if isinstance(error, ssl.SSLError):
        return failure('tls', 'TLS_FALHOU')
    if isinstance(error, socket.gaierror):
        return failure(target, 'DNS_FALHOU', True)
    if isinstance(error, ConnectionError):
        return failure(target, 'CONEXAO_FALHOU', True)
    if type(error).__name__ == 'TimeoutError':
        return failure(target, 'TEMPO_EXCEDIDO', True)
    if 'Executable doesn' in message or 'playwright install' in message:
        return failure('navegador', 'CHROMIUM_AUSENTE')
    if re.search(r'target.*closed|browser.*closed|page.*closed|page crashed', message, re.I):
        return failure('navegador', 'NAVEGADOR_ENCERRADO', True)
    return failure('execucao', 'FALHA_NAO_CLASSIFICADA')

def label(diagnostic):
    return f"[{diagnostic['categoria']} / {diagnostic['codigo']}]"
