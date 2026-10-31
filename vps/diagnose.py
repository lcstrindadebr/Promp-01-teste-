"""No client data: test DNS, TLS, Chromium and the chat form as the worker user."""
import asyncio, os, socket, ssl, sys
from datetime import datetime,timezone
from urllib.parse import urlsplit
from chat_browser import BANK_URL,CHAT_HOST,open_bank,open_chat,describe_error,NavigationIssue

async def main():
    from playwright.async_api import async_playwright
    results={'utc':datetime.now(timezone.utc).isoformat(),'uid':os.getuid(),'checks':[]}
    def record(name,ok,detail):
        results['checks'].append({'check':name,'ok':ok,'detail':detail})
        print(('OK   ' if ok else 'FALHA')+' | '+name+' | '+detail,flush=True)
    for host in [urlsplit(BANK_URL).hostname,CHAT_HOST]:
        try:
            addrs=await asyncio.to_thread(socket.getaddrinfo,host,443,type=socket.SOCK_STREAM)
            record('DNS '+host,True,str(len(addrs))+' endereços encontrados')
        except Exception as e:record('DNS '+host,False,type(e).__name__);continue
        def tls():
            with socket.create_connection((host,443),timeout=12) as sock:
                with ssl.create_default_context().wrap_socket(sock,server_hostname=host) as conn:return conn.version()
        try:record('TLS '+host,True,await asyncio.to_thread(tls))
        except Exception as e:record('TLS '+host,False,type(e).__name__+'; conferir certificados/relógio/rede')
    # Proxy settings can explain transport differences; never print credentials or values.
    proxies=[name for name in ('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY') if os.environ.get(name) or os.environ.get(name.lower())]
    if proxies:record('Proxy no ambiente',True,', '.join(proxies)+' definido(s), valores ocultos')
    browser=None;context=None
    async with async_playwright() as pw:
        try:
            browser=await pw.chromium.launch(headless=True,args=['--disable-dev-shm-usage'])
            context=await browser.new_context(locale='pt-BR');record('Chromium',True,'iniciado')
            async def report(percent,label):print(f'ETAPA | {percent}% | {label}',flush=True)
            page=await open_bank(context,timeout=45000,report=report);record('Página do banco',True,'carregada; avisos tratados por clique')
            scope=await open_chat(context,page,timeout=45000);record('Widget',True,'formulário/menu identificado, sem enviar dados')
        except Exception as e:
            # No client data is entered in this diagnostic; the first browser error is safe to show.
            detail=str(e).split('Call log:')[0][:600] if not isinstance(e,NavigationIssue) else str(e)
            record('Navegação',False,describe_error(e)+' | '+detail)
        finally:
            if context:
                try:await context.close()
                except Exception:pass
            if browser:
                try:await browser.close()
                except Exception:pass
    print('RESULTADO: '+('PASSOU' if all(c['ok'] for c in results['checks']) else 'FALHOU — confira as etapas acima'),flush=True)
    return 0 if all(c['ok'] for c in results['checks']) else 1

if __name__=='__main__':sys.exit(asyncio.run(main()))
