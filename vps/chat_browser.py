"""Navigation helpers shared by the robot and the VPS diagnostic command."""
import asyncio, re, time
from urllib.parse import urlsplit
BANK_URL='https://www.bancodigimais.com.br/'
CHAT_HOST='widget.voltdigital.com.br'
CHAT_URL='https://widget.voltdigital.com.br/br/14603de1a63fa6c1331d69c278d6d32f2bbd825b28c5e4053e6418b24c7e761f/chat'
# The bank failed HTTP/2 on the VPS; use HTTP/1.1 over verified TLS.
CHROMIUM_ARGS=('--disable-dev-shm-usage','--disable-http2','--disable-quic')

class NavigationIssue(Exception):pass

def describe_error(exc):
    text=str(exc)
    codes=re.findall(r'(?:net::)?ERR_[A-Z0-9_]+',text)
    if codes:return ', '.join(dict.fromkeys(codes))
    if re.search(r'target.*closed|browser.*closed|page.*closed',text,re.I):return 'Navegador/página encerrado. Confira memória e logs do serviço.'
    # Never publish arbitrary browser errors: they may contain entered client data.
    return type(exc).__name__+' sem código de rede. Execute Diagnosticar robô no instalador.'

def check_access(text,status=None):
    if re.search(r'verify you are human|verifique.{0,30}human|checking your browser|just a moment|\bcaptcha\b|access denied|automated traffic|unusual traffic',text,re.I):
        raise NavigationIssue('O site exige verificação adicional ou recusou este navegador. Revisão humana necessária.')
    if status and status>=400:raise NavigationIssue(f'O site retornou HTTP {status}; verifique o acesso na VPS.')

async def body_text(page):
    return await page.locator('body').inner_text(timeout=5000)

async def open_bank(context,timeout=60000,report=None):
    page=await context.new_page();page.set_default_timeout(timeout)
    # Register before navigation, so delayed overlays cannot race the first click.
    for name in ['Fechar','Aceitar todos','Aceitar cookies','Rejeitar todos']:
        locator=page.get_by_role('button',name=name,exact=True)
        async def dismiss(target):await target.click()
        await page.add_locator_handler(locator,dismiss)
    if report:await report(10,'Abrir site do banco')
    response=await page.goto(BANK_URL,wait_until='domcontentloaded',timeout=timeout)
    check_access(await body_text(page),response.status if response else None)
    if report:await report(20,'Abrir widget do chat')
    return page

async def find_chat_scope(context,page):
    # Supported display forms: new tab, same tab, or widget iframe.
    candidates=[p for p in context.pages if p is not page]+[page]
    for candidate in candidates:
        if candidate.is_closed():continue
        parsed=urlsplit(candidate.url)
        if parsed.hostname not in ('www.bancodigimais.com.br','bancodigimais.com.br',CHAT_HOST):continue
        scopes=[candidate]
        if parsed.hostname!=CHAT_HOST:
            scopes=[]
        for frame in candidate.frames:
            if frame is candidate.main_frame:continue
            if urlsplit(frame.url).hostname==CHAT_HOST:scopes.append(frame)
        for scope in scopes:
            # Fast DOM presence checks; filling will still auto-wait for visibility.
            if await scope.locator('input:not([type="hidden"]):not([type="file"]):not([type="checkbox"])').count()>=2:
                return scope
            if await scope.get_by_role('button',name='Empréstimo consignado',exact=True).count():return scope
    return None

async def open_chat(context,page,timeout=60000):
    # A new-tab listener is not required; inspect legitimate UI destinations after the click.
    await page.locator('button.v-chat-button').click(timeout=timeout)
    deadline=time.monotonic()+timeout/1000
    while time.monotonic()<deadline:
        for target in context.pages:
            if target.is_closed():continue
            if urlsplit(target.url).hostname not in ('www.bancodigimais.com.br','bancodigimais.com.br',CHAT_HOST):continue
            if await target.locator('body').count():check_access(await body_text(target))
        scope=await find_chat_scope(context,page)
        if scope:return scope
        await asyncio.sleep(.2)
    raise NavigationIssue('O widget foi clicado, mas o formulário do chat não abriu em aba, página ou iframe.')



async def open_direct_chat(context,timeout=60000,report=None):
    """Use the same public chat destination opened by the bank widget."""
    page=await context.new_page();page.set_default_timeout(timeout)
    if report:await report(10,'Abrir chat direto do banco')
    response=await page.goto(CHAT_URL,wait_until='domcontentloaded',timeout=timeout)
    check_access(await body_text(page),response.status if response else None)
    if report:await report(20,'Aguardar formulário do chat')
    deadline=time.monotonic()+timeout/1000
    while time.monotonic()<deadline:
        check_access(await body_text(page))
        scope=await find_chat_scope(context,page)
        if scope:return scope
        await asyncio.sleep(.2)
    raise NavigationIssue('O chat direto abriu, mas não exibiu formulário ou menu no prazo esperado.')
