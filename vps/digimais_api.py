"""HTTP pilot: original n8n menus, waits and success predicates, isolated per flow."""
import asyncio,json,re,uuid,urllib.request,urllib.parse,urllib.error
from datetime import datetime,timezone


def money(value):
 if value is None:return None
 return float(value.replace('.','').replace(',','.')) if ',' in value else float(value)


def messages(raw):
 if isinstance(raw,list):return raw
 return raw['items'] if isinstance(raw.get('items'),list) else raw['data'] if isinstance(raw.get('data'),list) else [raw]


def parse_result(items,kind):
 texts=[m.get('contentText') or m.get('content') or m.get('text') or '' for m in items]
 texts=[t for t in texts if t]
 pattern=r'Valor Saldo|Saldo para quita|Total de parcelas' if kind=='saldo' else r'valor da parcela|Segue o valor da Parcela|Parcela:\s*\*?R\$'
 msg=next((t for t in texts if re.search(pattern,t,re.I)),None)
 result={'sucesso':bool(msg),'mensagemCompleta':msg,'todasMensagens':texts}
 fields={'valorSaldo':r'Valor Saldo:\s*\*?R\$\s*([\d.,]+)\*?','totalParcelas':r'Total de parcelas:\s*\*?(\d+)\*?'} if kind=='saldo' else {'valorParcela':r'Parcela:\s*\*?R\$\s*([\d.,]+)\*?'}
 for key,regex in fields.items():
  match=re.search(regex,msg or '',re.I);result[key]=match[1] if match else None
 return result


class ApiSession:
 def __init__(self,config):self.config=config;self.telemetry=None
 async def flow(self,job,kind):
  cfg=self.config;cookie='';session=str(uuid.uuid4());user=str(uuid.uuid4());items=[]
  async def call(path,body=None,limit=None):
   def send():
    query={'code':cfg['code']}
    if limit:query.update(limit=limit,offset=0)
    req=urllib.request.Request(cfg['baseUrl'].rstrip('/')+path+'?'+urllib.parse.urlencode(query),
     data=json.dumps(body).encode() if body is not None else None,
     headers={'Content-Type':'application/json','Accept':'application/json','Cookie':cookie})
    with urllib.request.urlopen(req,timeout=45) as res:
     return json.load(res),res.headers.get_all('Set-Cookie',[])
   return await asyncio.to_thread(send)
  async def message(text,option=None):
   await call('/messages',{'customData':{'options':[option],'buttons':None,'contextData':None} if option else None,
    'id':str(uuid.uuid4()),'contentText':text,'contentType':'text/plain','contentUrl':None,'messageType':'text',
    'sessionId':session,'direction':'I','sentAt':datetime.now(timezone.utc).isoformat(),
    'from':user,'fromName':job['nome'],'fromUid':job['telefone'],'to':cfg['accountUid']})
  def option(predicate):
   for m in items:
    for o in m.get('options') or m.get('buttons') or []:
     if predicate((o.get('title') or o.get('label') or '').lower()) and o.get('id'):
      return {'id':o['id'],'title':o.get('title') or o.get('label')}
   raise ValueError('Opção esperada não encontrada: '+kind)
  try:
   login,cookies=await call('/auth/login-public',{'userData':None,'userAccountUid':cfg['accountUid'],
    'userFullName':job['nome'],'userId':user,'userRole':'public','userName':job['telefone'],'userPhotoUrl':None,'userCustomData':{}})
   if not login.get('userId'):raise RuntimeError('Login sem usuário')
   user=login['userId'];cookie='; '.join(c.split(';')[0].strip() for c in cookies)
   sess,_=await call('/sessions',{'id':session,'fromId':user,'from':job['telefone'],'fromName':job['nome'],
    'to':cfg['accountUid'],'context':{'uid':job['telefone'],'name':job['nome'],'setCustomData':{}}})
   session=sess.get('id') or session
   await asyncio.sleep(8)
   raw,_=await call('/sessions/'+session+'/messages',limit=20);items=messages(raw)
   selected=option(lambda t:'cobran' in t);await message(selected['id'],selected)
   await asyncio.sleep(5);await message(job['cpf'])
   await asyncio.sleep(6)
   raw,_=await call('/sessions/'+session+'/messages',limit=20);items=messages(raw)
   selected=option((lambda t:'iquid' in t or 'saldo' in t) if kind=='saldo' else (lambda t:'parcela' in t or ('valor' in t and 'saldo' not in t)))
   await message(selected['id'],selected);await asyncio.sleep(8)
   raw,_=await call('/sessions/'+session+'/messages',limit=30);items=messages(raw)
   return parse_result(items,kind)
  except Exception as error:
   # Never log request URLs, cookies or identifiers. Keep commercial reply for owner's result.
   return {'sucesso':False,'erro':('HTTP '+str(error.code)) if isinstance(error,urllib.error.HTTPError) else ('Opção esperada não encontrada' if isinstance(error,ValueError) else 'Falha na comunicação com o atendimento'),
    'http_status':error.code if isinstance(error,urllib.error.HTTPError) else None,
    'todasMensagens':[m.get('contentText','') for m in items]}

 async def run(self,job,on_progress=None,on_checkpoint=None):
  if on_progress:await on_progress(5,'API experimental · saldo')
  first=await self.flow(job,'saldo')
  result={'resultado_saldo':first,'saldo_liquidacao':money(first.get('valorSaldo')),
   'total_parcelas':int(first['totalParcelas']) if first.get('totalParcelas') else None,
   'status':'processando','progress':50,'stage':'API experimental · parcela'}
  if on_checkpoint:await on_checkpoint(result.copy())
  if on_progress:await on_progress(50,'API experimental · parcela')
  second=await self.flow(job,'parcela');result['resultado_parcela']=second
  result['valor_parcela']=money(second.get('valorParcela'))
  result.update(status='concluida' if first['sucesso'] and second['sucesso'] else 'revisao',progress=100,stage='API experimental · finalizada')
  result['message']='Fluxos API executados. Confira os valores retornados.'
  texts=first.get('todasMensagens',[])+second.get('todasMensagens',[])
  referral=next((t for t in texts if 'assessoria de cobrança' in t.lower()),None)
  if referral:result['message']='Contrato em assessoria de cobrança. '+referral
  elif not(first['sucesso'] and second['sucesso']):result['message']='API sem retorno conclusivo. '+str(first.get('erro') or second.get('erro') or 'Valores não informados pelo atendimento.')
  return result
