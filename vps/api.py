"""Small, bounded HTTP gateway. Business transactions and ownership live in Postgres."""
import hashlib,json,os,re,socket,threading,urllib.error,urllib.request,uuid
from datetime import date
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlsplit,parse_qs

MAX_BODY=2*1024*1024

CPF_DIGITS = re.compile(r'([0-9]{3})([0-9]{3})([0-9]{3})([0-9]{2})')

def format_cpf_field(record):
 value=record.get('cpf')
 if isinstance(value,str) and CPF_DIGITS.fullmatch(value):
  record['cpf']=CPF_DIGITS.sub(r'\1.\2.\3-\4',value)

def rpc(payload):
 url=os.environ['SUPABASE_URL'].rstrip('/')+'/rest/v1/rpc/api_execute'
 key=os.environ['SUPABASE_SERVICE_ROLE_KEY'];headers={'apikey':key,'Content-Type':'application/json'}
 if not key.startswith('sb_secret_'):headers['Authorization']='Bearer '+key
 request=urllib.request.Request(url,data=json.dumps(payload).encode(),headers=headers,method='POST')
 with urllib.request.urlopen(request,timeout=20) as response:return json.loads(response.read())

def supabase_call(path,payload=None,method='POST',bearer=None):
 key=os.environ['SUPABASE_SERVICE_ROLE_KEY'];headers={'apikey':key,'Content-Type':'application/json'}
 if bearer:headers['Authorization']='Bearer '+bearer
 elif not key.startswith('sb_secret_'):headers['Authorization']='Bearer '+key
 req=urllib.request.Request(os.environ['SUPABASE_URL'].rstrip('/')+path,
  data=json.dumps(payload).encode() if payload is not None else None,headers=headers,method=method)
 with urllib.request.urlopen(req,timeout=20) as response:
  body=response.read();return json.loads(body) if body else None

class AdminError(Exception):
 def __init__(self,status,code,message):self.status=status;self.code=code;self.message=message

def session_actor(auth):
 if not auth.startswith('Bearer ') or auth[7:].startswith('apc_'):raise AdminError(401,'session_required','Entre com sua conta do ApoiarCred.')
 try:user=supabase_call('/auth/v1/user',method='GET',bearer=auth[7:])
 except urllib.error.HTTPError:raise AdminError(401,'invalid_session','Sessão inválida. Entre novamente.')
 actor=user.get('id')
 if not actor:raise AdminError(401,'invalid_session','Sessão inválida.')
 return actor

