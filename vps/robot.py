"""Digi+ UI workflow with real step progress and explicit result classification."""
import asyncio, inspect, re, time
from decimal import Decimal
from chat_browser import CHROMIUM_ARGS, CHAT_URL, NavigationIssue, describe_error, open_direct_chat, check_access
class RobotError(Exception):pass

def format_cpf(value):
 digits=re.sub(r'\D','',str(value))
 if len(digits)!=11:raise RobotError('CPF precisa conter 11 dígitos.')
 return f'{digits[:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:]}'

def normalize(text):return re.sub(r'\s+',' ',text).strip()

def parse_response(text, *, ended=False, cpf_sent=False, kind="saldo"):
 text=normalize(text);lower=text.casefold()
 # Technical failures must never be classified as absence of a client.
 if 'encerrado por falta de interação' in lower:
  return {'status':'erro','message':'Sessão encerrada por falta de interação.'}
 if re.search(r'\b(?:erro|falha|indisponível)\b|tente novamente|não foi possível',lower):
  return {'status':'revisao','message':'O chat informou uma falha; revisar a consulta.'}
 if re.search(r'não foi informado um cpf válido|cpf inválido',lower):
  return {'status':'revisao','message':'O banco recusou o CPF como inválido. Confira os dados antes de nova consulta.'}
 if 'documento não foi localizado para esse produto' in lower:
  return {'status':'nao_cliente','message':'Documento não localizado para esse produto no chat.'}
 if kind=='parcela':
  match=re.search(r'valor\s+(?:da?\s+)?parcela\s*[:\-]?\s*R\$\s*((?:\d{1,3}(?:\.\d{3})+|\d+),\d{1,2}|\d+(?:\.\d{1,2})?)(?!\d|[.,]\d)',text,re.I)
  if match:
   amount=match.group(1)
   value=Decimal(amount.replace('.','').replace(',','.') if ',' in amount else amount)
   return {'status':'concluida','valor_parcela':float(value),'message':'Valor da parcela informado pelo chat.'}
  if ended and cpf_sent:return {'status':'revisao','message':'Chat encerrado sem valor de parcela reconhecido.'}
  return None
 saldo=re.search(r'(?:valor\s+(?:do\s+)?saldo|saldo\s*(?:para\s*)?(?:de\s*)?(?:quitação|liquidação)(?:\s*(?:hoje|atual))?)\s*[:\-]?\s*R\$\s*((?:\d{1,3}(?:\.\d{3})+|\d+),\d{2}|\d+\.\d{2})(?!\d|[.,]\d)',text,re.I)
 parcelas=re.search(r'(?:total|quantidade|número)\s*(?:de\s*)?parcelas\s*[:\-]?\s*(\d+)',text,re.I)
 if saldo and parcelas:
  amount=saldo.group(1)
  value=Decimal(amount.replace('.','').replace(',','.') if ',' in amount else amount);n=int(parcelas.group(1))
  if value<0 or not 0<=n<=1000:raise RobotError('Resposta fora dos limites esperados; revisar manualmente.')
  return {'status':'concluida','saldo_liquidacao':float(value),'total_parcelas':n,'message':'Saldo informado pelo chat na data desta consulta.'}
 if ended and cpf_sent:
  if saldo or parcelas:
   return {'status':'revisao','message':'Atendimento encerrado com resposta parcial de saldo/parcelas.'}
  return {'status':'revisao','message':'Chat encerrado sem resposta conclusiva após o CPF. Não é possível afirmar que não é cliente.'}
 return None

INPUTS='input:not([type="hidden"]):not([type="file"]):not([type="checkbox"])'
CONSIGNADO=re.compile(r'^Empr[ée]stimo\s+consignado$',re.I)

async def wait_menu(chat, name, timeout, *, registration=False):
 """Observe the actual state instead of waiting blindly on an absent button."""
 deadline=time.monotonic()+timeout/1000
 button=chat.get_by_role('button',name=name)
 while time.monotonic()<deadline:
  text=normalize(await chat.locator('body').inner_text(timeout=3000))
  check_access(text)
  if re.search(r'campo obrigatório|telefone inválido|nome obrigatório',text,re.I):
   raise RobotError('O formulário recusou nome/telefone; a consulta ainda não começou.')
  if re.search(r'encerrado|sessão de chat acabou',text,re.I):
   raise RobotError('O chat encerrou a sessão antes da consulta. Nenhum CPF foi reenviado.')
  if re.search(r'indisponível|tente novamente|não foi possível',text,re.I):
   raise RobotError('O chat informou indisponibilidade antes da consulta.')
  if await button.is_visible():return button
  await asyncio.sleep(.2)
 if registration:
  raise RobotError('Nome/telefone enviados, mas o banco não disponibilizou o menu no prazo. Nenhum CPF foi enviado.')
 raise RobotError('O banco não disponibilizou a próxima opção do atendimento no prazo.')

async def start_chat(chat, client, timeout):
 if await chat.get_by_role('button',name=CONSIGNADO).is_visible():return
 fields=chat.locator(INPUTS)
 # The live widget validates on keyboard events; fill alone leaves phone "required".
 for index,value in enumerate((client['nome'],re.sub(r'\D','',client['telefone']))):
  field=fields.nth(index)
  await field.fill('')
  await field.press_sequentially(value,delay=20,timeout=10000)
  await field.press('Tab')
 await chat.get_by_role('button',name='Enviar',exact=True).click(timeout=5000)
 await wait_menu(chat,CONSIGNADO,timeout,registration=True)

