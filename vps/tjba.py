"""Read-only TJBA adapter. References require authenticated portal homologation.
Never reserve margin, make proposals, save browser state or log portal content/secrets.
"""
import asyncio,re,time,unicodedata
from tjba_proxy import launch_options
from decimal import Decimal,InvalidOperation
from datetime import datetime,timezone
from urllib.parse import urlsplit
BASE='https://govbahia.consigx.com.br'
PATH='/Margem/ConsultaMargem.aspx'
# ConsigX uses the default Chromium HTTPS transport, independent of Digi+ workarounds.
CHROMIUM_ARGS=('--disable-dev-shm-usage',)
CPF='#body_cpfTextBox';RESULT_CPF='#body_cpf_nascimentoTextBox';SEARCH='#body_pesquisarButton';GRID='#body_servidorGridView'
FIELDS={'motivo_situacao':'#body_txtMotivo','matricula':'#body_matriculaTextBox','tipo_servidor':'#body_categoriaTextBox','situacao_atual':'#body_txtSituacao'}
ROWS={'emprestimo_disponivel':'#body_rptMargens1_headerservico1_0','cartao_disponivel':'#body_rptMargens1_headerservico1_1'}
class Review(Exception):
 def __init__(self,status,message,details=None):self.status=status;self.message=message;self.details=details or {};super().__init__(message)
def norm(text):return ' '.join(unicodedata.normalize('NFKD',str(text)).encode('ascii','ignore').decode().lower().split())
def normalize_cpf(value):
 value=re.sub(r'\D','',str(value))
 if not value or len(value)>11:raise ValueError('CPF inválido')
 return value.zfill(11)
def parse_brl(value):
 text=str(value or '').strip().replace('\xa0','').replace(' ','').replace('R$','')
 if text in ('','-','—'):return None
 if not re.fullmatch(r'\(?-?(?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d{1,2}|\.\d{1,2})?\)?',text):raise ValueError('Valor de margem não reconhecido')
 negative=text.startswith('(') and text.endswith(')');text=text.strip('()')
 if ',' in text:text=text.replace('.','').replace(',','.')
 elif re.fullmatch(r'-?\d{1,3}(?:\.\d{3})+',text):text=text.replace('.','')
 try:result=Decimal(text)
 except InvalidOperation:raise ValueError('Valor de margem não reconhecido') from None
 if negative:result=-result
 return str(result.quantize(Decimal('.01')))
def available_index(headers):
 matches=[i for i,h in enumerate(headers) if norm(h) in ('margem disponivel','margem disponivel (r$)')]
 if len(matches)!=1:raise Review('revisao_margens','Cabeçalho Margem Disponível não identificado de forma inequívoca.')
 return matches[0]
def active_index(headers,rows):
 labels=[norm(h) for h in headers]
 candidates=[i for i,h in enumerate(labels) if h in ('situacao','situacao atual','situacao do vinculo','status')]
 if len(candidates)!=1:return None
 col=candidates[0];active=[i for i,row in enumerate(rows) if len(row)>col and norm(row[col]) in ('ativo','ativa','ativo - ativo','ativa - ativa')]
 return active[0] if len(active)==1 else None
async def value(page,selector):
 loc=page.locator(selector)
 if await loc.count()!=1:return None
 tag=await loc.evaluate('el=>el.tagName.toLowerCase()')
 text=await loc.input_value() if tag in ('input','textarea','select') else await loc.inner_text()
 return text.strip() or None
async def assert_convenio(page):
 # Verified on 2026-11-02: the selected agreement is this exact header label.
 label=page.locator('#descricaoOrgaoLabel')
 if await label.count()==1 and norm(await label.inner_text())=='tribunal justica da bahia':return
 raise Review('sessao_expirada','O convênio TJBA selecionado não pôde ser confirmado pelo cabeçalho do portal.')
async def challenge(page):
 for selector in ['#txtCaptcha','iframe[src*="recaptcha"]','iframe[src*="hcaptcha"]']:
  if await page.locator(selector).first.is_visible():raise Review('sessao_expirada','O portal exige verificação humana. Retome a autenticação autorizada antes de consultar.')
async def report_step(callback,percent,label):
 if callback:await callback(percent,label)
async def dismiss_cookies(page):
 button=page.locator('#entendi-cookies')
 if await button.is_visible():await button.click(timeout=5000)
async def install_handlers(page):
 async def dismiss(target):await target.click(timeout=5000)
 await page.add_locator_handler(page.locator('#entendi-cookies'),dismiss)
