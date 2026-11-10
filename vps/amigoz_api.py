"""Server-side client for the Amigoz individual consultation pilot."""
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import ssl
import tempfile
import threading
import unicodedata
from urllib.parse import urlsplit


class AmigozError(Exception):
 def __init__(self,status,code,message):
  super().__init__(message)
  self.status=status
  self.code=code
  self.message=message


def load_catalog():
 rows=json.loads(Path(__file__).with_name('amigoz_convenios.json').read_text())
 result={}
 for row in rows:
  if type(row.get('id')) is not int or row['id'] in result or not row.get('uf') or not row.get('nome'):
   raise ValueError('Catálogo Amigoz inválido: identificador, estado ou nome.')
  if row.get('averbadora') is not None and type(row['averbadora']) is not int:
   raise ValueError('Catálogo Amigoz inválido: averbadora.')
  if any(type(product.get('codigo_produto')) is not int or type(product.get('tipo_margem')) is not int for product in row.get('produtos',[])):
   raise ValueError('Catálogo Amigoz inválido: produto ou margem.')
  result[row['id']]=row
 return {key:row for key,row in result.items() if row.get('operacional',True)}

CATALOG = load_catalog()


def public_catalog():
 # Full contractual metadata stays on the backend; picker receives only its fields.
 fields=('id','nome','uf','averbadora','matricula_obrigatoria','senha_servidor','produtos')
 return [{key:row[key] for key in fields} for row in CATALOG.values()]
LOCK = threading.Lock()
SESSION = None
MAX_RESPONSE = 1024 * 1024


def credentials_path():
 return Path(os.environ.get('STATE_DIRECTORY','/var/lib/apoiarcred-amigoz'))/'credentials.json'


def configuration():
 path=credentials_path()
 try:
  return json.loads(path.read_text())
 except FileNotFoundError:
  return None


def public_configuration(config):
 if not config:
  return {'configured':False}
 return {'configured':True,**{key:config[key] for key in ('url','usuario','corban_id')}}


def endpoint(value):
 try:
  parsed=urlsplit(value)
  if (parsed.scheme!='https' or not parsed.hostname or parsed.username is not None or
      parsed.password is not None or parsed.port not in (None,443) or
      parsed.query or parsed.fragment or parsed.path not in ('','/') or
      not re.fullmatch(r'[a-zA-Z0-9.-]+',parsed.hostname) or '.' not in parsed.hostname):
   raise ValueError()
  return parsed.hostname.lower()
 except (ValueError,TypeError,AttributeError):
  raise AmigozError(422,'invalid_amigoz_url','Informe o endereço HTTPS base da Amigoz, sem caminho ou parâmetros.') from None


def save_configuration(payload):
 global SESSION
 with LOCK:
  previous=configuration() or {}
  url='https://'+endpoint(payload.get('url'))
  user=payload.get('usuario')
  corban=payload.get('corban_id') or None
  password=payload.get('senha')
  if not isinstance(user,str) or not 1<=len(user.strip())<=200 or (corban is not None and (type(corban) is not int or not 1<=corban<=2147483647)):
   raise AmigozError(422,'invalid_amigoz_config','Informe um usuário válido.')
  user=user.strip()
  if not password and previous.get('url')==url and previous.get('usuario')==user:
   password=previous.get('senha')
  if not isinstance(password,str) or not 1<=len(password)<=512:
   raise AmigozError(422,'invalid_amigoz_password','Informe a senha da Amigoz para este usuário e endereço.')
  config={'url':url,'usuario':user,'senha':password,'corban_id':corban}
  path=credentials_path()
  with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,delete=False) as file:
   temp=Path(file.name)
   try:
    json.dump(config,file)
    file.flush()
    os.fsync(file.fileno())
    temp.replace(path)
   finally:
    temp.unlink(missing_ok=True)
  SESSION=None
  return public_configuration(config)