def partner_admin(auth,method,path,payload):
 actor=session_actor(auth)
 def manage(action,data=None):return supabase_call('/rest/v1/rpc/admin_partner_manage',dict(p_actor=actor,p_action=action,p_input=data or {}))
 try:manage('check')
 except urllib.error.HTTPError as error:
  if error.code in (401,403):raise AdminError(403,'admin_required','Apenas administradores podem gerenciar parceiros.')
  raise
 if method=='GET' and path=='/api/admin/parceiros':return 200,{'data':manage('list')}
 if method!='POST':raise AdminError(404,'not_found','Rota não encontrada.')
 name=payload.get('name');permissions=payload.get('permissions')
 if not isinstance(name,str) or not 1<=len(name.strip())<=160 or not isinstance(permissions,list) or len(permissions)!=2:
  raise AdminError(422,'invalid_partner','Informe nome e as permissões dos dois tipos de higienização.')
 services=set()
 for rule in permissions:
  if not isinstance(rule,dict):raise AdminError(422,'invalid_permissions','Permissões inválidas.')
  service=rule.get('service')
  if service not in ('digimais_saldo_parcela','tjba_margem'):raise AdminError(422,'invalid_permissions','Tipo de higienização inválido.')
  services.add(service);limit=rule.get('daily_limit')
  if type(limit) is not int or not 0<=limit<=100000 or any(type(rule.get(k)) is not bool for k in ('enabled','allow_individual','allow_campaign')):raise AdminError(422,'invalid_permissions','Limites e permissões inválidos.')
 if services!={'digimais_saldo_parcela','tjba_margem'} or type(payload.get('active')) is not bool:raise AdminError(422,'invalid_permissions','Permissões inválidas.')
 if 'allow_integrations' in payload and type(payload['allow_integrations']) is not bool:raise AdminError(422,'invalid_permissions','Permissão de integrações inválida.')
 data={key:payload[key] for key in ('name','permissions','active')}
 if 'allow_integrations' in payload:data['allow_integrations']=payload['allow_integrations']
 if 'allow_amigoz' in payload:
  if type(payload['allow_amigoz']) is not bool:raise AdminError(422,'invalid_permissions','Permissão Amigoz inválida.')
  data['allow_amigoz']=payload['allow_amigoz']
 if 'shared_daily_limit' in payload:
  quota=payload['shared_daily_limit']
  if quota is not None and (type(quota) is not int or not 1<=quota<=100000):
   raise AdminError(422,'invalid_daily_limit','Informe uma cota diária entre 1 e 100.000 ou selecione Ilimitadas.')
  data['shared_daily_limit']=quota
 if 'trial_until' in payload:
  trial=payload['trial_until']
  if trial is not None:
   try:
    if not isinstance(trial,str) or date.fromisoformat(trial).isoformat()!=trial:raise ValueError()
   except ValueError:raise AdminError(422,'invalid_trial_date','Informe uma data válida para o fim do teste.')
  data['trial_until']=trial
 if path=='/api/admin/parceiros':
  email=payload.get('email');password=payload.get('password')
  if not isinstance(email,str) or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',email) or len(email)>254 or not isinstance(password,str) or not 8<=len(password)<=256:
   raise AdminError(422,'invalid_credentials','Informe e-mail válido e senha de 8 a 256 caracteres.')
  try:created=supabase_call('/auth/v1/admin/users',dict(email=email.strip().lower(),password=password,email_confirm=True))
  except urllib.error.HTTPError as error:
   if error.code in (400,422):raise AdminError(422,'account_not_created','Não foi possível criar a conta. Confira se o e-mail já existe e se a senha atende às regras do projeto.')
   raise
  created=created.get('user',created)
  user_id=str(uuid.UUID(created['id']));data.update(user_id=user_id,email=created.get('email',email))
  try:result=manage('create',data)
  except Exception:
   try:supabase_call('/auth/v1/admin/users/'+user_id,method='DELETE')
   except Exception:pass
   raise AdminError(503,'profile_not_saved','Não foi possível configurar as permissões. A conta não recebeu acesso. Confira a lista antes de tentar novamente.')
  return 201,{'data':result}
 match=re.fullmatch(r'/api/admin/parceiros/([a-f0-9-]{36})',path)
 if match:
  data['user_id']=str(uuid.UUID(match.group(1)))
  try:return 200,{'data':manage('update',data)}
  except urllib.error.HTTPError as error:
   if error.code in (400,403,404,422):raise AdminError(422,'profile_not_saved','Não foi possível alterar este parceiro. Confira o cadastro e as permissões.')
   raise
 raise AdminError(404,'not_found','Rota não encontrada.')