def login_notice(text):
 value=norm(text)
 for pattern,message in [
  (r'(usuario|login|senha).*(invalid|incorret)|invalid.*(usuario|senha)', 'O portal informou usuário ou senha inválidos.'),
  (r'(ja.*(logado|conectado)|sessao.*(ativa|aberta)|acesso simultaneo)', 'O portal informou sessão já ativa ou acesso simultâneo.'),
  (r'(bloquead|suspens)', 'O portal informou bloqueio ou suspensão do acesso.'),
  (r'(senha.*(expir|venc)|alter.*senha|trocar.*senha)', 'O portal solicitou alteração de senha.'),
  (r'(cookie)', 'O portal exibiu uma mensagem relacionada a cookies.'),
  (r'(ip.*(autoriz|permit|restri)|acesso.*(negado|restrito))', 'O portal informou restrição de acesso ou de IP.')]:
  if re.search(pattern,value):return message
 return 'O portal exibiu uma mensagem de login não reconhecida; requer inspeção manual.'

def safe_login_text(text,credentials=None):
 for value in (credentials or {}).values():
  if isinstance(value,str) and value:text=re.sub(re.escape(value),'[oculto]',text,flags=re.I)
 text=re.sub(r'https?://\S+','[endereço omitido]',text)
 text=re.sub(r'[\w.+-]+@[\w.-]+','[email omitido]',text)
 text=re.sub(r'\d[\d. /()-]{3,}\d','[número omitido]',text)
 text=re.sub(r'(?i)(senha|password|token|secret)\s*[:=]\s*\S+',r'\1: [oculto]',text)
 return ' '.join(text.split())[:300]

def is_disconnect_confirmation(text):
 value=norm(text)
 value=re.sub(r'[^a-z0-9 ]',' ',value)
 value=' '.join(value.split())
 value=re.sub(r' (confirmar|cancelar)( (confirmar|cancelar))*$','',value)
 return value=='usuario ja logado deseja desconectar seu usuario dos outros terminais'

async def active_registration_modal(loc):
 # ASP.NET renders these forms in the document even when they are not open.
 # Require an actual foreground dialog layer, not just nonzero dimensions.
 return await loc.evaluate("""el => {
  const r=el.getBoundingClientRect();
  if (!r.width || !r.height) return false;
  let layer=false;
  for(let n=el;n;n=n.parentElement){
   const s=getComputedStyle(n);
   if(s.display==='none'||s.visibility==='hidden'||Number(s.opacity)===0) return false;
   if(n.getAttribute('aria-modal')==='true'||
      (['absolute','fixed'].includes(s.position)&&parseInt(s.zIndex,10)>0)) layer=true;
  }
  const x=Math.min(innerWidth-1,Math.max(0,r.left+r.width/2));
  const y=Math.min(innerHeight-1,Math.max(0,r.top+Math.min(r.height/2,100)));
  const hit=document.elementFromPoint(x,y);
  return layer && !!hit && el.contains(hit);
 }""")

async def inspect_login_notice(page,credentials=None):
 # Only inspect known login modal text; never return raw content or field values.
 for selector,kind in [('#ucAjaxModalPopup1_PanelPopup','mensagem'),
                       ('#ucAjaxModalPopupConfirmacao1_PanelPopup','confirmacao'),
                       ('#ucComplementoCadastro_PanelPopup','cadastro'),
                       ('#ucComplementoCadastroPadrao_PanelPopup','cadastro')]:
  loc=page.locator(selector)
  if await loc.is_visible():
   if kind=='cadastro' and not await active_registration_modal(loc):continue
   text=await loc.inner_text()
   useful=re.sub(r'(?im)^\s*(OK|Confirmar|Cancelar)\s*$','',text).strip()
   if kind!='cadastro' and not useful:continue
   if kind=='confirmacao' and is_disconnect_confirmation(useful):
    # Keyboard activation targets the actual submit control despite visual overlap.
    await loc.locator('#ucAjaxModalPopupConfirmacao1_btnConfirmarPopup').press('Enter',timeout=10000,no_wait_after=True)
    await page.locator('#gvOrgao:visible, #descricaoOrgaoLabel:visible').first.wait_for(state='visible',timeout=20000)
    return
   if kind=='cadastro':message='O portal solicitou complementação de cadastro. Conclua essa etapa manualmente no portal.'
   elif kind=='confirmacao':message='O portal solicitou confirmação adicional de login. '+login_notice(text)
   else:message=login_notice(text)
   invalid=kind=='mensagem' and message=='O portal informou usuário ou senha inválidos.'
   if 'não reconhecida' in message and credentials is not None:message+=' Mensagem do portal: '+safe_login_text(useful,credentials)
   raise Review('sessao_expirada',message,{'aviso_login':kind,'invalid_password':invalid})