class PublicHTTPS(http.client.HTTPSConnection):
 def connect(self):
  addresses={entry[4][0] for entry in socket.getaddrinfo(self.host,443,type=socket.SOCK_STREAM)}
  if not addresses or any(not ipaddress.ip_address(address).is_global or ipaddress.ip_address(address).is_multicast for address in addresses):
   raise AmigozError(422,'invalid_amigoz_host','O endereço da Amigoz deve apontar para um servidor público.')
  sock=socket.create_connection((sorted(addresses)[0],443),timeout=self.timeout)
  try:
   self.sock=self._context.wrap_socket(sock,server_hostname=self.host)
  except BaseException:
   sock.close()
   raise


def request(config,path,payload,token=None):
 timeout = 60 if path == '/api/consulta-margem' else 30
 conn=PublicHTTPS(endpoint(config['url']),timeout=timeout,context=ssl.create_default_context())
 headers={'Content-Type':'application/json','Accept':'application/json'}
 if token:
  headers['Authorization']='Bearer '+token
 try:
  conn.request('POST',path,json.dumps(payload),headers)
  response=conn.getresponse()
  if response.status in (401,403):
   raise AmigozError(response.status,'amigoz_denied','A Amigoz recusou a autenticação ou a permissão para esta operação.')
  if not 200<=response.status<300:
   raise AmigozError(response.status,'amigoz_upstream',f'A Amigoz respondeu HTTP {response.status} em {path}.')
  raw=response.read(MAX_RESPONSE+1)
  if len(raw)>MAX_RESPONSE:
   raise AmigozError(502,'amigoz_response','A resposta da Amigoz excedeu o tamanho permitido.')
  if not raw:
   raise AmigozError(502,'amigoz_empty_response',f'A Amigoz devolveu uma resposta vazia em {path}.')
  return json.loads(raw)
 except TimeoutError:
  raise AmigozError(504,'amigoz_timeout',f'Tempo de espera pela Amigoz excedido em {path} ({timeout} s por operação de rede).') from None
 except (json.JSONDecodeError, UnicodeDecodeError):
  raise AmigozError(502,'amigoz_invalid_json',f'A Amigoz devolveu uma resposta que não é JSON em {path}.') from None
 except (OSError,http.client.HTTPException):
  raise AmigozError(502,'amigoz_transport',f'A conexão com a Amigoz falhou em {path}.') from None
 finally:
  conn.close()


def read_tokens(response):
 if not isinstance(response,dict):
  return None,None
 data=response.get('data')
 if isinstance(data,dict):
  response={**response,**data}
 def token(*keys):
  return next((response[k] for k in keys if isinstance(response.get(k),str)
               and re.fullmatch(r'[A-Za-z0-9._~+/=-]{1,8192}',response[k])),None)
 return token('access','access_token','token'),token('refresh_token','refresh')


def start_session(config,refresh=None):
 if refresh:
  response=request(config,'/api/login/refresh',{'refresh':refresh})
 else:
  response=request(config,'/api/login',{key:config[key] for key in ('usuario','senha')})
 token,next_refresh=read_tokens(response)
 if not token:
  raise AmigozError(502,'amigoz_token','A Amigoz devolveu um formato de token não reconhecido.')
 # Match the working integration: use the access token returned by login.
 return token,next_refresh or refresh


def session(config,failed=None,force=False):
 global SESSION
 if not LOCK.acquire(timeout=5):
  raise AmigozError(503,'amigoz_busy','A conexão Amigoz está ocupada. Tente novamente.')
 try:
  if SESSION and SESSION[0]==config and not force and SESSION[1]!=failed:
   return SESSION[1]
  refresh=SESSION[2] if SESSION and SESSION[0]==config and not force else None
  try:
   token,new_refresh=start_session(config,refresh)
  except AmigozError as error:
   if not refresh or error.status not in (401,403):
    raise
   token,new_refresh=start_session(config)
  SESSION=(config,token,new_refresh)
  return token
 finally:
  LOCK.release()


