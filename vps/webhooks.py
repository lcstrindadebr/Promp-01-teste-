"""Independent webhook dispatcher. No bank/browser calls and no destination/secret logs."""
import concurrent.futures,hashlib,hmac,http.client,ipaddress,json,re,socket,ssl,threading,time
from urllib.parse import urlsplit,quote
from api import supabase_call

class DestinationError(Exception):pass

def destination(url):
 if not isinstance(url,str) or len(url)>2048 or any(ord(c)<33 or ord(c)==127 for c in url):raise DestinationError()
 try:
  parsed=urlsplit(url);host=parsed.hostname
  if parsed.scheme!='https' or not host or parsed.username is not None or parsed.password is not None or parsed.fragment or parsed.port not in (None,443) or '%' in host:raise DestinationError()
  host=host.encode('idna').decode('ascii')
  addresses=list(dict.fromkeys(item[4][0] for item in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)))
  if not addresses or any(not ipaddress.ip_address(ip).is_global for ip in addresses):raise DestinationError()
 except (ValueError,UnicodeError):raise DestinationError()
 path=quote(parsed.path or '/',safe="/%:@!$&'()*+,;=-._~")
 if parsed.query:path+='?'+quote(parsed.query,safe="=&%:@/?+!$'()*,-._~")
 return host,addresses[0],path

class PinnedHTTPS(http.client.HTTPSConnection):
 def __init__(self,host,ip):super().__init__(host,443,timeout=10,context=ssl.create_default_context());self.ip=ip
 def connect(self):
  # Resolve once, connect to that validated IP, preserve hostname verification/SNI.
  raw=socket.create_connection((self.ip,443),timeout=10)
  try:self.sock=self._context.wrap_socket(raw,server_hostname=self.host)
  except BaseException:raw.close();raise

def signed_body(payload,secret,timestamp):
 if not isinstance(secret,str) or not re.fullmatch(r'whsec_[a-f0-9]{64}',secret):raise ValueError('missing_secret')
 body=json.dumps(payload,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode('utf-8')
 if len(body)>262144:raise ValueError('payload_too_large')
 signature=hmac.new(secret.encode(),str(timestamp).encode()+b'.'+body,hashlib.sha256).hexdigest()
 return body,'v1='+signature

def deliver(job):
 connection=None;timer=None
 try:
  host,ip,path=destination(job['url']);timestamp=int(time.time());body,signature=signed_body(job['payload'],job['secret'],timestamp)
  connection=PinnedHTTPS(host,ip)
  def abort():
   try:
    if connection.sock:connection.sock.shutdown(socket.SHUT_RDWR)
   except OSError:pass
  timer=threading.Timer(15,abort);timer.daemon=True;timer.start()
  connection.request('POST',path,body=body,headers={
   'Content-Type':'application/json; charset=utf-8','User-Agent':'ApoiarCred-Webhooks/1.0',
   'X-ApoiarCred-Event-Id':str(job['event_id']),'X-ApoiarCred-Delivery-Id':str(job['id']),
   'X-ApoiarCred-Timestamp':str(timestamp),'X-ApoiarCred-Signature':signature})
  status=connection.getresponse().status # No redirects, response body or arbitrary error text is stored.
  success=200<=status<300;retry=status in (408,425,429) or 500<=status<600
  return dict(p_success=success,p_http=status,p_error=None if success else 'HTTP '+str(status)+(' — redirecionamento não seguido.' if 300<=status<400 else ''),p_retry=retry)
 except DestinationError:return dict(p_success=False,p_http=None,p_error='Destino não permitido. Use HTTPS público na porta 443.',p_retry=False)
 except ssl.SSLCertVerificationError:return dict(p_success=False,p_http=None,p_error='Certificado TLS inválido no destino.',p_retry=False)
 except (OSError,http.client.HTTPException):return dict(p_success=False,p_http=None,p_error='Falha de conexão, DNS ou tempo excedido no destino.',p_retry=True)
 except (ValueError,KeyError,TypeError):return dict(p_success=False,p_http=None,p_error='Payload ou segredo de assinatura inválido.',p_retry=False)
 finally:
  if timer:timer.cancel()
  if connection:connection.close()

def rpc(name,body=None):return supabase_call('/rest/v1/rpc/'+name,{} if body is None else body)

def dispatch_batch(jobs,pool):
 futures={pool.submit(deliver,job):job for job in jobs}
 for future in concurrent.futures.as_completed(futures):
  job=futures[future]
  try:result=future.result()
  except Exception:result=dict(p_success=False,p_http=None,p_error='Falha interna do envio.',p_retry=True)
  # Only persist again after an ACK failure; never call the HTTP destination again here.
  for attempt in range(6):
   try:
    rpc('ack_webhook_delivery',dict(p_id=job['id'],p_token=job['claim_token'],**result));break
   except Exception:
    print('Webhooks: confirmação no banco indisponível; repetindo somente a gravação.',flush=True)
    if attempt<5:time.sleep(5)

def main():
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  while True:
   try:
    jobs=rpc('claim_webhook_deliveries') or []
    if jobs:dispatch_batch(jobs,pool)
    else:time.sleep(5)
   except Exception:
    print('Webhooks: fila indisponível; nova tentativa em 5 segundos.',flush=True);time.sleep(5)
if __name__=='__main__':main()