async def login(page,credentials,on_step=None):
 await report_step(on_step,12,'Abrir página pública de login ConsigX')
 response=await page.goto(BASE+'/',wait_until='domcontentloaded',timeout=30000)
 if response and response.status>=400:raise Review('sessao_expirada',f'Entrada do portal retornou HTTP {response.status}. Nenhuma credencial foi enviada.')
 await challenge(page);await dismiss_cookies(page)
 if urlsplit(page.url).hostname!='govbahia.consigx.com.br':raise Review('sessao_expirada','O portal redirecionou a autenticação para outro domínio.')
 # A reused, authenticated browser may already have the agreement selected.
 if await page.locator('#descricaoOrgaoLabel').is_visible():
  await assert_convenio(page)
 else:
  await report_step(on_step,15,'Identificar formulário de login')
  if not await page.locator('#gvOrgao').is_visible():
   await page.locator('#txtLogin').wait_for(state='visible',timeout=12000)
   await page.locator('#txtSenha').wait_for(state='visible',timeout=12000)
   await report_step(on_step,18,'Enviar login ao ConsigX')
   await dismiss_cookies(page)
   show_password=page.locator('#chkMostrarSenha')
   if await show_password.is_visible():await show_password.check(timeout=5000)
   await page.wait_for_function("()=>window.Sys?.WebForms?.PageRequestManager?!Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack():document.readyState!=='loading'",timeout=12000)
   await page.locator('#txtLogin').fill(credentials['username'])
   await page.locator('#txtLogin').press('Tab')
   await page.wait_for_function("()=>window.Sys?.WebForms?.PageRequestManager?!Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack():document.readyState!=='loading'",timeout=12000)
   await page.locator('#txtSenha').fill(credentials['password'])
   await challenge(page)
   if await page.locator('#txtLogin').input_value()!=credentials['username'] or await page.locator('#txtSenha').input_value()!=credentials['password']:
    raise Review('sessao_expirada','Campo de login ou senha não preservado após aguardar a atualização do formulário. Nenhuma credencial foi registrada no log.',{'retryable_login':True})
   # The validated success flow navigates to LoginSelecao.aspx.
   async with page.expect_response(lambda r: r.request.method=='POST' and urlsplit(r.url).hostname=='govbahia.consigx.com.br' and urlsplit(r.url).path in ('/','/Default.aspx'),timeout=25000) as submitted:
    await page.locator('#Entrar').click(no_wait_after=True)
   response=await submitted.value
   await response.finished()
   await page.wait_for_load_state('domcontentloaded')
   await challenge(page);await dismiss_cookies(page)
  await report_step(on_step,22,'Confirmar resposta do login ConsigX')
  await inspect_login_notice(page,credentials)
  # Login navigation may land directly in an already selected agreement, or
  # return to the login form. Neither case should wait for a nonexistent grid.
  if await page.locator('#descricaoOrgaoLabel').is_visible():
   await assert_convenio(page)
  else:
   grid=page.locator('#gvOrgao')
   if not await grid.is_visible() and await page.locator('#txtSenha').is_visible():
    await challenge(page)
    raise Review('sessao_expirada','O portal voltou ao formulário de login. Autenticação não confirmada; confira o acesso no portal antes de repetir. Nenhuma consulta de CPF foi feita.',{'retryable_login':True})
   await grid.wait_for(state='visible',timeout=12000)
   await report_step(on_step,23,'Localizar botão do convênio TJBA')
   target=grid.locator('tr').filter(has_text=re.compile(r'TRIBUNAL\s+JUSTI[ÇC]A\s+DA\s+BAHIA',re.I))
   if await target.count()!=1:raise Review('sessao_expirada','Convênio TJBA não localizado de forma inequívoca.')
   entry=target.locator('[id^="gvOrgao_imgEntrar_"]')
   if await entry.count()!=1:raise Review('sessao_expirada','Botão de entrada no convênio TJBA não reconhecido.')
   await dismiss_cookies(page)
   await report_step(on_step,24,'Acionar entrada no convênio TJBA')
   await entry.click(timeout=10000,no_wait_after=True)
   await report_step(on_step,25,'Confirmar cabeçalho do convênio TJBA')
   # Wait for the actual success condition, including partial postbacks.
   # A full document navigation is not required for a successful selection.
   await page.locator('#descricaoOrgaoLabel').wait_for(state='visible',timeout=20000)
   await assert_convenio(page)
 await report_step(on_step,28,'Abrir formulário de consulta TJBA')
 await page.goto(BASE+PATH,wait_until='domcontentloaded',timeout=20000)
 await dismiss_cookies(page);await challenge(page)
 await page.locator(SEARCH).wait_for(state='visible',timeout=12000)
 await page.locator(CPF).wait_for(state='visible',timeout=12000)
 await assert_convenio(page)
 await report_step(on_step,32,'Login e convênio TJBA confirmados')