def call(config,path,payload):
 token=session(config)
 try:
  return request(config,path,payload,token)
 except AmigozError as error:
  if error.status!=401:
   raise
 return request(config,path,payload,session(config,failed=token))


def normalized(value):
 return ' '.join(re.findall(r'[a-z0-9]+',unicodedata.normalize('NFKD',str(value)).encode('ascii','ignore').decode().lower()))


def saque_result(response,convenio):
 if not isinstance(response,list) or any(not isinstance(item,dict) for item in response):
  raise AmigozError(502,'amigoz_saque_response','O formato do resultado de saque não corresponde ao OpenAPI.')
 fields=('elegivel','valor_saque_disponivel','valor_saque_minimo','limite_cartao','limite_disponivel_cliente','status','nome_oferta','numeroMatricula','numero_matricula','nome_matricula')
 matched=[]
 for item in response:
  reference=item.get('convenio_cliente')
  if str(reference)==str(convenio['id']) or normalized(reference)==normalized(convenio['nome']):
   row={key:item.get(key) for key in fields if type(item.get(key)) in (str,int,float,bool,type(None))}
   row['erro_informado']=bool(item.get('error'))
   matched.append(row)
 return {'ofertas':matched,'total_sem_correspondencia':len(response)-len(matched)}


def margin_result(value):
 if isinstance(value,dict):
  return {key:margin_result(item) for key,item in value.items()
          if not re.search(r'senha|token|password|authorization|secret|credencial',normalized(key))}
 if isinstance(value,list):
  return [margin_result(item) for item in value]
 return value


def consultation(config,payload,before_request=None):
 mode=payload.get('modo')
 convenio_id=payload.get('convenio_id')
 convenio=CATALOG.get(convenio_id) if type(convenio_id) is int else None
 raw_cpf=payload.get('cpf')
 cpf=re.sub(r'[.\-\s]','',raw_cpf) if isinstance(raw_cpf,str) else ''
 if mode not in ('saque','margem','ambos') or not convenio or not re.fullmatch(r'[0-9]{11}',cpf):
  raise AmigozError(422,'invalid_amigoz_query','Informe CPF, convênio e tipo de consulta válidos.')
 margin={'cpf':cpf,'convenio':str(convenio_id),'averbadora':str(convenio['averbadora'])}
 if mode in ('margem','ambos') and convenio['averbadora'] is not None:
  # OpenAPI ConsultaQueryParams: these nullable fields are optional.
  for field,label in (('numero_matricula','matrícula'),('senha_servidor','senha do servidor')):
   value=payload.get(field)
   if (value is not None and (not isinstance(value,str) or len(value)>256)):
    raise AmigozError(422,'invalid_amigoz_margin_input',f'Informe {label} para este convênio.')
   if value:
    margin[field]=value
 if before_request and (mode!='margem' or convenio['averbadora'] is not None):
  before_request()
 result={'cpf':f'{cpf[:3]}.{cpf[3:6]}.{cpf[6:9]}-{cpf[9:]}','convenio_id':convenio_id}
 for operation,path,body in (('saque','/api/simulacao/v2/saque-complementar',{'cpf':cpf}),
                             ('margem','/api/consulta-margem',margin)):
  if mode not in (operation,'ambos'):
   continue
  if operation=='margem' and convenio['averbadora'] is None:
   result[operation]={'status':'indisponivel','mensagem':'Consulta de margem indisponível para este convênio. Falta o ID da averbadora.'}
   continue
  try:
   value=call(config,path,body)
   data=saque_result(value,convenio) if operation=='saque' else margin_result(value)
   result[operation]={'status':'respondido','dados':data}
  except AmigozError as error:
   result[operation]={'status':'erro','mensagem':error.message,'http_status':error.status,'codigo':error.code,'operacao':operation}
 return result
