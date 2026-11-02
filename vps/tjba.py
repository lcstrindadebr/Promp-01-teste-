"""Read-only TJBA adapter. References require authenticated portal homologation.
Never reserve margin, make proposals, save browser state or log portal content/secrets.
"""
import asyncio,re,time,unicodedata
from decimal import Decimal,InvalidOperation
from datetime import datetime,timezone
from urllib.parse import urlsplit
BASE='https://govbahia.consigx.com.br'
PATH='/Margem/ConsultaMargem.aspx'
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
async def login(page,credentials):
 await page.goto(BASE+PATH,wait_until='domcontentloaded',timeout=25000)
 if await page.locator(CPF).is_visible():await assert_convenio(page);return
 await challenge(page)
 if urlsplit(page.url).hostname!='govbahia.consigx.com.br':raise Review('sessao_expirada','O portal redirecionou a autenticação; validar o fluxo.')
 if not await page.locator('#txtLogin').is_visible() or not await page.locator('#txtSenha').is_visible():raise Review('sessao_expirada','Tela de autenticação não reconhecida; validar o fluxo do portal.')
 await page.locator('#txtLogin').fill(credentials['username']);await page.locator('#txtSenha').fill(credentials['password'])
 await page.locator('#Entrar').click();await page.wait_for_load_state('domcontentloaded');await challenge(page)
 # Verified agreement selection grid. Match the row text, not its changing position.
 if await page.locator('#gvOrgao').is_visible():
  target=page.locator('#gvOrgao tr').filter(has_text=re.compile(r'TRIBUNAL JUSTICA DA BAHIA',re.I))
  if await target.count()!=1:raise Review('sessao_expirada','Convênio TJBA não localizado de forma inequívoca.')
  entry=target.locator('[id^="gvOrgao_imgEntrar_"]')
  if await entry.count()!=1:raise Review('sessao_expirada','Botão de entrada no convênio TJBA não reconhecido.')
  await entry.click();await page.wait_for_load_state('domcontentloaded')
 if not await page.locator(CPF).is_visible() or not await page.locator(SEARCH).is_visible():await page.goto(BASE+PATH,wait_until='domcontentloaded',timeout=20000)
 if not await page.locator(CPF).is_visible():raise Review('sessao_expirada','Login ou seleção do convênio requer validação. Confira as credenciais e o acesso TJBA.')
 await assert_convenio(page)
async def prepare(page):
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
async def consult(page,cpf):
 await prepare(page)
 verba=page.locator('#body_servicoDropDownList')
 if await verba.is_visible():
  labels=await verba.locator('option').all_inner_texts();matches=[label for label in labels if norm(label).startswith('emprestimo')]
  if len(matches)!=1:raise Review('revisao_margens','Verba de empréstimo não identificada de forma inequívoca.')
  await verba.select_option(label=matches[0]);await page.wait_for_load_state('domcontentloaded')
 matricula=page.locator('#body_matriculaTextBox')
 if await matricula.is_visible():await matricula.fill('')
 await page.locator(CPF).fill(normalize_cpf(cpf))
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
 vinculos=await choose_matricula(page)
 await page.locator(ROWS['emprestimo_disponivel']).wait_for(state='visible',timeout=12000)
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
class Session:
 """One live browser per worker; reuse only for the same owner and credential revision."""
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
  if not credentials or not credentials.get('enabled'):return job_result(dict(base,status='sessao_expirada',observacoes='Configure o acesso TJBA e habilite a integração após homologação em Configurações.'))
  identity=(job['user_id'],credentials['revision'])
  if identity==self.blocked:return job_result(dict(base,status='sessao_expirada',observacoes='Autenticação pausada após falha. Valide o acesso e salve novamente as credenciais antes de tentar.'))
  try:
   await on_progress(10,'Abrir consulta TJBA')
   if self.identity!=identity or not self.page or self.page.is_closed():
    await self.close()
    from playwright.async_api import async_playwright
    from chat_browser import CHROMIUM_ARGS
    self.pw=await async_playwright().start();self.browser=await self.pw.chromium.launch(headless=True,args=CHROMIUM_ARGS)
    self.context=await self.browser.new_context(accept_downloads=False);self.page=await self.context.new_page();self.page.set_default_timeout(12000)
    try:await login(self.page,credentials)
    except Exception:self.blocked=identity;raise
    self.identity=identity
   await on_progress(35,'Pesquisar CPF no TJBA');raw=await consult(self.page,job['cpf']);await on_progress(90,'Salvar margens TJBA')
   return job_result(dict(base,**raw))
  except Review as e:
   if e.status=='sessao_expirada':self.blocked=identity;await self.close()
   return job_result(dict(base,status=e.status,observacoes=e.message,**e.details))
  except Exception:
   await self.close();return job_result(dict(base,status='erro',observacoes='Falha ou tempo excedido no portal TJBA. Validar o fluxo antes de repetir.'))
  finally:self.last_used=time.monotonic()