def amigoz_admin(auth,method,path,payload):
 import amigoz_api as amigoz
 actor=session_actor(auth)
 route=path.removeprefix('/api/admin/amigoz')
 def authorize(consume=False):
  try:
   supabase_call('/rest/v1/rpc/authorize_amigoz',dict(p_actor=actor,p_consume=consume))
  except urllib.error.HTTPError as error:
   if error.code==429:raise AdminError(429,'daily_limit','Limite diário de consultas atingido.') from None
   if error.code in (401,403):raise AdminError(403,'amigoz_access_denied','Acesso Amigoz não liberado para esta conta ou período de teste encerrado.') from None
   raise
 if (method,route) in (('GET','/convenios'),('POST','/consultar')):
  authorize()
 else:
  try:
   supabase_call('/rest/v1/rpc/admin_partner_manage',dict(p_actor=actor,p_action='check',p_input={}))
  except urllib.error.HTTPError as error:
   if error.code in (401,403):raise AdminError(403,'admin_required','Apenas administradores podem configurar a Amigoz.') from None
   raise
 try:
  if method=='GET' and route=='/convenios':
   return 200,{'data':amigoz.public_catalog()}
  if method=='POST' and route=='/configuracao':
   return 200,{'data':amigoz.save_configuration(payload)}
  config=amigoz.configuration()
  if method=='GET' and route=='/configuracao':
   return 200,{'data':amigoz.public_configuration(config)}
  if method=='POST' and route in ('/testar','/consultar'):
   if not config:raise AdminError(409,'amigoz_not_configured','Configure as credenciais Amigoz antes de consultar.')
   if route=='/testar':
    amigoz.session(config,force=True)
    return 200,{'data':{'connected':True}}
   execution={}
   def begin():
    convenio=amigoz.CATALOG[payload['convenio_id']]
    try:
     record=supabase_call('/rest/v1/rpc/start_amigoz_individual',dict(
      p_actor=actor,p_cpf=re.sub(r'[.\-\s]','',payload['cpf']),
      p_convenio='amigoz_'+str(convenio['id']),p_uf=convenio['uf'],
      p_modo=payload['modo'],p_matricula=payload.get('numero_matricula')))
     job=record[0] if isinstance(record,list) and record else record
     if not isinstance(job,dict) or not job.get('id') or not job.get('lease'):
      raise AdminError(502,'amigoz_history_start','O banco não confirmou o registro da consulta.')
     execution.update(job)
    except urllib.error.HTTPError as error:
     if error.code==429:raise AdminError(429,'daily_limit','Limite diário de consultas atingido.') from None
     if error.code in (401,403):raise AdminError(403,'amigoz_access_denied','Acesso Amigoz não liberado.') from None
     raise
   diagnostics=None
   if payload.get('modo') in ('margem','ambos'):
    try:
     access=supabase_call('/rest/v1/rpc/admin_partner_manage',dict(p_actor=actor,p_action='check',p_input={}))
     if isinstance(access,dict) and access.get('admin') is True:
      diagnostics={}
    except Exception:
     pass  # Diagnostics fail closed. The customer result remains available.
   result=amigoz.consultation(config,payload,before_request=begin,diagnostics=diagnostics)
   if execution:
    operations=[result[key] for key in ('saque','margem') if key in result]
    failures=sum(operation.get('status')!='respondido' for operation in operations)
    state='erro' if failures==len(operations) else 'revisao' if failures else 'concluida'
    try:
     saved=supabase_call('/rest/v1/rpc/finish_amigoz_import_job',dict(
      p_id=execution['id'],p_lease=execution['lease'],p_status=state,p_resultado=result,
      p_message='Resultado parcial.' if state=='revisao' else 'Consulta finalizada.'))
    except Exception as error:
     print(f'Amigoz | falha na gravação da consulta {execution["id"]} ({type(error).__name__}).',flush=True)
     saved=False
    result['consulta_id']=execution['id']
    result['salvo_no_historico']=saved is True
   if diagnostics:
    result['diagnostico_admin']=diagnostics
   return 200,{'data':result}
  raise AdminError(404,'not_found','Rota não encontrada.')
 except amigoz.AmigozError as error:
  raise AdminError(502 if error.status in (401,403) else error.status,error.code,error.message) from None

