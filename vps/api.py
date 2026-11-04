"""Small, bounded HTTP gateway. Business transactions and ownership live in Postgres."""
import hashlib,json,os,re,socket,threading,urllib.error,urllib.request,uuid
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlsplit,parse_qs

MAX_BODY=2*1024*1024

def rpc(payload):
 url=os.environ['SUPABASE_URL'].rstrip('/')+'/rest/v1/rpc/api_execute'
 key=os.environ['SUPABASE_SERVICE_ROLE_KEY'];headers={'apikey':key,'Content-Type':'application/json'}
 if not key.startswith('sb_secret_'):headers['Authorization']='Bearer '+key
 request=urllib.request.Request(url,data=json.dumps(payload).encode(),headers=headers,method='POST')
 with urllib.request.urlopen(request,timeout=20) as response:return json.loads(response.read())

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
  if not target.path.startswith('/api/v1/') or '%' in target.path:return self.error(404,'not_found','Rota não encontrada.')
  auth=self.headers.get('Authorization','')
  if not re.fullmatch(r'Bearer apc_[a-f0-9]{64}',auth):return self.error(401,'invalid_token','Envie Authorization: Bearer SEU_TOKEN.')
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
   if any(k not in ('page','page_size','servico','paused','status') or len(v)!=1 for k,v in query.items()):return self.error(422,'invalid_filter','Filtros inválidos. CPF deve ser enviado por POST /leads/buscar.')
   payload={k:v[0] for k,v in query.items()}
  key=self.headers.get('Idempotency-Key')
  if key is not None and (not 1<=len(key)<=128 or not re.fullmatch(r'[A-Za-z0-9_.:-]+',key)):return self.error(400,'invalid_idempotency_key','Use chave de 1 a 128 caracteres: letras, números, ponto, dois-pontos, hífen ou sublinhado.')
  try:
   result=rpc(dict(p_hash=hashlib.sha256(token.encode()).hexdigest(),p_method=self.command,p_route=target.path[len('/api/v1'):],p_payload=payload,p_key=key))
   status=int(result['status']);body=result['body'];body['request_id']=self.request_id
   self.send_json(status,body,**({'Idempotency_Replayed':'true'} if result.get('replayed') else {}),**({'Retry_After':'60'} if status==429 else {}))
  except (urllib.error.URLError,socket.timeout,TimeoutError):self.error(503,'upstream_unavailable','API temporariamente indisponível. Tente novamente com a mesma Idempotency-Key.')
  except Exception:self.error(500,'internal_error','Não foi possível concluir a requisição.')
 def do_GET(self):self.handle_route()
 def do_POST(self):self.handle_route()
 def do_OPTIONS(self):self.request_id=str(uuid.uuid4());self.error(405,'method_not_allowed','Método não permitido. Integre pelo servidor, sem expor seu token no navegador público.')
 def do_PUT(self):self.do_OPTIONS()
 def do_DELETE(self):self.do_OPTIONS()
 def do_PATCH(self):self.do_OPTIONS()

if __name__=='__main__':Server(('127.0.0.1',8877),Handler).serve_forever()
