"""Digi+ UI workflow with real step progress and explicit result classification."""
import asyncio, inspect, re, time
from decimal import Decimal
BANK_URL='https://www.bancodigimais.com.br/'
class RobotError(Exception):pass

def format_cpf(value):
 digits=re.sub(r'\D','',str(value))
 if len(digits)!=11:raise RobotError('CPF precisa conter 11 dígitos.')
 return f'{digits[:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:]}'

def normalize(text):return re.sub(r'\s+',' ',text).strip()

def parse_response(text, *, ended=False, cpf_sent=False):
 text=normalize(text);lower=text.casefold()
 # Technical failures must never be classified as absence of a client.
 if 'encerrado por falta de interação' in lower:
  return {'status':'erro','message':'Sessão encerrada por falta de interação.'}
 if re.search(r'\b(?:erro|falha|indisponível)\b|tente novamente|não foi possível',lower):
  return {'status':'revisao','message':'O chat informou uma falha; revisar a consulta.'}
 if 'documento não foi localizado para esse produto' in lower:
  return {'status':'nao_cliente','message':'Documento não localizado para esse produto no chat.'}
 saldo=re.search(r'saldo\s*(?:para\s*)?(?:de\s*)?(?:quitação|liquidação)(?:\s*(?:hoje|atual))?\s*[:\-]?\s*R\$\s*([\d.]+,\d{2})',text,re.I)
 parcelas=re.search(r'(?:total|quantidade|número)\s*(?:de\s*)?parcelas\s*[:\-]?\s*(\d+)',text,re.I)
 if saldo and parcelas:
  value=Decimal(saldo.group(1).replace('.','').replace(',','.'));n=int(parcelas.group(1))
  if value<0 or not 0<=n<=1000:raise RobotError('Resposta fora dos limites esperados; revisar manualmente.')
  return {'status':'concluida','saldo_liquidacao':float(value),'total_parcelas':n,'message':'Saldo informado pelo chat na data desta consulta.'}
 if ended and cpf_sent:
  if saldo or parcelas:
   return {'status':'revisao','message':'Atendimento encerrado com resposta parcial de saldo/parcelas.'}
  return {'status':'revisao','message':'Chat encerrado sem resposta conclusiva após o CPF. Não é possível afirmar que não é cliente.'}
 return None

async def run(client,timeout=60000,on_progress=None):
 from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeout
 progress=0;stage='Iniciar navegador';browser=None;context=None
 async def emit(percent,label):
  nonlocal progress,stage
  progress=percent;stage=label
  if on_progress:
   result=on_progress(percent,label)
   if inspect.isawaitable(result):await result
 async def finish(result):
  if result['status'] in ('concluida','nao_cliente'):await emit(100,'Concluída' if result['status']=='concluida' else 'Não é cliente')
  result.update(progress=progress,stage=stage);return result
 async with async_playwright() as pw:
  try:
   await emit(5,'Iniciar navegador')
   browser=await pw.chromium.launch(headless=True,args=['--disable-dev-shm-usage'])
   context=await browser.new_context(locale='pt-BR')
   page=await context.new_page();page.set_default_timeout(timeout)
   await emit(10,'Abrir site do banco')
   response=await page.goto(BANK_URL,wait_until='domcontentloaded')
   if response and response.status>=400:raise RobotError('O site do banco retornou erro HTTP. Nenhuma consulta concluída.')
   close=page.get_by_role('button',name='Fechar',exact=True)
   async def close_notice(locator):await locator.click()
   await page.add_locator_handler(close,close_notice)
   await emit(20,'Abrir widget do chat')
   async with context.expect_page(timeout=timeout) as opened:
    await page.locator('button.v-chat-button').click()
   chat=await opened.value;chat.set_default_timeout(timeout)
   await chat.wait_for_load_state('domcontentloaded')
   await emit(30,'Preencher nome e telefone')
   await chat.locator('input:not([type="hidden"]):not([type="file"])').nth(0).fill(client['nome'])
   await chat.locator('input:not([type="hidden"]):not([type="file"])').nth(1).fill(client['telefone'])
   await chat.get_by_role('button',name='Enviar',exact=True).click()
   await emit(40,'Selecionar empréstimo consignado')
   await chat.get_by_role('button',name=re.compile(r'^Empréstimo consignado$',re.I)).click()
   await emit(50,'Selecionar boleto')
   await chat.get_by_role('button',name='Boleto',exact=True).click()
   await emit(60,'Aguardar solicitação do CPF')
   # Match normalized text across nested elements/nonbreaking spaces.
   await chat.wait_for_function("() => /para te localizar.*cpf/i.test(document.body.innerText.replace(/\\s+/g,' '))",timeout=timeout)
   field=chat.get_by_placeholder('Digitar...',exact=True)
   await field.fill(format_cpf(client['cpf']))
   # Observed actual send button; Enter is no longer assumed to submit.
   await chat.locator('button.send[type="submit"]').click()
   await emit(70,'CPF enviado; aguardando resposta')
   selected_saldo=False;end_seen=None;deadline=time.monotonic()+timeout/1000
   while time.monotonic()<deadline:
    text=await chat.locator('body').inner_text()
    if re.search(r'verifique.{0,30}human|captcha|checking your browser|access denied',text,re.I):
     return await finish({'status':'revisao','message':'Verificação adicional no site; intervenção humana necessária.'})
    ended=bool(re.search(r'a sessão de chat acabou|esse atendimento foi encerrado',normalize(text),re.I)) or await chat.get_by_role('button',name='Novo Chat',exact=True).count()>0
    # Let any last message settle after the close event, without resending CPF.
    if ended:
     end_seen=end_seen or time.monotonic()
    result=parse_response(text,ended=ended and time.monotonic()-(end_seen or 0)>=2,cpf_sent=True)
    if result:return await finish(result)
    button=chat.get_by_role('button',name=re.compile(r'^Saldo\s+Liquidação$',re.I))
    if not selected_saldo and await button.is_visible():
     await button.click();selected_saldo=True;deadline=time.monotonic()+timeout/1000
     await emit(85,'Saldo de liquidação solicitado; aguardando valores')
    await asyncio.sleep(.5)
   raise RobotError('Não houve resposta final reconhecida após o envio. Não é possível classificar como não cliente.')
  except PlaywrightTimeout:
   return {'status':'erro','message':f'Tempo excedido: {stage} ({progress}%). Nenhum resultado conclusivo.','progress':progress,'stage':stage}
  except RobotError as e:return {'status':'revisao','message':str(e),'progress':progress,'stage':stage}
  except Exception as e:
   return {'status':'erro','message':f'Falha na etapa {stage}: {type(e).__name__}.','progress':progress,'stage':stage}
  finally:
   if context:await context.close()
   if browser:await browser.close()