async def login_with_retries(page,credentials,on_step=None):
 # Keep one browser/context/proxy and its cookies throughout all attempts.
 # Retry only a plain return to the form, cleared fields or a transient timeout.
 async with asyncio.timeout(90):
  for attempt in range(1,4):
   async def progress(percent,label):
    await report_step(on_step,percent,f'{label} · login {attempt}/3')
   try:
    await login(page,credentials,on_step=progress)
    return
   except Exception as exc:
    invalid=isinstance(exc,Review) and exc.details.get('invalid_password') is True
    if invalid:
     if attempt>=2:raise
     await challenge(page)
     button=page.locator('#ucAjaxModalPopup1_btnConfirmarPopup')
     if await button.is_visible():await button.click(timeout=5000)
     await report_step(on_step,22,'Repetir login após aviso de senha inválida · tentativa 2/3')
     await asyncio.sleep(2)
     continue
    retryable=(isinstance(exc,Review) and exc.details.get('retryable_login') is True) or type(exc).__name__=='TimeoutError'
    if not retryable or attempt==3:raise
    # A timeout does not authorize ignoring a challenge or portal warning.
    await challenge(page)
    await inspect_login_notice(page,credentials)
    await report_step(on_step,22,f'Aguardar nova tentativa de login {attempt+1}/3')
    await asyncio.sleep(2)

async def prepare(page):
 await dismiss_cookies(page)
 if not await page.locator(CPF).is_visible() or not await page.locator(SEARCH).is_visible():
  back=page.locator('#body_voltarButton')
  if await back.is_visible():await back.click();await page.locator(SEARCH).wait_for(state='visible',timeout=12000)
  else:await page.goto(BASE+PATH,wait_until='domcontentloaded',timeout=20000)
 if not await page.locator(CPF).is_visible() or not await page.locator(SEARCH).is_visible():raise Review('sessao_expirada','A sessão do portal expirou ou o formulário não está disponível.')
 await assert_convenio(page)
async def choose_matricula(page):
 table=page.locator(GRID)
 if not await table.is_visible():return []
 headers=await table.locator('tr').first.locator('th,td').all_inner_texts()
 rowlocs=await table.locator('tr').all();rows=[];locs=[]
 for row in rowlocs[1:]:
  cells=await row.locator('td').all_inner_texts()
  if cells:rows.append(cells);locs.append(row)
 idx=active_index(headers,rows)
 if idx is None:raise Review('revisao_matricula','Matrículas encontradas sem uma única situação ativa verificável.',{'vinculos':[{'colunas':headers,'valores':r} for r in rows]})
 actions=locs[idx].get_by_role('link',name=re.compile(r'^selecionar$',re.I))
 if await actions.count()!=1:raise Review('revisao_matricula','Ação de seleção da matrícula ainda precisa ser validada.',{'vinculos':[{'colunas':headers,'valores':r} for r in rows]})
 await actions.click();return [{'matricula':r[headers.index(next(h for h in headers if norm(h)=='matricula'))] if any(norm(h)=='matricula' for h in headers) else None,'situacao':r[next(i for i,h in enumerate(headers) if norm(h) in ('situacao','situacao atual','situacao do vinculo','status'))]} for r in rows]
