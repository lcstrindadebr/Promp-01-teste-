"""TJBA runtime diagnostic: no credentials, no CPF, no authentication attempts."""
import asyncio,socket,ssl,sys
from tjba_proxy import launch_options
from tjba import BASE,CHROMIUM_ARGS,failure_details
async def main():
 failed=False;browser=None;page=None
 def record(name,ok,detail):
  nonlocal failed
  if not ok:failed=True
  print(('OK   ' if ok else 'FALHA')+' | '+name+' | '+detail,flush=True)
 try: options=launch_options()
 except ValueError as e:
  record('Proxy TJBA',False,str(e));return 1
 print('ROTA | '+('proxy privado TJBA; TLS validado pelo navegador' if options else 'acesso direto'),flush=True)
 if not options:
  host='govbahia.consigx.com.br'
  try:
   addresses=await asyncio.to_thread(socket.getaddrinfo,host,443,type=socket.SOCK_STREAM);record('DNS ConsigX',True,str(len(addresses))+' endereços')
  except Exception as e:record('DNS ConsigX',False,type(e).__name__)
  def tls():
   with socket.create_connection((host,443),timeout=10) as sock:
    with ssl.create_default_context().wrap_socket(sock,server_hostname=host) as conn:return conn.version()
  try:record('TLS ConsigX',True,await asyncio.to_thread(tls))
  except Exception as e:record('TLS ConsigX',False,type(e).__name__)
 try:
  from playwright.async_api import async_playwright
  async with async_playwright() as pw:
   try:
    browser=await pw.chromium.launch(headless=True,args=list(CHROMIUM_ARGS),**options);record('Chromium',True,'iniciado')
    context=await browser.new_context(locale='pt-BR');page=await context.new_page()
    response=await page.goto(BASE+'/',wait_until='domcontentloaded',timeout=30000)
    record('Página pública',bool(response) and response.status<400,'HTTP '+str(response.status if response else 'indisponível'))
    await page.locator('#txtLogin').wait_for(state='visible',timeout=10000)
    await page.locator('#txtSenha').wait_for(state='visible',timeout=10000)
    record('Formulário de login',True,'campos identificados; nenhuma credencial enviada')
   finally:
    if browser:await browser.close()
 except Exception as e:
  d=failure_details(e,page);record('Ambiente/navegação',False,d['tipo']+' | '+d['codigo'])
 print('RESULTADO: '+('FALHOU' if failed else 'PASSOU')+' — diagnóstico sem login e sem CPF',flush=True)
 return 1 if failed else 0
if __name__=='__main__':sys.exit(asyncio.run(main()))