class Server(ThreadingHTTPServer):
 daemon_threads=True;request_queue_size=32
 def __init__(self,*args,**kwargs):self.slots=threading.BoundedSemaphore(16);super().__init__(*args,**kwargs)
 def process_request(self,request,address):
  if not self.slots.acquire(blocking=False):
   try:request.sendall(b'HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
   finally:self.shutdown_request(request)
   return
  try:super().process_request(request,address)
  except BaseException:self.slots.release();raise
 def process_request_thread(self,*args):
  try:super().process_request_thread(*args)
  finally:self.slots.release()

class Handler(BaseHTTPRequestHandler):
 server_version='ApoiarCredAPI';sys_version=''
 def setup(self):super().setup();self.connection.settimeout(10)
 def log_message(self,*args):pass # Never log tokens, CPF query strings or request bodies.
 def send_json(self,status,body,**headers):
  raw=json.dumps(body,ensure_ascii=False).encode();self.send_response(status)
  self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(raw)))
  self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff')
  for name,value in headers.items():self.send_header(name.replace('_','-'),str(value))
  self.end_headers();self.wfile.write(raw)
 def error(self,status,code,message):self.send_json(status,{'error':{'code':code,'message':message},'request_id':self.request_id})
 def handle_route(self):
  self.request_id=str(uuid.uuid4());target=urlsplit(self.path)
  if self.command=='GET' and target.path=='/api/health':
   return self.send_json(200,{'status':'ok','version':'1'})
  if not target.path.startswith(('/api/v1/','/api/admin/')) or '%' in target.path:return self.error(404,'not_found','Rota não encontrada.')
  auth=self.headers.get('Authorization','')
  admin=target.path.startswith('/api/admin/')
  if not admin and not re.fullmatch(r'Bearer apc_[a-f0-9]{64}',auth):return self.error(401,'invalid_token','Envie Authorization: Bearer SEU_TOKEN.')
  token=auth[7:];payload={}
  if self.headers.get('Transfer-Encoding'):return self.error(400,'invalid_body','Envie Content-Length e JSON.')
  if self.command=='POST':
   if self.headers.get('Content-Type','').split(';')[0].strip().lower()!='application/json':return self.error(415,'content_type','Use application/json.')
   try:length=int(self.headers.get('Content-Length','0'))
   except ValueError:return self.error(400,'invalid_length','Content-Length inválido.')
   if length<0 or length>MAX_BODY:return self.error(413,'body_too_large','Limite de 2 MB.')
   try:
    payload=json.loads(self.rfile.read(length))
    if not isinstance(payload,dict):raise ValueError()
   except (ValueError,UnicodeError):return self.error(400,'invalid_json','Envie um objeto JSON válido.')
  else:
   query=parse_qs(target.query,keep_blank_values=True)
   allowed=('page','page_size','servico','paused','status')
   if re.fullmatch(r'/api/v1/campanhas/[^/]+/leads',target.path):allowed+=('all',)
   if target.path=='/api/v1/clientes/convenios':allowed=('uf',)
   if target.path=='/api/v1/clientes/importacoes':allowed=('offset',)
   if target.path=='/api/v1/oportunidades':allowed=('page','page_size','etapa','tipos','exportaveis')
   if any(k not in allowed or len(v)!=1 for k,v in query.items()):return self.error(422,'invalid_filter','Filtros inválidos. CPF deve ser enviado por POST /leads/buscar.')
   payload={k:v[0] for k,v in query.items()}
  key=self.headers.get('Idempotency-Key')
  if key is not None and (not 1<=len(key)<=128 or not re.fullmatch(r'[A-Za-z0-9_.:-]+',key)):return self.error(400,'invalid_idempotency_key','Use chave de 1 a 128 caracteres: letras, números, ponto, dois-pontos, hífen ou sublinhado.')
  try:
   if admin:
    handler=amigoz_admin if target.path.startswith('/api/admin/amigoz/') else partner_admin
    status,body=handler(auth,self.command,target.path,payload);body['request_id']=self.request_id;return self.send_json(status,body)
   result=rpc(dict(p_hash=hashlib.sha256(token.encode()).hexdigest(),p_method=self.command,p_route=target.path[len('/api/v1'):],p_payload=payload,p_key=key))
   status=int(result['status']);body=result['body'];body['request_id']=self.request_id
   format_cpf_field(body)
   if isinstance(body.get('data'),dict):format_cpf_field(body['data'])
   for field in ('data','accepted','duplicates'):
    rows=body.get(field)
    if isinstance(rows,list):
     for row in rows:
      if isinstance(row,dict):format_cpf_field(row)
   self.send_json(status,body,**({'Idempotency_Replayed':'true'} if result.get('replayed') else {}),**({'Retry_After':'60'} if status==429 and body.get('error',{}).get('code')=='rate_limit' else {}))
  except AdminError as e:self.error(e.status,e.code,e.message)
  except (urllib.error.URLError,socket.timeout,TimeoutError):self.error(503,'upstream_unavailable','API temporariamente indisponível. Tente novamente com a mesma Idempotency-Key.')
  except Exception:self.error(500,'internal_error','Não foi possível concluir a requisição.')
 def do_GET(self):self.handle_route()
 def do_POST(self):self.handle_route()
 def do_OPTIONS(self):self.request_id=str(uuid.uuid4());self.error(405,'method_not_allowed','Método não permitido. Integre pelo servidor, sem expor seu token no navegador público.')
 def do_PUT(self):self.do_OPTIONS()
 def do_DELETE(self):self.do_OPTIONS()
 def do_PATCH(self):self.do_OPTIONS()

if __name__=='__main__':
 import amigoz_queue
 queue_stop=amigoz_queue.start(supabase_call)
 try:Server(('127.0.0.1',8877),Handler).serve_forever()
 finally:queue_stop.set()