async def read_margin(page,selector):
 row=page.locator(selector)
 if not await row.is_visible():return None
 # Locate the real table header; do not assume that the fourth cell is availability.
 header= row.locator('xpath=ancestor::table[1]').locator('tr').first.locator('th,td')
 for cell in await header.all():
  if (await cell.get_attribute('colspan') or '1')!='1':raise Review('revisao_margens','Cabeçalho agrupado: validar as colunas de Margem Disponível.')
 headers=await header.all_inner_texts()
 index=available_index(headers);cells=await row.locator('td').all_inner_texts()
 if index>=len(cells):raise Review('revisao_margens','A estrutura das colunas de margem mudou.')
 expected='emprestimo' if selector==ROWS['emprestimo_disponivel'] else 'cartao'
 if not cells or expected not in norm(cells[0]):raise Review('revisao_margens','A verba da linha de margem não corresponde ao resultado esperado.')
 try:return parse_brl(cells[index])
 except ValueError:raise Review('revisao_margens','Não foi possível interpretar o valor da margem disponível.') from None
async def consult(page,cpf,on_step=None):
 await report_step(on_step,35,'Preparar formulário TJBA')
 await prepare(page)
 # Live validated: default Cartão returns both loan and card detail rows.
 # Preserve the portal's selection; no dropdown interaction or reload needed.
 await report_step(on_step,40,'Preparar pesquisa por CPF')
 matricula=page.locator('#body_matriculaTextBox')
 if await matricula.is_visible():await matricula.fill('')
 await report_step(on_step,45,'Preencher CPF no formulário TJBA')
 await page.locator(CPF).fill(normalize_cpf(cpf))
 await report_step(on_step,50,'Enviar pesquisa e aguardar retorno ConsigX')
 # Wait for an actual postback response, never accept old details from a previous CPF.
 try:
  async with page.expect_response(lambda r: r.request.method=='POST' and urlsplit(r.url).hostname=='govbahia.consigx.com.br',timeout=20000) as pending:
   await page.locator(SEARCH).click()
  response=await pending.value;await response.finished()
 except Exception:raise Review('erro','O portal não confirmou o envio da consulta. Nenhum resultado anterior foi reutilizado.') from None
 await page.wait_for_load_state('domcontentloaded')
 await page.wait_for_function("()=>window.Sys?.WebForms?.PageRequestManager?!Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack():document.readyState==='complete'",timeout=15000)
 await page.wait_for_function("""()=>{
 const visible=s=>{const e=document.querySelector(s);return !!e&&e.getClientRects().length>0};
 const body=document.body.innerText.toLowerCase();
 return visible('#body_servidorGridView')||visible('#body_rptMargens1_headerservico1_0')||visible('#txtSenha')||/servidor n[aã]o encontrado|nenhum servidor encontrado|cpf n[aã]o encontrado/.test(body);
 }""",timeout=15000)
 await challenge(page)
 if await page.locator('#txtSenha').is_visible():raise Review('sessao_expirada','A sessão do portal expirou durante a consulta.')
 text=norm(await page.locator('body').inner_text())
 if re.search(r'servidor nao encontrado|nenhum servidor encontrado|cpf nao encontrado',text):return {'status':'nao_encontrado','observacoes':'O portal informou que não encontrou esse CPF no convênio.'}
 await assert_convenio(page)
 await report_step(on_step,65,'Verificar vínculo e matrícula retornados')
 vinculos=await choose_matricula(page)
 await page.locator(ROWS['emprestimo_disponivel']).wait_for(state='visible',timeout=12000)
 await report_step(on_step,78,'Ler margens disponíveis e confirmar CPF')
 fields={k:await value(page,s) for k,s in FIELDS.items()}
 margins={k:await read_margin(page,s) for k,s in ROWS.items()}
 if not fields['matricula'] or not fields['situacao_atual']:raise Review('revisao_matricula','Resultado sem matrícula ou situação verificável.')
 # Where available, verify the returned CPF as well as the completed postback.
 returned=await value(page,RESULT_CPF)
 if not returned or normalize_cpf(returned)!=normalize_cpf(cpf):raise Review('erro','O CPF retornado pelo portal não corresponde à consulta.')
 return dict(nome=await value(page,'#body_clienteTextBox'),status='consultado' if all(v is not None for v in margins.values()) else 'revisao_margens',observacoes=None if all(v is not None for v in margins.values()) else 'Uma das margens não foi retornada pelo portal.',vinculos=vinculos,**fields,**margins)
def job_result(raw):
 status=raw['status'];result=dict(status='concluida' if status=='consultado' else 'nao_encontrado' if status=='nao_encontrado' else 'erro' if status=='erro' else 'revisao',tjba_status=status,resultado_tjba=raw,matricula=raw.get('matricula'),tipo_servidor=raw.get('tipo_servidor'),situacao_atual=raw.get('situacao_atual'),emprestimo_disponivel=raw.get('emprestimo_disponivel'),cartao_disponivel=raw.get('cartao_disponivel'),message=raw.get('observacoes'),progress=100,stage='Consulta TJBA finalizada')
 if raw.get('nome'):result['nome']=str(raw['nome'])[:160]
 return result
