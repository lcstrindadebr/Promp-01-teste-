"""HTTP pilot: original n8n menus, waits and success predicates, isolated per flow."""
import asyncio,json,re,uuid,urllib.request,urllib.parse,urllib.error
from robot_failures import diagnose
from datetime import datetime,timezone
from http.cookies import SimpleCookie
import unicodedata


class CpfFormatError(ValueError):
 pass


def format_cpf(value):
 """Keep storage identifiers unchanged; mask only the outbound chat message."""
 digits=re.sub(r'[.\-\s]','',str(value or ''))
 if not re.fullmatch(r'[0-9]{11}',digits):
  raise CpfFormatError('CPF deve conter 11 dígitos')
 return f'{digits[:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:]}'


class FlowStopped(Exception):
 def __init__(self,code,reason):
  self.code=code;self.reason=reason
  super().__init__(reason)


BUSINESS_RESULTS={
 'DOCUMENTO_NAO_LOCALIZADO':('nao_cliente','Não é cliente'),
 'CONTRATO_EM_ASSESSORIA':('ja_vendeu','Já vendeu'),
}


def assert_service_available(items,after_cpf=False):
 for item in items:
  if item.get('direction')=='I':continue
  text=item.get('contentText') or item.get('content') or item.get('text') or ''
  text=''.join(c for c in unicodedata.normalize('NFKD',text.lower()) if not unicodedata.combining(c))
  if re.search(r'fora do horario(?: de atendimento)?|fora (?:do nosso|de nosso) horario',text):
   raise FlowStopped('FORA_HORARIO_ATENDIMENTO','Atendimento DigiMais indisponível: fora do horário de atendimento informado pelo provedor.')
  if not after_cpf:continue
  text=' '.join(re.sub(r'[*_]', '', text).split())
  if 'nao consegui localizar o seu documento' in text:
   raise FlowStopped('DOCUMENTO_NAO_LOCALIZADO','O atendimento Digi+ informou que não localizou o documento.')
  if re.search(r'(?:seu|o) contrato esta sob (?:a )?responsabilidade d[ae] (?:nossa |uma )?assessoria de cobranca',text):
   raise FlowStopped('CONTRATO_EM_ASSESSORIA','O atendimento Digi+ informou que o contrato está sob responsabilidade de uma assessoria de cobrança.')



def money(value):
 if value is None:return None
 return float(value.replace('.','').replace(',','.')) if ',' in value else float(value)


