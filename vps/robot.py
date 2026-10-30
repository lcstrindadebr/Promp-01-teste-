"""Digi+ saldo de liquidação. UI flow based on observed chat; requires live homologation."""
import re
from decimal import Decimal
URL='https://widget.voltdigital.com.br/br/14603de1a63fa6c1331d69c278d6d32f2bbd825b28c5e4053e6418b24c7e761f/chat'
class RobotError(Exception): pass

def parse_response(text):
 lower=text.casefold()
 if 'documento não foi localizado para esse produto' in lower:
  return {'status':'nao_localizado','message':'Documento não localizado para esse produto. Não equivale a saldo zero.'}
 saldo=re.search(r'saldo\s*(?:para\s*)?(?:de\s*)?(?:quitação|liquidação)(?:\s*(?:hoje|atual))?\s*[:\-]?\s*R\$\s*([\d.]+,\d{2})',text,re.I)
 parcelas=re.search(r'(?:total|quantidade|número)\s*(?:de\s*)?parcelas\s*[:\-]?\s*(\d+)',text,re.I)
 if saldo and parcelas:
  value=Decimal(saldo.group(1).replace('.','').replace(',','.'));n=int(parcelas.group(1))
  if value<0 or not 0<=n<=1000:raise RobotError('Resposta fora dos limites esperados; revisar manualmente.')
  return {'status':'concluida','saldo_liquidacao':float(value),'total_parcelas':n,'message':'Saldo informado pelo chat; verificar a data da consulta.'}
 if 'encerrado por falta de interação' in lower:return {'status':'erro','message':'Sessão encerrada por falta de interação.'}
 return None

async def run(client,timeout=45000):
 from playwright.async_api import async_playwright,TimeoutError as PlaywrightTimeout
 async with async_playwright() as pw:
  browser=await pw.chromium.launch(headless=True,args=['--disable-dev-shm-usage'])
  context=await browser.new_context(locale='pt-BR') # isolated cookies/localStorage per client
  page=await context.new_page();page.set_default_timeout(timeout)
  try:
   await page.goto(URL,wait_until='domcontentloaded')
   # Initial form observed: two text fields (name and phone) followed by Enviar.
   fields=page.get_by_role('textbox')
   await fields.nth(0).fill(client['nome'])
   await fields.nth(1).fill(client['telefone'])
   await page.get_by_role('button',name='Enviar',exact=True).click()
   await page.get_by_role('button',name='Empréstimo consignado',exact=True).click()
   await page.get_by_role('button',name='Boleto',exact=True).click()
   await page.get_by_text('Para te localizar aqui no sistema',exact=False).wait_for()
   field=page.get_by_placeholder('Digitar...',exact=True)
   await field.fill(client['cpf']);await field.press('Enter')
   # Wait for a known result or the next menu. Never click Atendente automatically.
   import time,asyncio
   deadline=time.monotonic()+timeout/1000
   while time.monotonic()<deadline:
    text=await page.locator('body').inner_text()
    if re.search(r'verifique.{0,30}human|captcha|checking your browser|access denied',text,re.I):
     return {'status':'revisao','message':'Verificação adicional no site; intervenção humana necessária.'}
    result=parse_response(text)
    if result and result['status']!='concluida':return result
    button=page.get_by_role('button',name='Saldo Liquidação',exact=True)
    if await button.is_visible():
     await button.click();break
    await asyncio.sleep(.5)
   else:raise RobotError('CPF enviado, mas menu ou resposta não reconhecida.')
   deadline=time.monotonic()+timeout/1000
   while time.monotonic()<deadline:
    result=parse_response(await page.locator('body').inner_text())
    if result:return result
    await asyncio.sleep(.5)
   raise RobotError('Saldo e total de parcelas não reconhecidos na resposta.')
  except PlaywrightTimeout:
   return {'status':'erro','message':'Tempo excedido em uma etapa do chat. Revisar antes de tentar novamente.'}
  except RobotError as e:return {'status':'revisao','message':str(e)}
  finally:await context.close();await browser.close()