def failure_details(exc,page=None):
 # Inspect arbitrary exception text only for approved markers; never copy the text/trace.
 text=str(exc);codes=list(dict.fromkeys(re.findall(r'ERR_[A-Z0-9_]+',text)))
 code='CHROMIUM_AUSENTE' if 'Executable doesn' in text or 'playwright install' in text else 'NAVEGADOR_ENCERRADO' if re.search(r'target.*closed|browser.*closed|page.*closed',text,re.I) else ','.join(codes) if codes else 'SEM_CODIGO_REDE'
 route=None
 try:
  path=urlsplit(str(page.url)).path if page else ''
  if path in ('/','/LoginSelecao.aspx','/Inicial/Inicial.aspx',PATH,'/Margem/ConsultaMargemDados.aspx'):route=path
 except Exception:pass
 return {'tipo':type(exc).__name__,'codigo':code,'rota':route}
class Session:
 """One live browser per worker; owner-scoped session and bounded login retries."""
 def __init__(self):self.pw=None;self.browser=None;self.context=None;self.page=None;self.identity=None;self.blocked=None;self.last_used=0
 async def close(self):
  if self.browser:
   try:await self.browser.close()
   except Exception:pass
  if self.pw:
   try:await self.pw.stop()
   except Exception:pass
  self.pw=self.browser=self.context=self.page=None;self.identity=None
 async def close_idle(self):
  if self.browser and time.monotonic()-self.last_used>120:await self.close()
 async def run(self,job,credentials,on_progress):
  base=dict(cpf=normalize_cpf(job['cpf']),tipo_higienizacao='margem',provedor='tjba',data_consulta=datetime.now(timezone.utc).isoformat())
  percent=0;stage='Preparar execução TJBA'
  async def report(p,label):
   nonlocal percent,stage
   percent=p;stage=label;await on_progress(p,label)
  def failed(raw):
   result=job_result(raw);result['progress']=percent;result['stage']='Falha TJBA | '+stage;return result
  if not credentials or not credentials.get('enabled'):return failed(dict(base,status='sessao_expirada',observacoes='Configure o acesso TJBA e habilite a integração em Configurações.'))
  identity=(job['user_id'],credentials['revision'])
  if identity==self.blocked:return failed(dict(base,status='sessao_expirada',observacoes='Autenticação pausada após falha. Valide o acesso e salve novamente as configurações.'))
  try:
   if self.identity!=identity or not self.page or self.page.is_closed():
    await self.close();await report(5,'Carregar Playwright do robô TJBA')
    from playwright.async_api import async_playwright
    self.pw=await async_playwright().start()
    await report(8,'Iniciar Chromium na VPS')
    self.browser=await self.pw.chromium.launch(headless=True,args=list(CHROMIUM_ARGS),**launch_options())
    await report(10,'Criar contexto do navegador TJBA')
    self.context=await self.browser.new_context(accept_downloads=False,locale='pt-BR');self.page=await self.context.new_page();self.page.set_default_timeout(12000)
    await install_handlers(self.page)
    try:await login_with_retries(self.page,credentials,on_step=report)
    except Exception:self.blocked=identity;raise
    self.identity=identity
   raw=await consult(self.page,job['cpf'],on_step=report);await report(90,'Salvar margens TJBA')
   return job_result(dict(base,**raw))
  except Review as e:
   raw=dict(base,status=e.status,observacoes=e.message,diagnostico={'etapa':stage},**e.details)
   if e.status=='sessao_expirada':self.blocked=identity;await self.close()
   return failed(raw)
  except Exception as exc:
   diagnostic=failure_details(exc,self.page);diagnostic['etapa']=stage
   message=f"Falha em {stage}. Tipo: {diagnostic['tipo']}; código: {diagnostic['codigo']}."
   if diagnostic['codigo']=='CHROMIUM_AUSENTE':message+=' Execute Atualizar no instalador para instalar o Chromium.'
   elif diagnostic['codigo']=='NAVEGADOR_ENCERRADO':message+=' Confira a RAM e os logs do serviço na VPS.'
   raw=dict(base,status='erro',observacoes=message,diagnostico=diagnostic)
   await self.close();return failed(raw)
  finally:self.last_used=time.monotonic()