def messages(raw):
 if isinstance(raw,list):return [item for item in raw if isinstance(item,dict)]
 if not isinstance(raw,dict):return []
 for key in ('items','data','body'):
  if isinstance(raw.get(key),(list,dict)):return messages(raw[key])
 return [raw]


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
  async def request_once(path,body=None,limit=None):
   nonlocal cookie
   def send():
    query={'code':cfg['code']}
    if limit:query.update(limit=limit,offset=0)
    req=urllib.request.Request(cfg['baseUrl'].rstrip('/')+path+'?'+urllib.parse.urlencode(query),
     data=json.dumps(body).encode() if body is not None else None,
     headers={'Content-Type':'application/json','Accept':'application/json','Cookie':cookie})
    with urllib.request.urlopen(req,timeout=45) as res:
     return json.load(res),res.headers.get_all('Set-Cookie',[])
   data,set_cookies=await asyncio.to_thread(send)
   jar=SimpleCookie();jar.load(cookie)
   for header in set_cookies:
    incoming=SimpleCookie();incoming.load(header)
    for name,morsel in incoming.items():
     if morsel['max-age']=='0':
      if name in jar:del jar[name]
     else:jar[name]=morsel.value
   cookie='; '.join(m.OutputString() for m in jar.values())
   return data,set_cookies
  async def call(path,body=None,limit=None,validate=None):
   for attempt,delay in enumerate((0,4,2),1):
    if delay:
     events.append({'horario':datetime.now(timezone.utc).isoformat(),'etapa':stage,'status':'nova tentativa','tentativa':attempt,'espera_segundos':delay})
     await asyncio.sleep(delay)
    try:
     data,cookies=await request_once(path,body,limit)
     if validate:validate(data)
     return data,cookies
    except (FlowStopped,CpfFormatError):
     raise
    except Exception:
     if attempt==3:
      raise FlowStopped('TENTATIVAS_ESGOTADAS','Falha na etapa '+stage+' após 3 tentativas da mesma chamada.')
  def validate_login(data):
   if not isinstance(data,dict) or not data.get('userId'):
    raise ValueError('Login sem usuário')
  def validate_menu(raw,predicate):
   nonlocal items
   items=messages(raw)
   assert_service_available(items,after_cpf=stage!='menu de cobrança')
   option(predicate)
  def validate_result(raw):
   nonlocal items
   items=messages(raw)
   assert_service_available(items,after_cpf=True)
   result=parse_result(items,kind)
   if not result['sucesso'] or result.get('valorSaldo' if kind=='saldo' else 'valorParcela') is None:
    raise ValueError('Resultado ainda indisponível')
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
    'userFullName':job['nome'],'userId':user,'userRole':'public','userName':job['telefone'],'userPhotoUrl':None,'userCustomData':{}},validate=validate_login)
   if not login.get('userId'):raise RuntimeError('Login sem usuário')
   user=login['userId']
   mark('criação da sessão')
   sess,_=await call('/sessions',{'id':session,'fromId':user,'from':job['telefone'],'fromName':job['nome'],
    'to':cfg['accountUid'],'context':{'uid':job['telefone'],'name':job['nome'],'setCustomData':{}}})
   session=sess.get('id') or session
   mark('menu de cobrança')
   await asyncio.sleep(8)
   raw,_=await call('/sessions/'+session+'/messages',limit=20,validate=lambda raw:validate_menu(raw,lambda t:'cobran' in t));items=messages(raw);assert_service_available(items)
   selected=option(lambda t:'cobran' in t);await message(selected['id'],selected)
   mark('envio do CPF')
   await asyncio.sleep(5);await message(format_cpf(job['cpf']))
   await asyncio.sleep(6)
   mark('seleção de '+kind)
   raw,_=await call('/sessions/'+session+'/messages',limit=20,validate=lambda raw:validate_menu(raw,(lambda t:'iquid' in t or 'saldo' in t) if kind=='saldo' else (lambda t:'parcela' in t or ('valor' in t and 'saldo' not in t))));items=messages(raw);assert_service_available(items,after_cpf=True)
   selected=option((lambda t:'iquid' in t or 'saldo' in t) if kind=='saldo' else (lambda t:'parcela' in t or ('valor' in t and 'saldo' not in t)))
   await message(selected['id'],selected);mark('retorno de '+kind);await asyncio.sleep(8)
   raw,_=await call('/sessions/'+session+'/messages',limit=30,validate=validate_result);items=messages(raw);assert_service_available(items,after_cpf=True)
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
   reason=(error.reason if isinstance(error,FlowStopped) else
    'CPF inválido: informe 11 dígitos' if isinstance(error,CpfFormatError) else
    'Resposta JSON inválida do atendimento' if isinstance(error,json.JSONDecodeError) else
    'Opção esperada não encontrada no menu de '+kind if isinstance(error,ValueError) else
    'Autenticação retornou resposta sem usuário' if isinstance(error,RuntimeError) else diagnostic['codigo'])
   mark(stage,'interrompida')
   return {'sucesso':False,'etapa':stage,'motivo_interrupcao':reason,'codigo':error.code if isinstance(error,FlowStopped) else diagnostic['codigo'],'eventos':events,'erro':error.reason if isinstance(error,FlowStopped) else ('HTTP '+str(error.code)) if isinstance(error,urllib.error.HTTPError) else ('Opção esperada não encontrada' if isinstance(error,ValueError) else 'Falha na comunicação com o atendimento'),
    'http_status':error.code if isinstance(error,urllib.error.HTTPError) else None,
    'todasMensagens':[m.get('contentText') or m.get('content') or m.get('text') or '' for m in items]}

 async def run(self,job,on_progress=None,on_checkpoint=None):
  if on_progress:await on_progress(5,'API experimental · saldo')
  first=await self.flow(job,'saldo')
  result={'resultado_saldo':first,'saldo_liquidacao':money(first.get('valorSaldo')),
   'total_parcelas':int(first['totalParcelas']) if first.get('totalParcelas') else None,
   'status':'processando','progress':50,'stage':'API experimental · fora do horário' if first.get('codigo')=='FORA_HORARIO_ATENDIMENTO' else 'API experimental · parcela'}
  if first.get('codigo') in BUSINESS_RESULTS:
   status,label=BUSINESS_RESULTS[first['codigo']]
   result.update(status=status,progress=100,stage=label,message=first['motivo_interrupcao'])
   return result
  balance=result['saldo_liquidacao']
  outside_hours=first.get('codigo')=='FORA_HORARIO_ATENDIMENTO'
  if outside_hours or not first.get('sucesso') or balance is None or balance<=0:
   confirmed_zero=first.get('sucesso') and balance==0
   reason=(first.get('motivo_interrupcao') or first.get('erro') or
    ('O atendimento informou saldo de liquidação de R$ 0,00.' if confirmed_zero else 'O atendimento não confirmou um saldo de liquidação positivo.'))
   result.update(status='interrompida' if confirmed_zero else 'revisao',progress=100,
    stage='API · parcela não iniciada',message=reason+' A parcela não foi consultada.')
   result['resultado_parcela']={'sucesso':False,'etapa':'parcela não iniciada',
    'motivo_interrupcao':reason,'nao_executada':True}
   return result
  if on_checkpoint:await on_checkpoint(result.copy())
  if on_progress:await on_progress(50,'API experimental · parcela')
  second=await self.flow(job,'parcela')
  result['resultado_parcela']=second
  result['valor_parcela']=money(second.get('valorParcela'))
  result.update(status='concluida' if first['sucesso'] and second['sucesso'] else 'revisao',progress=100,stage='API experimental · finalizada')
  if second.get('codigo') in BUSINESS_RESULTS:
   status,label=BUSINESS_RESULTS[second['codigo']]
   result.update(status=status,stage=label,message=second['motivo_interrupcao'])
   return result
  result['message']='Fluxos API executados. Confira os valores retornados.'
  texts=first.get('todasMensagens',[])+second.get('todasMensagens',[])
  referral=next((t for t in texts if 'assessoria de cobrança' in t.lower()),None)
  if referral:result['message']='Contrato em assessoria de cobrança. '+referral
  elif not(first['sucesso'] and second['sucesso']):result['message']='API sem retorno conclusivo. '+str(first.get('erro') or second.get('erro') or 'Valores não informados pelo atendimento.')
  reasons=[kind+': '+r['etapa']+' — '+r['motivo_interrupcao'] for kind,r in [('Saldo',first),('Parcela',second)] if r.get('motivo_interrupcao')]
  if reasons:result['message']+=' Motivo da interrupção: '+'; '.join(reasons)
  return result
