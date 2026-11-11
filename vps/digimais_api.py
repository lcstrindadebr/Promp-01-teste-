"""HTTP pilot: original n8n menus, waits and success predicates, isolated per flow."""
import asyncio,json,re,uuid,urllib.request,urllib.parse,urllib.error
from robot_failures import diagnose
from datetime import datetime,timezone


class CpfFormatError(ValueError):
 pass


def format_cpf(value):
 """Keep storage identifiers unchanged; mask only the outbound chat message."""
 digits=re.sub(r'[.\-\s]','',str(value or ''))
 if not re.fullmatch(r'[0-9]{11}',digits):
  raise CpfFormatError('CPF deve conter 11 dígitos')
 return f'{digits[:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:]}'


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
  events=[];stage='autenticação'
  def mark(value,status='iniciada'):
   nonlocal stage
   stage=value;events.append({'horario':datetime.now(timezone.utc).isoformat(),'etapa':value,'status':status})
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
   mark('autenticação')
   login,cookies=await call('/auth/login-public',{'userData':None,'userAccountUid':cfg['accountUid'],
    'userFullName':job['nome'],'userId':user,'userRole':'public','userName':job['telefone'],'userPhotoUrl':None,'userCustomData':{}})
   if not login.get('userId'):raise RuntimeError('Login sem usuário')
   user=login['userId'];cookie='; '.join(c.split(';')[0].strip() for c in cookies)
   mark('criação da sessão')
   sess,_=await call('/sessions',{'id':session,'fromId':user,'from':job['telefone'],'fromName':job['nome'],
    'to':cfg['accountUid'],'context':{'uid':job['telefone'],'name':job['nome'],'setCustomData':{}}})
   session=sess.get('id') or session
   mark('menu de cobrança')
   await asyncio.sleep(8)
   raw,_=await call('/sessions/'+session+'/messages',limit=20);items=messages(raw)
   selected=option(lambda t:'cobran' in t);await message(selected['id'],selected)
   mark('envio do CPF')
   await asyncio.sleep(5);await message(format_cpf(job['cpf']))
   await asyncio.sleep(6)
   raw,_=await call('/sessions/'+session+'/messages',limit=20);items=messages(raw)
   mark('seleção de '+kind)
   selected=option((lambda t:'iquid' in t or 'saldo' in t) if kind=='saldo' else (lambda t:'parcela' in t or ('valor' in t and 'saldo' not in t)))
   await message(selected['id'],selected);mark('retorno de '+kind);await asyncio.sleep(8)
   raw,_=await call('/sessions/'+session+'/messages',limit=30);items=messages(raw)
   result=parse_result(items,kind)
   reason=None if result['sucesso'] else 'O atendimento não retornou uma mensagem de '+kind+' reconhecida.'
   if result['sucesso'] and result.get('valorSaldo' if kind=='saldo' else 'valorParcela') is None:
    reason='A mensagem de '+kind+' foi reconhecida, mas não contém valor numérico.'
   mark(stage,'interrompida' if reason else 'concluída')
   result.update(etapa=stage,motivo_interrupcao=reason,eventos=events)
   return result
  except Exception as error:
   # Persist only classified errors, never exception text, URLs or cookies.
   diagnostic=diagnose(error,'digimais_api')
   reason=('CPF inválido: informe 11 dígitos' if isinstance(error,CpfFormatError) else
    'Resposta JSON inválida do atendimento' if isinstance(error,json.JSONDecodeError) else
    'Opção esperada não encontrada no menu de '+kind if isinstance(error,ValueError) else
    'Autenticação retornou resposta sem usuário' if isinstance(error,RuntimeError) else diagnostic['codigo'])
   mark(stage,'interrompida')
   return {'sucesso':False,'etapa':stage,'motivo_interrupcao':reason,'eventos':events,'erro':('HTTP '+str(error.code)) if isinstance(error,urllib.error.HTTPError) else ('Opção esperada não encontrada' if isinstance(error,ValueError) else 'Falha na comunicação com o atendimento'),
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
  reasons=[kind+': '+r['etapa']+' — '+r['motivo_interrupcao'] for kind,r in [('Saldo',first),('Parcela',second)] if r.get('motivo_interrupcao')]
  if reasons:result['message']+=' Motivo da interrupção: '+'; '.join(reasons)
  return result