async def run_once(client,timeout=60000,on_progress=None,kind="saldo"):
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
   browser=await pw.chromium.launch(headless=True,args=list(CHROMIUM_ARGS))
   context=await browser.new_context(locale='pt-BR')
   chat=await open_direct_chat(context,timeout=timeout,report=emit)
   await emit(30,'Preencher nome e telefone')
   await start_chat(chat,client,timeout)
   await emit(40,'Selecionar empréstimo consignado')
   await chat.get_by_role('button',name=CONSIGNADO).click(timeout=5000)
   await emit(50,'Selecionar boleto')
   boleto=await wait_menu(chat,re.compile(r'^Boleto$',re.I),timeout)
   await boleto.click(timeout=5000)
   await emit(60,'Aguardar solicitação do CPF')
   # Match normalized text across nested elements/nonbreaking spaces.
   await chat.wait_for_function("() => /para te localizar.*cpf/i.test(document.body.innerText.replace(/\\s+/g,' '))",timeout=timeout)
   field=chat.get_by_placeholder('Digitar...',exact=True)
   await field.fill(format_cpf(client['cpf']))
   # Observed actual send button; Enter is no longer assumed to submit.
   await chat.locator('button.send[type="submit"]').click()
   await emit(70,'CPF enviado; aguardando resposta')
   selected_saldo=False;end_seen=None;history_opened=False;deadline=time.monotonic()+timeout/1000
   while time.monotonic()<deadline:
    text=await chat.locator('body').inner_text()
    if re.search(r'verifique.{0,30}human|captcha|checking your browser|access denied',text,re.I):
     return await finish({'status':'revisao','message':'Verificação adicional no site; intervenção humana necessária.'})
    ended=bool(re.search(r'a sessão de chat acabou|esse atendimento foi encerrado',normalize(text),re.I)) or await chat.get_by_role('button',name='Novo Chat',exact=True).count()>0
    # Let any last message settle after the close event, without resending CPF.
    if ended:
     end_seen=end_seen or time.monotonic()
     history=chat.get_by_role('button',name='Visualizar Chat',exact=True)
     if not history_opened and await history.is_visible():
      await history.click(timeout=5000);history_opened=True
      continue # Read the newly visible final message before deciding.
    result=parse_response(text,ended=ended and time.monotonic()-(end_seen or 0)>=5,cpf_sent=True,kind=kind)
    if result:return await finish(result)
    button=chat.get_by_role('button',name=re.compile(r'^Valor\s+de\s+Parcela$' if kind=='parcela' else r'^Saldo\s+Liquidação$',re.I))
    if not selected_saldo and await button.is_visible():
     await button.click();selected_saldo=True;deadline=time.monotonic()+timeout/1000
     await emit(85,'Valor de parcela solicitado; aguardando resposta' if kind=='parcela' else 'Saldo de liquidação solicitado; aguardando valores')
    await asyncio.sleep(.5)
   raise RobotError('Não houve resposta final reconhecida após o envio. Não é possível classificar como não cliente.')
  except PlaywrightTimeout:
   return {'status':'erro','message':f'Tempo excedido: {stage} ({progress}%). Nenhum resultado conclusivo.','progress':progress,'stage':stage}
  except (RobotError,NavigationIssue) as e:return {'status':'revisao','message':str(e),'progress':progress,'stage':stage}
  except Exception as e:
   return {'status':'erro','message':f'Falha na etapa {stage}: {describe_error(e)}.','progress':progress,'stage':stage}
  finally:
   if context:
    try:await context.close()
    except Exception:pass
   if browser:
    try:await browser.close()
    except Exception:pass



async def run(client,timeout=60000,on_progress=None,on_checkpoint=None):
 """Two independent sessions, one job. Persist the balance before the second call."""
 async def progress(percent,label):
  if on_progress:
   result=on_progress(percent,label)
   if inspect.isawaitable(result):await result
 async def first_progress(percent,label):await progress(percent//2,'1/2 Saldo: '+label)
 async def second_progress(percent,label):await progress(50+percent//2,'2/2 Parcela: '+label)
 first=await run_once(client,timeout,first_progress,kind='saldo')
 combined={k:v for k,v in first.items() if k not in ('progress','stage')}
 combined.update(resultado_saldo=first,progress=first.get('progress',0)//2,stage='1/2 Saldo: '+first.get('stage',''))
 if first['status']!='concluida':
  # Do not start another session after an inconclusive or blocked first call.
  if first['status']=='nao_cliente':combined.update(progress=100,stage='Não é cliente')
  return combined
 combined.update(status='processando',progress=50,stage='Saldo salvo; iniciando consulta da parcela')
 if on_checkpoint:
  try:
   result=on_checkpoint(combined.copy())
   if inspect.isawaitable(result):await result
  except Exception:
   combined.update(status='revisao',message='Saldo obtido; não foi possível confirmar o salvamento parcial. A segunda consulta não foi iniciada.')
   return combined
 try:
  second=await run_once(client,timeout,second_progress,kind='parcela')
 except Exception:
  second={'status':'erro','progress':0,'stage':'Iniciar consulta da parcela','message':'Falha interna na segunda consulta; saldo preservado.'}
 combined.update(resultado_parcela=second,progress=50+second.get('progress',0)//2,stage='2/2 Parcela: '+second.get('stage',''))
 if second['status']=='concluida':
  combined.update(valor_parcela=second['valor_parcela'],status='concluida',progress=100,stage='Saldo e parcela consultados',message='Saldo, total de parcelas e valor da parcela informados pelo chat.')
 else:
  combined.update(status='revisao',message='Saldo preservado. Consulta da parcela: '+second.get('message','sem resultado conclusivo.'))
 return combined
