# ApoiarCred — instruções e revisão com localização no código

Revisão de 15/11/2026. Repositório `lcstrindadebr/Promp-01-teste-`, branch `apoiarcred-consultas-mvp`, commit `9955a723edd4145373175784e893ac96cafa961d`.

## Como usar este documento

Cada funcionalidade possui explicação, ponto de entrada e referências clicáveis para arquivo e linha. As linhas se referem ao commit acima. O catálogo SQL mostra todas as definições encontradas, incluindo redefinições de funções em migrações. A versão efetiva no banco depende das migrações aplicadas.

Esta é uma revisão estática de 226 arquivos textuais de autoria do projeto. A suíte completa não foi executada nesta revisão. Configuração sensível, bibliotecas de terceiros, imagens e planilhas binárias foram excluídas do conteúdo analisado. A revisão não comprova implantação ou disponibilidade de produção.

## Objetivo, entidades e arquitetura

O produto organiza importação de bases, consultas de saldo/parcela e margens, enriquecimento cadastral, simulação e trabalho comercial. Cliente, vínculo, consulta, campanha e oportunidade são entidades relacionadas. A navegação operacional parte de [dist/app.js · linha 262](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L262). O funil parte de [dist/crm.js · linha 339](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L339).

| Camada | Onde localizar | Papel |
| --- | --- | --- |
| Interface | [dist/index.html · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/index.html#L1) | HTML e ordem de carregamento dos scripts |
| Estilos | [dist/interface.css · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/interface.css#L1) e [dist/ux-crm.css · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/ux-crm.css#L1) | Apresentação do painel e CRM |
| Acesso aos dados | [dist/supabase.js · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L13) | Transporte, sessão, RPCs e sincronização |
| Gateway HTTP | [vps/api.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L16) | Recepção e encaminhamento à API transacional |
| Workers | [vps/worker.py · linha 338](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L338) | Inicialização dos executores e supervisores |
| Banco | [supabase/schema.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1) | Estrutura base e funções |
| Atualizações SQL | Seção de catálogo SQL deste documento | Definições e migrações incrementais |
| Publicação | [scripts/update-core.sh · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/update-core.sh#L1) | Instalação de código e serviços |

## Mapa funcional detalhado

### 1. Objetivo e navegação

A aplicação transforma cadastro e consultas assíncronas em oportunidades comerciais. A navegação organiza o acesso ao painel, clientes, campanhas e configurações.

| Componente | Localização exata |
| --- | --- |
| `function navigate` | [dist/app.js · linha 262](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L262) |
| `async function loadCrmClients` | [dist/crm.js · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L25) |
| `async function loadCrmPipeline` | [dist/crm.js · linha 339](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L339) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.crm_filter_clients` — [supabase/schema.sql · linha 2777](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2777) · [supabase/schema.sql · linha 2905](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2905) · [supabase/upgrade_crm_importacao.sql · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L95) · [supabase/upgrade_crm_kanban.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L52)
- `public.crm_filter_options` — [supabase/schema.sql · linha 2787](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2787) · [supabase/schema.sql · linha 2915](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2915) · [supabase/upgrade_crm_importacao.sql · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L105) · [supabase/upgrade_crm_kanban.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L62)
- `public.crm_registrar_exportacao` — [supabase/schema.sql · linha 3895](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3895) · [supabase/upgrade_crm_ficha_exportacoes.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L35)
- `public.crm_listar_etapas` — [supabase/schema.sql · linha 5287](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5287) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L93)
- `public.crm_salvar_etapa` — [supabase/schema.sql · linha 5298](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5298) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 104](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L104)
- `public.crm_mover_etapa` — [supabase/schema.sql · linha 5340](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5340) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L146)
- `public.crm_kanban` — [supabase/schema.sql · linha 5404](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5404) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L210)
- `public.crm_listar_exportacao` — [supabase/schema.sql · linha 5892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5892) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L2)
- `public.crm_convenios_exportacao` — [supabase/schema.sql · linha 5914](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5914) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L24)
- `public.crm_selecionar_etapa` — [supabase/schema.sql · linha 5953](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5953) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L63)
- `public.crm_acao_lote` — [supabase/schema.sql · linha 5975](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5975) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L85)

### 2. Login, logout e restauração

O formulário autentica no Supabase Auth. openPanel valida as permissões antes de abrir o painel. A restauração e renovação da sessão são caminhos separados; os timeouts podem ocorrer em qualquer uma dessas etapas.

| Componente | Localização exata |
| --- | --- |
| `$('#login').onsubmit` | [dist/supabase.js · linha 232](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L232) |
| `async function openPanel` | [dist/supabase.js · linha 196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L196) |
| `async function restoreSession` | [dist/supabase.js · linha 264](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L264) |
| `async function refreshSession` | [dist/supabase.js · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L27) |
| `async function signOut` | [dist/supabase.js · linha 252](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L252) |
| `function loginFailureMessage` | [dist/supabase.js · linha 187](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L187) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.my_access` — [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) · [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47)
- `public.my_access` — [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) · [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51)
- `public.create_individual_consulta` — [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) · [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114)
- `public.painel_consultas_sync` — [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) · [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) · [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) · [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) · [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) · [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1)
- `public.save_digimais_campaign_batch` — [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1)

### 3. Transporte do painel e isolamento de sessão

raw faz fetch com chave pública e timeout. sbRequest acrescenta JWT e trata sessão expirada. showLogin limpa estado compartilhado. Alterações nesses pontos afetam todos os módulos que usam o Supabase.

| Componente | Localização exata |
| --- | --- |
| `async function raw` | [dist/supabase.js · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L13) |
| `async function sbRequest` | [dist/supabase.js · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L32) |
| `function showLogin` | [dist/supabase.js · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L7) |
| `function saveSession` | [dist/supabase.js · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L12) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.my_access` — [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) · [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47)
- `public.my_access` — [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) · [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51)
- `public.create_individual_consulta` — [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) · [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114)
- `public.painel_consultas_sync` — [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) · [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) · [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) · [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) · [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) · [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1)
- `public.save_digimais_campaign_batch` — [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1)

### 4. Permissões, parceiros e cotas

my_access fornece o acesso efetivo. O frontend exibe permissões, mas a autorização também é aplicada no backend e SQL. Parceiros possuem serviços, modalidades, cotas e liberação de integrações.

| Componente | Localização exata |
| --- | --- |
| `async function refreshMyAccess` | [dist/supabase.js · linha 176](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L176) |
| `function assertCanSubmit` | [dist/partners.js · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L21) |
| `function applyAccessUi` | [dist/partners.js · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L51) |
| `def partner_admin` | [vps/api.py · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L58) |
| `def session_actor` | [vps/api.py · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L35) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.api_execute` — [supabase/schema.sql · linha 751](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L751) · [supabase/schema.sql · linha 947](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L947) · [supabase/schema.sql · linha 1291](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1291) · [supabase/schema.sql · linha 5624](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5624) · [supabase/schema.sql · linha 5784](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5784) · [supabase/schema.sql · linha 5848](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5848) · [supabase/upgrade_api.sql · linha 162](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L162) · [supabase/upgrade_crm_auditoria_e_totais.sql · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L122) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 430](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L430) · [supabase/upgrade_crm_permissoes_api.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L26) · [supabase/upgrade_partner_integrations.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L82) · [supabase/upgrade_partners.sql · linha 163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L163)
- `apoiarcred_private.my_access` — [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) · [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47)
- `public.my_access` — [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) · [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51)
- `public.create_individual_consulta` — [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) · [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114)
- `public.admin_partner_manage` — [supabase/schema.sql · linha 912](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L912) · [supabase/schema.sql · linha 1233](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1233) · [supabase/schema.sql · linha 2350](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2350) · [supabase/schema.sql · linha 2463](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2463) · [supabase/upgrade_partner_amigoz_access.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L27) · [supabase/upgrade_partner_integrations.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L24) · [supabase/upgrade_partner_trials_quota.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L62) · [supabase/upgrade_partners.sql · linha 128](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L128)
- `public.authorize_amigoz` — [supabase/schema.sql · linha 2511](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2511) · [supabase/upgrade_partner_amigoz_access.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L75)
- `public.finish_amigoz_import_job` — [supabase/schema.sql · linha 3393](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3393) · [supabase/upgrade_crm_import_auto.sql · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L215)
- `public.start_amigoz_individual` — [supabase/schema.sql · linha 3437](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3437) · [supabase/upgrade_amigoz_individual_history.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_individual_history.sql#L2)
- `public.painel_consultas_sync` — [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) · [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) · [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) · [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) · [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) · [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1)
- `apoiarcred_private.admin_digimais_access` — [supabase/schema.sql · linha 6203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6203) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L46)
- `public.admin_digimais_access` — [supabase/schema.sql · linha 6228](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6228) · [supabase/upgrade_digimais_partner_access.sql · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L71)
- `public.save_digimais_campaign_batch` — [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1)

### 5. Cadastro e consulta individual

add cria consulta individual por RPC. O serviço escolhido determina os campos exigidos. O resultado chega pela sincronização da fila, sem depender de manter uma chamada bancária aberta no navegador.

| Componente | Localização exata |
| --- | --- |
| `function selectedService` | [dist/app.js · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L4) |
| `function validate(` | [dist/app.js · linha 128](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L128) |
| `async function add(` | [dist/supabase.js · linha 169](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L169) |
| `function selectedConvenio` | [dist/tjba.js · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L2) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.my_access` — [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) · [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47)
- `public.my_access` — [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) · [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51)
- `public.create_individual_consulta` — [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) · [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114)
- `public.manage_consigx_access` — [supabase/schema.sql · linha 1739](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1739) · [supabase/schema.sql · linha 2193](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2193) · [supabase/upgrade_consigx_access_editor.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx_access_editor.sql#L3) · [supabase/upgrade_fourth_robot.sql · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L40)
- `public.painel_consultas_sync` — [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) · [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) · [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) · [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) · [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) · [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1)
- `public.save_digimais_campaign_batch` — [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1)

### 6. Criação de campanhas Digi+ e ConsigX

createCampaign monta o lote e seleciona a RPC por serviço. Digi+ com mais de 100 itens usa envio em blocos e conserva a posição para retomada na sessão do navegador.

| Componente | Localização exata |
| --- | --- |
| `async function createCampaign` | [dist/supabase.js · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L41) |
| `function drawCreationStep` | [dist/workspace.js · linha 236](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L236) |
| `function syncQueryContext` | [dist/workspace.js · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L210) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.set_campaign_paused` — [supabase/schema.sql · linha 434](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L434) · [supabase/upgrade_campaign_ux.sql · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L7)
- `public.set_campaign_paused` — [supabase/schema.sql · linha 446](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L446) · [supabase/upgrade_campaign_ux.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L19)
- `apoiarcred_private.my_access` — [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) · [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47)
- `public.my_access` — [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) · [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51)
- `public.create_individual_consulta` — [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) · [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114)
- `public.painel_consultas_sync` — [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) · [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) · [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) · [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) · [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) · [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1)
- `public.save_digimais_campaign_batch` — [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1)

### 7. Pausa, andamento e previsão das campanhas

A fase visual distingue espera, execução, pausa e conclusão. A previsão usa conclusões recentes da própria campanha e amostra mínima. Pausar uma campanha e matar executores são operações distintas.

| Componente | Localização exata |
| --- | --- |
| `function campaignPhase(` | [dist/workspace.js · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L8) |
| `function campaignPhaseLabel` | [dist/workspace.js · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L9) |
| `function campaignEta` | [dist/workspace.js · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L10) |
| `function renderCampaignList` | [dist/workspace.js · linha 124](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L124) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.set_campaign_paused` — [supabase/schema.sql · linha 434](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L434) · [supabase/upgrade_campaign_ux.sql · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L7)
- `public.set_campaign_paused` — [supabase/schema.sql · linha 446](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L446) · [supabase/upgrade_campaign_ux.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L19)

### 8. Retentativas e exclusão de consultas

retryCampaign reenvia falhas pelas RPCs específicas. deleteConsultation controla exclusão pelo painel. A revisão de uma mudança deve verificar efeitos no histórico, fila e resultados parciais.

| Componente | Localização exata |
| --- | --- |
| `async function retryCampaign` | [dist/supabase.js · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L80) |
| `async function deleteConsultation` | [dist/exclusao.js · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/exclusao.js#L3) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.my_access` — [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) · [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47)
- `public.my_access` — [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) · [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51)
- `public.create_individual_consulta` — [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) · [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114)
- `public.painel_consultas_sync` — [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) · [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) · [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) · [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) · [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) · [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1)
- `public.save_digimais_campaign_batch` — [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1)

### 9. Leitura de planilhas e classificação

O parser de importação e a validação de cabeçalhos/classificação ficam no frontend. A importação cadastral tem leitor próprio e modelos dependentes do convênio.

| Componente | Localização exata |
| --- | --- |
| `function csvParse` | [dist/app.js · linha 134](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L134) |
| `function validateImportClassification` | [dist/app.js · linha 152](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L152) |
| `async function crmReadClientFile` | [dist/crm-import.js · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L74) |
| `function crmAgreementTemplate` | [dist/crm-import.js · linha 191](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L191) |
| `function crmAgreementWorkbook` | [dist/crm-import.js · linha 209](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L209) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.crm_preview_import` — [supabase/schema.sql · linha 4433](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4433) · [supabase/upgrade_crm_import_preview.sql · linha 190](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L190) · [supabase/upgrade_crm_import_timeout.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_timeout.sql#L2)
- `public.crm_import_history` — [supabase/schema.sql · linha 4474](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4474) · [supabase/upgrade_crm_import_preview.sql · linha 231](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L231)

### 10. Prévia, confirmação e recuperação de importação

O cadastro de base tem prévia e confirmação. crmConfirmWithReceipt consulta o recibo/histórico após falha, e crmConfirmImportBatches divide a operação em blocos. Isso deve ser preservado em alterações de timeout para evitar duplicação.

| Componente | Localização exata |
| --- | --- |
| `async function crmOpenClientImport` | [dist/crm-import.js · linha 239](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L239) |
| `async function crmConfirmWithReceipt` | [dist/crm-import.js · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L1) |
| `async function crmConfirmImportBatches` | [dist/crm-import.js · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L22) |
| `async function crmOpenImportHistory` | [dist/crm-import.js · linha 547](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L547) |
| `async function crmGetImportCatalog` | [dist/crm-import.js · linha 490](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L490) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.crm_preview_import` — [supabase/schema.sql · linha 4433](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4433) · [supabase/upgrade_crm_import_preview.sql · linha 190](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L190) · [supabase/upgrade_crm_import_timeout.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_timeout.sql#L2)
- `public.crm_import_history` — [supabase/schema.sql · linha 4474](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4474) · [supabase/upgrade_crm_import_preview.sql · linha 231](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L231)

### 11. Clientes, vínculos, ficha e histórico

O CRM lista clientes e vínculos, abre ficha detalhada e mostra histórico. CPF de cliente e IDs de oportunidade têm finalidades diferentes; uma pessoa pode possuir várias oportunidades.

| Componente | Localização exata |
| --- | --- |
| `async function loadCrmClients` | [dist/crm.js · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L25) |
| `async function loadCrmLinks` | [dist/crm.js · linha 70](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L70) |
| `async function loadCrmHistory` | [dist/crm.js · linha 152](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L152) |
| `async function crmOpenClientProfile` | [dist/crm.js · linha 1054](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L1054) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.crm_filter_clients` — [supabase/schema.sql · linha 2777](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2777) · [supabase/schema.sql · linha 2905](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2905) · [supabase/upgrade_crm_importacao.sql · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L95) · [supabase/upgrade_crm_kanban.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L52)
- `public.crm_filter_options` — [supabase/schema.sql · linha 2787](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2787) · [supabase/schema.sql · linha 2915](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2915) · [supabase/upgrade_crm_importacao.sql · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L105) · [supabase/upgrade_crm_kanban.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L62)
- `public.crm_registrar_exportacao` — [supabase/schema.sql · linha 3895](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3895) · [supabase/upgrade_crm_ficha_exportacoes.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L35)
- `public.crm_listar_etapas` — [supabase/schema.sql · linha 5287](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5287) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L93)
- `public.crm_salvar_etapa` — [supabase/schema.sql · linha 5298](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5298) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 104](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L104)
- `public.crm_mover_etapa` — [supabase/schema.sql · linha 5340](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5340) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L146)
- `public.crm_kanban` — [supabase/schema.sql · linha 5404](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5404) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L210)
- `public.crm_listar_exportacao` — [supabase/schema.sql · linha 5892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5892) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L2)
- `public.crm_convenios_exportacao` — [supabase/schema.sql · linha 5914](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5914) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L24)
- `public.crm_selecionar_etapa` — [supabase/schema.sql · linha 5953](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5953) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L63)
- `public.crm_acao_lote` — [supabase/schema.sql · linha 5975](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5975) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L85)

### 12. Funil, etapas e operações em lote

loadCrmPipeline renderiza o Kanban a partir do banco. As ações individuais e em lote enviam IDs e contexto de etapa. A apresentação financeira dos cartões é implementada separadamente.

| Componente | Localização exata |
| --- | --- |
| `async function loadCrmPipeline` | [dist/crm.js · linha 339](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L339) |
| `async function crmMoveOpportunity` | [dist/crm.js · linha 908](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L908) |
| `async function crmApplyBulk` | [dist/crm.js · linha 317](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L317) |
| `function crmOpportunityCard` | [dist/crm.js · linha 936](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L936) |
| `function crmCardFinance` | [dist/crm.js · linha 970](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L970) |
| `function crmEditOpportunity` | [dist/crm.js · linha 1183](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L1183) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.crm_filter_clients` — [supabase/schema.sql · linha 2777](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2777) · [supabase/schema.sql · linha 2905](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2905) · [supabase/upgrade_crm_importacao.sql · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L95) · [supabase/upgrade_crm_kanban.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L52)
- `public.crm_filter_options` — [supabase/schema.sql · linha 2787](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2787) · [supabase/schema.sql · linha 2915](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2915) · [supabase/upgrade_crm_importacao.sql · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L105) · [supabase/upgrade_crm_kanban.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L62)
- `public.crm_registrar_exportacao` — [supabase/schema.sql · linha 3895](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3895) · [supabase/upgrade_crm_ficha_exportacoes.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L35)
- `public.crm_listar_etapas` — [supabase/schema.sql · linha 5287](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5287) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L93)
- `public.crm_salvar_etapa` — [supabase/schema.sql · linha 5298](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5298) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 104](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L104)
- `public.crm_mover_etapa` — [supabase/schema.sql · linha 5340](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5340) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L146)
- `public.crm_kanban` — [supabase/schema.sql · linha 5404](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5404) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L210)
- `public.crm_listar_exportacao` — [supabase/schema.sql · linha 5892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5892) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L2)
- `public.crm_convenios_exportacao` — [supabase/schema.sql · linha 5914](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5914) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L24)
- `public.crm_selecionar_etapa` — [supabase/schema.sql · linha 5953](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5953) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L63)
- `public.crm_acao_lote` — [supabase/schema.sql · linha 5975](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5975) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L85)

### 13. Exportação e reexportação

A geração de arquivo e o registro da exportação têm responsabilidades próprias. Os IDs efetivamente incluídos devem orientar a movimentação de etapa. CSV protege células potencialmente interpretadas como fórmulas.

| Componente | Localização exata |
| --- | --- |
| `async function crmDownloadOpportunities` | [dist/crm.js · linha 618](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L618) |
| `async function crmExportPageRows` | [dist/crm.js · linha 584](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L584) |
| `function crmOfferReexport` | [dist/crm.js · linha 601](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L601) |
| `async function crmExportClients` | [dist/crm.js · linha 768](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L768) |
| `function crmCsvCell` | [dist/crm.js · linha 764](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L764) |
| `async function exportResults` | [dist/app.js · linha 239](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L239) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.crm_filter_clients` — [supabase/schema.sql · linha 2777](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2777) · [supabase/schema.sql · linha 2905](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2905) · [supabase/upgrade_crm_importacao.sql · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L95) · [supabase/upgrade_crm_kanban.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L52)
- `public.crm_filter_options` — [supabase/schema.sql · linha 2787](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2787) · [supabase/schema.sql · linha 2915](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2915) · [supabase/upgrade_crm_importacao.sql · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L105) · [supabase/upgrade_crm_kanban.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L62)
- `public.crm_registrar_exportacao` — [supabase/schema.sql · linha 3895](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3895) · [supabase/upgrade_crm_ficha_exportacoes.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L35)
- `public.crm_listar_etapas` — [supabase/schema.sql · linha 5287](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5287) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L93)
- `public.crm_salvar_etapa` — [supabase/schema.sql · linha 5298](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5298) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 104](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L104)
- `public.crm_mover_etapa` — [supabase/schema.sql · linha 5340](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5340) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L146)
- `public.crm_kanban` — [supabase/schema.sql · linha 5404](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5404) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L210)
- `public.crm_listar_exportacao` — [supabase/schema.sql · linha 5892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5892) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L2)
- `public.crm_convenios_exportacao` — [supabase/schema.sql · linha 5914](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5914) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L24)
- `public.crm_selecionar_etapa` — [supabase/schema.sql · linha 5953](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5953) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L63)
- `public.crm_acao_lote` — [supabase/schema.sql · linha 5975](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5975) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L85)

### 14. Reaproveitamento de campanhas

campaign-reuse.js implementa consulta de histórico e apresentação paginada de candidatos. Verificar filtros e contexto de conta antes de mudar o reaproveitamento.

| Componente | Localização exata |
| --- | --- |
| `async function history` | [dist/campaign-reuse.js · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/campaign-reuse.js#L26) |
| `async function loadPage` | [dist/campaign-reuse.js · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/campaign-reuse.js#L80) |

### 15. Sincronização incremental e cache em memória

O painel conserva snapshot e mapa local, sincroniza páginas e aplica espera crescente em falhas. cloudSyncVisible limita trabalho conforme a tela e visibilidade. Esse mecanismo depende do backend para atualizar dados.

| Componente | Localização exata |
| --- | --- |
| `async function syncCloudPages` | [dist/supabase.js · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L111) |
| `function loadCloud` | [dist/supabase.js · linha 143](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L143) |
| `function cloudSyncVisible` | [dist/supabase.js · linha 99](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L99) |
| `async function loadConsultationLogDetail` | [dist/supabase.js · linha 90](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L90) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.my_access` — [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) · [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47)
- `public.my_access` — [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) · [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51)
- `public.create_individual_consulta` — [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) · [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114)
- `public.painel_consultas_sync` — [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) · [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) · [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) · [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) · [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) · [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1)
- `public.save_digimais_campaign_batch` — [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1)

### 16. Logs e diagnóstico no painel

O log de consultas realizadas é filtrado e pode ser baixado. O detalhe pode ser carregado sob demanda. DigiMais API possui visualização própria.

| Componente | Localização exata |
| --- | --- |
| `function consultationWasPerformed` | [dist/app.js · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L16) |
| `function consultationLogRecords` | [dist/app.js · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L19) |
| `function downloadConsultationLog` | [dist/app.js · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L25) |
| `async function downloadRowConsultationLog` | [dist/workspace.js · linha 87](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L87) |
| `async function renderDigiApiLogs` | [dist/digimais-pilot.js · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L81) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.set_campaign_paused` — [supabase/schema.sql · linha 434](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L434) · [supabase/upgrade_campaign_ux.sql · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L7)
- `public.set_campaign_paused` — [supabase/schema.sql · linha 446](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L446) · [supabase/upgrade_campaign_ux.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L19)
- `apoiarcred_private.manage_digimais_pilot` — [supabase/schema.sql · linha 4613](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4613) · [supabase/upgrade_digimais_api_campaign_switch.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_switch.sql#L1) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L3) · [supabase/upgrade_digimais_api_concurrency_50.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L12) · [supabase/upgrade_digimais_api_pilot.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L19) · [supabase/upgrade_digimais_robot_handoff.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_robot_handoff.sql#L4)
- `public.manage_digimais_pilot` — [supabase/schema.sql · linha 4635](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4635) · [supabase/upgrade_digimais_api_pilot.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L34)

### 17. Gateway HTTP público

O servidor Python limita e interpreta requisições e encaminha a lógica da API V1 à RPC api_execute. Alterar uma rota frequentemente exige editar Python, SQL e OpenAPI.

| Componente | Localização exata |
| --- | --- |
| `def rpc(` | [vps/api.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L16) |
| `class Server` | [vps/api.py · linha 200](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L200) |
| `class Handler` | [vps/api.py · linha 214](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L214) |
| `MAX_BODY=` | [vps/api.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L7) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.api_execute` — [supabase/schema.sql · linha 751](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L751) · [supabase/schema.sql · linha 947](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L947) · [supabase/schema.sql · linha 1291](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1291) · [supabase/schema.sql · linha 5624](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5624) · [supabase/schema.sql · linha 5784](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5784) · [supabase/schema.sql · linha 5848](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5848) · [supabase/upgrade_api.sql · linha 162](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L162) · [supabase/upgrade_crm_auditoria_e_totais.sql · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L122) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 430](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L430) · [supabase/upgrade_crm_permissoes_api.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L26) · [supabase/upgrade_partner_integrations.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L82) · [supabase/upgrade_partners.sql · linha 163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L163)
- `public.admin_partner_manage` — [supabase/schema.sql · linha 912](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L912) · [supabase/schema.sql · linha 1233](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1233) · [supabase/schema.sql · linha 2350](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2350) · [supabase/schema.sql · linha 2463](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2463) · [supabase/upgrade_partner_amigoz_access.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L27) · [supabase/upgrade_partner_integrations.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L24) · [supabase/upgrade_partner_trials_quota.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L62) · [supabase/upgrade_partners.sql · linha 128](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L128)
- `public.authorize_amigoz` — [supabase/schema.sql · linha 2511](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2511) · [supabase/upgrade_partner_amigoz_access.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L75)
- `public.finish_amigoz_import_job` — [supabase/schema.sql · linha 3393](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3393) · [supabase/upgrade_crm_import_auto.sql · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L215)
- `public.start_amigoz_individual` — [supabase/schema.sql · linha 3437](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3437) · [supabase/upgrade_amigoz_individual_history.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_individual_history.sql#L2)

### 18. Tokens e documentação de integração

A UI cria, lista e revoga tokens por manage_api_tokens. Os tokens externos da API têm escopos e são diferentes do JWT de sessão usado na administração. O contrato completo está em openapi.json.

| Componente | Localização exata |
| --- | --- |
| `async function loadApiTokens` | [dist/settings.js · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L26) |
| `async function loadApiDocs` | [dist/settings.js · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L45) |
| `function renderApiRoute` | [dist/settings.js · linha 76](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L76) |
| `def session_actor` | [vps/api.py · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L35) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.manage_api_tokens` — [supabase/schema.sql · linha 584](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L584) · [supabase/schema.sql · linha 1267](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1267) · [supabase/schema.sql · linha 5824](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5824) · [supabase/upgrade_api.sql · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L23) · [supabase/upgrade_crm_permissoes_api.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L2) · [supabase/upgrade_partner_integrations.sql · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L58)
- `public.manage_api_tokens` — [supabase/schema.sql · linha 609](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L609) · [supabase/upgrade_api.sql · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L48)
- `public.api_execute` — [supabase/schema.sql · linha 751](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L751) · [supabase/schema.sql · linha 947](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L947) · [supabase/schema.sql · linha 1291](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1291) · [supabase/schema.sql · linha 5624](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5624) · [supabase/schema.sql · linha 5784](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5784) · [supabase/schema.sql · linha 5848](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5848) · [supabase/upgrade_api.sql · linha 162](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L162) · [supabase/upgrade_crm_auditoria_e_totais.sql · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L122) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 430](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L430) · [supabase/upgrade_crm_permissoes_api.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L26) · [supabase/upgrade_partner_integrations.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L82) · [supabase/upgrade_partners.sql · linha 163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L163)
- `public.admin_partner_manage` — [supabase/schema.sql · linha 912](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L912) · [supabase/schema.sql · linha 1233](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1233) · [supabase/schema.sql · linha 2350](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2350) · [supabase/schema.sql · linha 2463](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2463) · [supabase/upgrade_partner_amigoz_access.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L27) · [supabase/upgrade_partner_integrations.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L24) · [supabase/upgrade_partner_trials_quota.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L62) · [supabase/upgrade_partners.sql · linha 128](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L128)
- `public.authorize_amigoz` — [supabase/schema.sql · linha 2511](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2511) · [supabase/upgrade_partner_amigoz_access.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L75)
- `public.finish_amigoz_import_job` — [supabase/schema.sql · linha 3393](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3393) · [supabase/upgrade_crm_import_auto.sql · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L215)
- `public.start_amigoz_individual` — [supabase/schema.sql · linha 3437](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3437) · [supabase/upgrade_amigoz_individual_history.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_individual_history.sql#L2)

### 19. API administrativa

A administração usa sessão autenticada e autorização no servidor. Há controladores para parceiros, Amigoz e configuração MinIO.

| Componente | Localização exata |
| --- | --- |
| `def partner_admin` | [vps/api.py · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L58) |
| `def amigoz_admin` | [vps/api.py · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L123) |
| `def minio_admin` | [vps/api.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L43) |
| `async function partnerRequest` | [dist/partners.js · linha 86](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L86) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.api_execute` — [supabase/schema.sql · linha 751](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L751) · [supabase/schema.sql · linha 947](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L947) · [supabase/schema.sql · linha 1291](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1291) · [supabase/schema.sql · linha 5624](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5624) · [supabase/schema.sql · linha 5784](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5784) · [supabase/schema.sql · linha 5848](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5848) · [supabase/upgrade_api.sql · linha 162](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L162) · [supabase/upgrade_crm_auditoria_e_totais.sql · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L122) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 430](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L430) · [supabase/upgrade_crm_permissoes_api.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L26) · [supabase/upgrade_partner_integrations.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L82) · [supabase/upgrade_partners.sql · linha 163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L163)
- `public.admin_partner_manage` — [supabase/schema.sql · linha 912](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L912) · [supabase/schema.sql · linha 1233](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1233) · [supabase/schema.sql · linha 2350](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2350) · [supabase/schema.sql · linha 2463](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2463) · [supabase/upgrade_partner_amigoz_access.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L27) · [supabase/upgrade_partner_integrations.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L24) · [supabase/upgrade_partner_trials_quota.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L62) · [supabase/upgrade_partners.sql · linha 128](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L128)
- `public.authorize_amigoz` — [supabase/schema.sql · linha 2511](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2511) · [supabase/upgrade_partner_amigoz_access.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L75)
- `public.finish_amigoz_import_job` — [supabase/schema.sql · linha 3393](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3393) · [supabase/upgrade_crm_import_auto.sql · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L215)
- `public.start_amigoz_individual` — [supabase/schema.sql · linha 3437](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3437) · [supabase/upgrade_amigoz_individual_history.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_individual_history.sql#L2)
- `apoiarcred_private.admin_digimais_access` — [supabase/schema.sql · linha 6203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6203) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L46)
- `public.admin_digimais_access` — [supabase/schema.sql · linha 6228](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6228) · [supabase/upgrade_digimais_partner_access.sql · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L71)

### 20. Orquestração dos robôs

main_async inicia slots, telemetria, controle de capacidade e supervisor de API. dispatch_robot_jobs distribui tarefas elegíveis, e robot_loop executa e persiste resultados.

| Componente | Localização exata |
| --- | --- |
| `async def main_async` | [vps/worker.py · linha 338](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L338) |
| `async def dispatch_robot_jobs` | [vps/worker.py · linha 131](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L131) |
| `async def robot_loop` | [vps/worker.py · linha 158](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L158) |
| `class RobotCapacity` | [vps/worker.py · linha 223](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L223) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.get_tjba_credentials` — [supabase/schema.sql · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L284) · [supabase/upgrade_tjba.sql · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L103)
- `public.get_tjba_credentials` — [supabase/schema.sql · linha 295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L295) · [supabase/upgrade_tjba.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L114)
- `apoiarcred_private.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1680](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1680) · [supabase/upgrade_shared_robots.sql · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L68)
- `public.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1687](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1687) · [supabase/upgrade_shared_robots.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L75)
- `public.claim_tjba_job_for_robot` — [supabase/schema.sql · linha 1724](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1724) · [supabase/upgrade_shared_robots.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L112)
- `public.claim_consulta_job_for_robot` — [supabase/schema.sql · linha 1820](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1820) · [supabase/schema.sql · linha 2250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2250) · [supabase/schema.sql · linha 4670](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4670) · [supabase/upgrade_digimais_api_pilot.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L69) · [supabase/upgrade_fourth_robot.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L97) · [supabase/upgrade_robot_log_slots.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_robot_log_slots.sql#L4)
- `public.get_digimais_api_config` — [supabase/schema.sql · linha 4648](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4648) · [supabase/upgrade_digimais_api_pilot.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L47)
- `public.claim_consulta_job_for_api` — [supabase/schema.sql · linha 4651](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4651) · [supabase/schema.sql · linha 6182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6182) · [supabase/upgrade_digimais_api_campaign_pause.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_pause.sql#L2) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L29) · [supabase/upgrade_digimais_api_concurrency_50.sql · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L38) · [supabase/upgrade_digimais_api_pilot.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L25)

### 21. Progresso, checkpoints e recuperação

process_digimais e process_tjba desacoplam gravação de progresso da navegação. Checkpoints e resultado final precisam permanecer coerentes. O resultado pendente em memória fica vulnerável a encerramento forçado.

| Componente | Localização exata |
| --- | --- |
| `async def process_digimais` | [vps/worker.py · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L19) |
| `async def process_tjba` | [vps/worker.py · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L50) |
| `async def run_with_recovery` | [vps/worker.py · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L111) |
| `def request(` | [vps/worker.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L11) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.get_tjba_credentials` — [supabase/schema.sql · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L284) · [supabase/upgrade_tjba.sql · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L103)
- `public.get_tjba_credentials` — [supabase/schema.sql · linha 295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L295) · [supabase/upgrade_tjba.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L114)
- `apoiarcred_private.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1680](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1680) · [supabase/upgrade_shared_robots.sql · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L68)
- `public.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1687](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1687) · [supabase/upgrade_shared_robots.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L75)
- `public.claim_tjba_job_for_robot` — [supabase/schema.sql · linha 1724](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1724) · [supabase/upgrade_shared_robots.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L112)
- `public.claim_consulta_job_for_robot` — [supabase/schema.sql · linha 1820](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1820) · [supabase/schema.sql · linha 2250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2250) · [supabase/schema.sql · linha 4670](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4670) · [supabase/upgrade_digimais_api_pilot.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L69) · [supabase/upgrade_fourth_robot.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L97) · [supabase/upgrade_robot_log_slots.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_robot_log_slots.sql#L4)
- `public.get_digimais_api_config` — [supabase/schema.sql · linha 4648](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4648) · [supabase/upgrade_digimais_api_pilot.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L47)
- `public.claim_consulta_job_for_api` — [supabase/schema.sql · linha 4651](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4651) · [supabase/schema.sql · linha 6182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6182) · [supabase/upgrade_digimais_api_campaign_pause.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_pause.sql#L2) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L29) · [supabase/upgrade_digimais_api_concurrency_50.sql · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L38) · [supabase/upgrade_digimais_api_pilot.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L25)

### 22. Robô Digi+ por navegador

DigiSession controla ciclo de sessão. run_once realiza uma consulta, run_with_alternate_route trata outra rota e run coordena saldo/parcela. parse_response transforma mensagens em resultado estruturado.

| Componente | Localização exata |
| --- | --- |
| `class DigiSession` | [vps/robot.py · linha 90](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L90) |
| `def parse_response` | [vps/robot.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L15) |
| `async def run_once` | [vps/robot.py · linha 149](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L149) |
| `async def run_with_alternate_route` | [vps/robot.py · linha 254](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L254) |
| `async def run(` | [vps/robot.py · linha 132](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L132) |

### 23. Navegação e abertura de chat Digi+

chat_browser.py concentra abertura de portal/chat e diagnóstico de navegação. Uma falha de transporte deve ser tratada antes de interpretar mensagens como resultado comercial.

| Componente | Localização exata |
| --- | --- |
| `async def open_bank` | [vps/chat_browser.py · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L32) |
| `async def open_chat` | [vps/chat_browser.py · linha 66](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L66) |
| `async def open_direct_chat` | [vps/chat_browser.py · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L82) |
| `def check_access` | [vps/chat_browser.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L24) |

### 24. DigiMais por API e concorrência

ApiSession executa o fluxo externo. api_supervisor inicia slots e api_loop reserva e finaliza trabalhos. O teto é 100 no código, com controle de capacidade e permissões. O teto não representa homologação de carga sustentada.

| Componente | Localização exata |
| --- | --- |
| `class ApiSession` | [vps/digimais_api.py · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L74) |
| `def parse_result` | [vps/digimais_api.py · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L62) |
| `async def api_supervisor` | [vps/worker.py · linha 320](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L320) |
| `async def api_loop` | [vps/worker.py · linha 285](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L285) |
| `class ApiCapacity` | [vps/worker.py · linha 262](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L262) |
| `DIGIMAIS_API_MAX_CONCURRENCY` | [vps/robot_metrics.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L7) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.get_tjba_credentials` — [supabase/schema.sql · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L284) · [supabase/upgrade_tjba.sql · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L103)
- `public.get_tjba_credentials` — [supabase/schema.sql · linha 295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L295) · [supabase/upgrade_tjba.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L114)
- `apoiarcred_private.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1680](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1680) · [supabase/upgrade_shared_robots.sql · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L68)
- `public.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1687](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1687) · [supabase/upgrade_shared_robots.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L75)
- `public.claim_tjba_job_for_robot` — [supabase/schema.sql · linha 1724](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1724) · [supabase/upgrade_shared_robots.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L112)
- `public.claim_consulta_job_for_robot` — [supabase/schema.sql · linha 1820](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1820) · [supabase/schema.sql · linha 2250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2250) · [supabase/schema.sql · linha 4670](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4670) · [supabase/upgrade_digimais_api_pilot.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L69) · [supabase/upgrade_fourth_robot.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L97) · [supabase/upgrade_robot_log_slots.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_robot_log_slots.sql#L4)
- `public.get_digimais_api_config` — [supabase/schema.sql · linha 4648](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4648) · [supabase/upgrade_digimais_api_pilot.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L47)
- `public.claim_consulta_job_for_api` — [supabase/schema.sql · linha 4651](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4651) · [supabase/schema.sql · linha 6182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6182) · [supabase/upgrade_digimais_api_campaign_pause.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_pause.sql#L2) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L29) · [supabase/upgrade_digimais_api_concurrency_50.sql · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L38) · [supabase/upgrade_digimais_api_pilot.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L25)

### 25. Preferência API/robô e handoff

O painel salva modalidade, pausa e concorrência via manage_digimais_pilot. A liberação por parceiro é separada. O handoff do worker precisa preservar contexto e tentativa ao devolver trabalho ao robô.

| Componente | Localização exata |
| --- | --- |
| `async function loadDigiPilot` | [dist/digimais-pilot.js · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L25) |
| `async function loadPartnerDigiAccess` | [dist/partners.js · linha 150](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L150) |
| `def digimais_api_handoff` | [vps/worker.py · linha 267](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L267) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.get_tjba_credentials` — [supabase/schema.sql · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L284) · [supabase/upgrade_tjba.sql · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L103)
- `public.get_tjba_credentials` — [supabase/schema.sql · linha 295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L295) · [supabase/upgrade_tjba.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L114)
- `apoiarcred_private.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1680](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1680) · [supabase/upgrade_shared_robots.sql · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L68)
- `public.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1687](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1687) · [supabase/upgrade_shared_robots.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L75)
- `public.claim_tjba_job_for_robot` — [supabase/schema.sql · linha 1724](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1724) · [supabase/upgrade_shared_robots.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L112)
- `public.claim_consulta_job_for_robot` — [supabase/schema.sql · linha 1820](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1820) · [supabase/schema.sql · linha 2250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2250) · [supabase/schema.sql · linha 4670](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4670) · [supabase/upgrade_digimais_api_pilot.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L69) · [supabase/upgrade_fourth_robot.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L97) · [supabase/upgrade_robot_log_slots.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_robot_log_slots.sql#L4)
- `apoiarcred_private.manage_digimais_pilot` — [supabase/schema.sql · linha 4613](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4613) · [supabase/upgrade_digimais_api_campaign_switch.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_switch.sql#L1) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L3) · [supabase/upgrade_digimais_api_concurrency_50.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L12) · [supabase/upgrade_digimais_api_pilot.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L19) · [supabase/upgrade_digimais_robot_handoff.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_robot_handoff.sql#L4)
- `public.manage_digimais_pilot` — [supabase/schema.sql · linha 4635](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4635) · [supabase/upgrade_digimais_api_pilot.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L34)
- `public.get_digimais_api_config` — [supabase/schema.sql · linha 4648](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4648) · [supabase/upgrade_digimais_api_pilot.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L47)
- `public.claim_consulta_job_for_api` — [supabase/schema.sql · linha 4651](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4651) · [supabase/schema.sql · linha 6182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6182) · [supabase/upgrade_digimais_api_campaign_pause.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_pause.sql#L2) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L29) · [supabase/upgrade_digimais_api_concurrency_50.sql · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L38) · [supabase/upgrade_digimais_api_pilot.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L25)
- `apoiarcred_private.admin_digimais_access` — [supabase/schema.sql · linha 6203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6203) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L46)
- `public.admin_digimais_access` — [supabase/schema.sql · linha 6228](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6228) · [supabase/upgrade_digimais_partner_access.sql · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L71)

### 26. ConsigX, login e sessão

O adaptador controla autenticação, seleção de convênio, matrícula e consulta. Há repetição limitada de login e reconhecimento de avisos. Sessões e credenciais por slot são integradas pelo worker.

| Componente | Localização exata |
| --- | --- |
| `async def login(` | [vps/tjba.py · linha 138](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L138) |
| `async def login_with_retries` | [vps/tjba.py · linha 206](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L206) |
| `async def prepare` | [vps/tjba.py · linha 234](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L234) |
| `async def choose_matricula` | [vps/tjba.py · linha 245](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L245) |
| `async def consult` | [vps/tjba.py · linha 281](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L281) |
| `class Session` | [vps/tjba.py · linha 368](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L368) |
| `async function loadTjbaSettings` | [dist/tjba.js · linha 55](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L55) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.manage_consigx_access` — [supabase/schema.sql · linha 1739](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1739) · [supabase/schema.sql · linha 2193](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2193) · [supabase/upgrade_consigx_access_editor.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx_access_editor.sql#L3) · [supabase/upgrade_fourth_robot.sql · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L40)

### 27. Extração de margens ConsigX

A identificação de coluna disponível e a extração monetária determinam o valor exposto. job_result normaliza o retorno; failure_details classifica a falha operacional.

| Componente | Localização exata |
| --- | --- |
| `def available_index` | [vps/tjba.py · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L36) |
| `async def read_margin` | [vps/tjba.py · linha 260](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L260) |
| `def job_result` | [vps/tjba.py · linha 327](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L327) |
| `def failure_details` | [vps/tjba.py · linha 331](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L331) |

### 28. Proxy e diagnóstico ConsigX

tjba_proxy.py valida configuração e produz opções de inicialização. diagnose_tjba.py executa o diagnóstico do ambiente. Configuração de proxy precisa ser coerente com toda a sessão.

| Componente | Localização exata |
| --- | --- |
| `def validate` | [vps/tjba_proxy.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba_proxy.py#L11) |
| `def launch_options` | [vps/tjba_proxy.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba_proxy.py#L31) |
| `async def main` | [vps/diagnose_tjba.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose_tjba.py#L5) |

### 29. Integração Amigoz

O backend mantém configuração e sessão do fornecedor, executa chamadas e interpreta margem/saque. O painel consulta catálogo e expõe resultados conforme autorização.

| Componente | Localização exata |
| --- | --- |
| `def configuration` | [vps/amigoz_api.py · linha 56](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L56) |
| `def session(` | [vps/amigoz_api.py · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L215) |
| `def consultation` | [vps/amigoz_api.py · linha 273](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L273) |
| `def margin_result` | [vps/amigoz_api.py · linha 264](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L264) |
| `def saque_result` | [vps/amigoz_api.py · linha 250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L250) |
| `async function loadAmigozCatalog` | [dist/amigoz-api.js · linha 56](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L56) |
| `function showAmigozResult` | [dist/amigoz-api.js · linha 194](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L194) |

### 30. Fila e campanhas Amigoz

amigoz_queue processa jobs e conclui usando contexto de reserva. O frontend agrupa e atualiza campanhas específicas de Amigoz.

| Componente | Localização exata |
| --- | --- |
| `def process` | [vps/amigoz_queue.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_queue.py#L11) |
| `def run(` | [vps/amigoz_queue.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_queue.py#L21) |
| `function amigozCampaignCards` | [dist/amigoz-campaigns.js · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-campaigns.js#L7) |
| `async function refreshAmigozCampaignList` | [dist/amigoz-campaigns.js · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-campaigns.js#L26) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.claim_amigoz_import_job` — [supabase/schema.sql · linha 3374](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3374) · [supabase/upgrade_crm_import_auto.sql · linha 196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L196)
- `public.finish_amigoz_import_job` — [supabase/schema.sql · linha 3393](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3393) · [supabase/upgrade_crm_import_auto.sql · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L215)
- `public.crm_listar_campanhas_amigoz` — [supabase/upgrade_amigoz_campanhas_avulsas.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_campanhas_avulsas.sql#L19)

### 31. Simulador por coeficientes e contexto

O painel carrega contexto de dívida, margem, vínculo e versão e calcula por RPC. A regra atual do banco calcula saque sobre limite residual, aplica mínimo bruto e considera IOF estimado. Alterar apenas os cartões não modifica o motor.

| Componente | Localização exata |
| --- | --- |
| `async function loadCoefficientContext` | [dist/amigoz-coefficients.js · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L65) |
| `async function openAmigozClient` | [dist/amigoz-coefficients.js · linha 139](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L139) |
| `function coefficientResultCards` | [dist/amigoz-coefficients.js · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L50) |
| `amigoz_simular_coeficientes` | [dist/amigoz-coefficients.js · linha 232](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L232) |
| `CREATE OR REPLACE FUNCTION` | [supabase/upgrade_amigoz_debt_cash.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_debt_cash.sql#L4) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.amigoz_simulation_context` — [supabase/schema.sql · linha 4776](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4776) · [supabase/upgrade_amigoz_agreement_context.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_agreement_context.sql#L1) · [supabase/upgrade_amigoz_coefficients.sql · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L79) · [supabase/upgrade_amigoz_imported_agreement.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_imported_agreement.sql#L1)
- `public.amigoz_simular_coeficientes` — [supabase/schema.sql · linha 4869](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4869) · [supabase/schema.sql · linha 5115](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5115) · [supabase/upgrade_amigoz_coefficients.sql · linha 167](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L167) · [supabase/upgrade_amigoz_tables.sql · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L123)
- `public.amigoz_exportar_estimativas` — [supabase/schema.sql · linha 4939](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4939) · [supabase/schema.sql · linha 5933](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5933) · [supabase/upgrade_amigoz_coefficients.sql · linha 237](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L237) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L43)

### 32. Estimativas nas exportações

A exportação agrupa cálculos, verifica compatibilidade e monta colunas financeiras. Valores ausentes ou desatualizados precisam conservar explicação e contexto.

| Componente | Localização exata |
| --- | --- |
| `async function amigozExportEstimates` | [dist/amigoz-coefficients.js · linha 250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L250) |
| `async function amigozAppendExport` | [dist/amigoz-coefficients.js · linha 265](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L265) |
| `function crmAmigozColumns` | [dist/crm.js · linha 129](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L129) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.crm_filter_clients` — [supabase/schema.sql · linha 2777](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2777) · [supabase/schema.sql · linha 2905](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2905) · [supabase/upgrade_crm_importacao.sql · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L95) · [supabase/upgrade_crm_kanban.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L52)
- `public.crm_filter_options` — [supabase/schema.sql · linha 2787](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2787) · [supabase/schema.sql · linha 2915](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2915) · [supabase/upgrade_crm_importacao.sql · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L105) · [supabase/upgrade_crm_kanban.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L62)
- `public.crm_registrar_exportacao` — [supabase/schema.sql · linha 3895](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3895) · [supabase/upgrade_crm_ficha_exportacoes.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L35)
- `public.amigoz_simulation_context` — [supabase/schema.sql · linha 4776](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4776) · [supabase/upgrade_amigoz_agreement_context.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_agreement_context.sql#L1) · [supabase/upgrade_amigoz_coefficients.sql · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L79) · [supabase/upgrade_amigoz_imported_agreement.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_imported_agreement.sql#L1)
- `public.amigoz_simular_coeficientes` — [supabase/schema.sql · linha 4869](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4869) · [supabase/schema.sql · linha 5115](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5115) · [supabase/upgrade_amigoz_coefficients.sql · linha 167](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L167) · [supabase/upgrade_amigoz_tables.sql · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L123)
- `public.amigoz_exportar_estimativas` — [supabase/schema.sql · linha 4939](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4939) · [supabase/schema.sql · linha 5933](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5933) · [supabase/upgrade_amigoz_coefficients.sql · linha 237](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L237) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L43)
- `public.crm_listar_etapas` — [supabase/schema.sql · linha 5287](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5287) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L93)
- `public.crm_salvar_etapa` — [supabase/schema.sql · linha 5298](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5298) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 104](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L104)
- `public.crm_mover_etapa` — [supabase/schema.sql · linha 5340](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5340) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L146)
- `public.crm_kanban` — [supabase/schema.sql · linha 5404](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5404) · [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L210)
- `public.crm_listar_exportacao` — [supabase/schema.sql · linha 5892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5892) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L2)
- `public.crm_convenios_exportacao` — [supabase/schema.sql · linha 5914](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5914) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L24)
- `public.crm_selecionar_etapa` — [supabase/schema.sql · linha 5953](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5953) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L63)
- `public.crm_acao_lote` — [supabase/schema.sql · linha 5975](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5975) · [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L85)

### 33. Tabelas comerciais e comissões

amigoz-tables.js renderiza tabelas, regras de comissão e duplicação. O motor por coeficientes e a configuração comercial têm funções distintas e devem ser revisados juntos quando houver mudança de oferta.

| Componente | Localização exata |
| --- | --- |
| `function bankTableCommission` | [dist/amigoz-tables.js · linha 39](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L39) |
| `function bankTableDuplicate` | [dist/amigoz-tables.js · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L146) |
| `async function loadAmigozTables` | [dist/amigoz-tables.js · linha 172](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L172) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.amigoz_save_tables` — [supabase/schema.sql · linha 5006](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5006) · [supabase/upgrade_amigoz_tables.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L14)
- `public.amigoz_save_tables` — [supabase/schema.sql · linha 5070](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5070) · [supabase/upgrade_amigoz_tables.sql · linha 78](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L78)

### 34. Webhooks no painel

A interface gerencia integrações, filtros, segredo e histórico via manage_webhooks. Testes e reenvios devem respeitar liberação da conta e as regras da fila.

| Componente | Localização exata |
| --- | --- |
| `function whRpc` | [dist/webhooks.js · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L21) |
| `async function loadWebhooks` | [dist/webhooks.js · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L36) |
| `function whEdit` | [dist/webhooks.js · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L45) |
| `function whRenderHistory` | [dist/webhooks.js · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L32) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.manage_webhooks` — [supabase/schema.sql · linha 1096](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1096) · [supabase/schema.sql · linha 1327](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1327) · [supabase/schema.sql · linha 2084](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2084) · [supabase/upgrade_campaign_failure_pause.sql · linha 219](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L219) · [supabase/upgrade_partner_integrations.sql · linha 118](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L118) · [supabase/upgrade_webhooks.sql · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L111)
- `public.manage_webhooks` — [supabase/schema.sql · linha 1196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1196) · [supabase/upgrade_webhooks.sql · linha 211](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L211)

### 35. Entrega de webhooks

O despachante valida destino, assina payload, envia e registra a tentativa. O destinatário deve deduplicar eventos e validar HMAC sobre o corpo recebido.

| Componente | Localização exata |
| --- | --- |
| `def destination` | [vps/webhooks.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L8) |
| `def signed_body` | [vps/webhooks.py · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L29) |
| `def deliver` | [vps/webhooks.py · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L40) |
| `def dispatch_batch` | [vps/webhooks.py · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L67) |
| `def main` | [vps/webhooks.py · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L81) |

### 36. Monitoramento da VPS e slots

O coletor lê recursos locais e publica snapshot. Os slots registram atividade, progresso e qualidade agregada. O painel renderiza dados coletados, incluindo atualidade da coleta.

| Componente | Localização exata |
| --- | --- |
| `def snapshot` | [vps/monitor.py · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L41) |
| `def publish` | [vps/monitor.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L46) |
| `class Slot` | [vps/robot_metrics.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L12) |
| `class RobotMetrics` | [vps/robot_metrics.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L45) |
| `async function tickMonitoring` | [dist/monitoramento.js · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L21) |
| `function renderRobotHealth` | [dist/monitoramento.js · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L34) |

### 37. S3/MinIO

O módulo administra configuração local e testa conexão. A análise desses métodos não demonstra migração das tabelas ou da autenticação para S3.

| Componente | Localização exata |
| --- | --- |
| `def validate_settings` | [vps/minio_settings.py · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L34) |
| `def write_settings` | [vps/minio_settings.py · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L67) |
| `def test_connection` | [vps/minio_settings.py · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L79) |
| `async function requestMinio` | [dist/minio-settings.js · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/minio-settings.js#L41) |

### 38. Instalador e atualização

instalar.sh apresenta opções. atualizar.sh valida checkout e baixa a branch. update-core.sh valida o banco, interrompe consultas, copia arquivos e inicia serviços. A opção 7 troca apenas o JavaScript de login.

| Componente | Localização exata |
| --- | --- |
| `case "$OPTION"` | [instalar.sh · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/instalar.sh#L16) |
| `    7)` | [instalar.sh · linha 92](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/instalar.sh#L92) |
| `git pull` | [atualizar.sh · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/atualizar.sh#L21) |
| `--check-runtime` | [scripts/update-core.sh · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/update-core.sh#L27) |
| `stop-consultas.py` | [scripts/update-core.sh · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/update-core.sh#L29) |
| `systemctl start` | [scripts/update-core.sh · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/update-core.sh#L63) |

### 39. Configuração e validação Supabase

configure_supabase.py separa validação de formato, probe remoto, renderização e persistência. check_endpoint aplica diagnóstico e uma repetição de determinadas falhas transitórias.

| Componente | Localização exata |
| --- | --- |
| `def validate` | [scripts/configure_supabase.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L11) |
| `def check_endpoint` | [scripts/configure_supabase.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L24) |
| `def probe` | [scripts/configure_supabase.py · linha 61](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L61) |
| `def main` | [scripts/configure_supabase.py · linha 106](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L106) |

### 40. Parada emergencial e recuperação da fila

stop_services encerra processos antes de requeue acessar o banco. O timeout nesse momento deixa serviços parados e devolução sem confirmação. drain_queue implementa outro mecanismo com token de manutenção e espera.

| Componente | Localização exata |
| --- | --- |
| `def stop_services` | [scripts/stop-consultas.py · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L25) |
| `def requeue_batch` | [scripts/stop-consultas.py · linha 64](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L64) |
| `def requeue(` | [scripts/stop-consultas.py · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L80) |
| `def main` | [scripts/stop-consultas.py · linha 100](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L100) |
| `def drain` | [scripts/drain_queue.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/drain_queue.py#L16) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `public.consulta_queue_maintenance` — [supabase/schema.sql · linha 397](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L397) · [supabase/upgrade_digimais_concurrency.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_concurrency.sql#L11)

### 41. Diagnóstico de falhas dos robôs

robot_failures classifica falha e transitoriedade. O worker usa essas informações para diagnóstico e recuperação. Mensagem de erro de rede não comprova inexistência de cliente.

| Componente | Localização exata |
| --- | --- |
| `def diagnose` | [vps/robot_failures.py · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_failures.py#L26) |
| `def label` | [vps/robot_failures.py · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_failures.py#L65) |
| `def log_failure` | [vps/worker.py · linha 99](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L99) |

**RPCs e definições SQL usadas pelos módulos acima**

As referências abaixo cobrem chamadas literais desses módulos. Chamadas montadas dinamicamente devem ser acompanhadas na função de entrada indicada.

- `apoiarcred_private.get_tjba_credentials` — [supabase/schema.sql · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L284) · [supabase/upgrade_tjba.sql · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L103)
- `public.get_tjba_credentials` — [supabase/schema.sql · linha 295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L295) · [supabase/upgrade_tjba.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L114)
- `apoiarcred_private.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1680](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1680) · [supabase/upgrade_shared_robots.sql · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L68)
- `public.get_tjba_robot_credentials` — [supabase/schema.sql · linha 1687](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1687) · [supabase/upgrade_shared_robots.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L75)
- `public.claim_tjba_job_for_robot` — [supabase/schema.sql · linha 1724](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1724) · [supabase/upgrade_shared_robots.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L112)
- `public.claim_consulta_job_for_robot` — [supabase/schema.sql · linha 1820](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1820) · [supabase/schema.sql · linha 2250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2250) · [supabase/schema.sql · linha 4670](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4670) · [supabase/upgrade_digimais_api_pilot.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L69) · [supabase/upgrade_fourth_robot.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L97) · [supabase/upgrade_robot_log_slots.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_robot_log_slots.sql#L4)
- `public.get_digimais_api_config` — [supabase/schema.sql · linha 4648](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4648) · [supabase/upgrade_digimais_api_pilot.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L47)
- `public.claim_consulta_job_for_api` — [supabase/schema.sql · linha 4651](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4651) · [supabase/schema.sql · linha 6182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6182) · [supabase/upgrade_digimais_api_campaign_pause.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_pause.sql#L2) · [supabase/upgrade_digimais_api_concurrency_100.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L29) · [supabase/upgrade_digimais_api_concurrency_50.sql · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L38) · [supabase/upgrade_digimais_api_pilot.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L50) · [supabase/upgrade_digimais_partner_access.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L25)

## Catálogo da API V1 com contrato e despacho

O gateway encaminha operações externas para `api_execute`. As rotas são distribuídas por funções SQL e wrappers introduzidos nas migrações. Consulte o contrato de cada método e as definições de despacho listadas abaixo para acompanhar alterações.

Entrada HTTP em [vps/api.py · linha 214](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L214) e encaminhamento RPC em [vps/api.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L16).

- `apoiarcred_private.api_route` — [supabase/schema.sql · linha 656](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L656)
- `public.api_execute` — [supabase/schema.sql · linha 751](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L751)
- `public.api_execute` — [supabase/schema.sql · linha 947](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L947)
- `public.api_execute` — [supabase/schema.sql · linha 1291](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1291)
- `apoiarcred_private.api_route` — [supabase/schema.sql · linha 1518](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1518)
- `apoiarcred_private.api_route` — [supabase/schema.sql · linha 1920](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1920)
- `apoiarcred_private.api_route` — [supabase/schema.sql · linha 3744](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3744)
- `apoiarcred_private.api_route` — [supabase/schema.sql · linha 4180](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4180)
- `apoiarcred_private.api_route` — [supabase/schema.sql · linha 4484](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4484)
- `apoiarcred_private.api_route_oportunidades` — [supabase/schema.sql · linha 5449](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5449)
- `apoiarcred_private.api_route` — [supabase/schema.sql · linha 5540](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5540)
- `public.api_execute` — [supabase/schema.sql · linha 5624](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5624)
- `apoiarcred_private.api_route_oportunidades` — [supabase/schema.sql · linha 5666](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5666)
- `public.api_execute` — [supabase/schema.sql · linha 5784](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5784)
- `public.api_execute` — [supabase/schema.sql · linha 5848](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5848)
- `apoiarcred_private.api_route` — [supabase/upgrade_admin_campaign_limits.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_admin_campaign_limits.sql#L46)
- `apoiarcred_private.api_route` — [supabase/upgrade_api.sql · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L67)
- `public.api_execute` — [supabase/upgrade_api.sql · linha 162](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L162)
- `apoiarcred_private.api_route` — [supabase/upgrade_api_campaign_leads.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_campaign_leads.sql#L2)
- `apoiarcred_private.api_route_legacy` — [supabase/upgrade_api_campanha_convenio.sql · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_campanha_convenio.sql#L22)
- `apoiarcred_private.api_route` — [supabase/upgrade_api_oportunidades.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_oportunidades.sql#L4)
- `apoiarcred_private.api_route` — [supabase/upgrade_campaign_failure_pause.sql · linha 84](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L84)
- `apoiarcred_private.api_route_oportunidades` — [supabase/upgrade_crm_auditoria_e_totais.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L4)
- `public.api_execute` — [supabase/upgrade_crm_auditoria_e_totais.sql · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L122)
- `apoiarcred_private.api_route` — [supabase/upgrade_crm_busca_telefone.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_busca_telefone.sql#L1)
- `apoiarcred_private.api_route_oportunidades` — [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 255](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L255)
- `apoiarcred_private.api_route` — [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 346](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L346)
- `public.api_execute` — [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 430](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L430)
- `apoiarcred_private.api_route` — [supabase/upgrade_crm_import_preview.sql · linha 241](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L241)
- `apoiarcred_private.api_route` — [supabase/upgrade_crm_modelos_convenio.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_modelos_convenio.sql#L97)
- `public.api_execute` — [supabase/upgrade_crm_permissoes_api.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L26)
- `public.api_execute` — [supabase/upgrade_partner_integrations.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L82)
- `public.api_execute` — [supabase/upgrade_partners.sql · linha 163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L163)

| Método | Rota | Comportamento documentado | Contrato no código |
| --- | --- | --- | --- |
| GET | `/servicos` | Serviços disponíveis | [dist/openapi.json · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L14) |
| GET | `/campanhas` | Listar campanhas | [dist/openapi.json · linha 149](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L149) |
| POST | `/campanhas` | Criar campanha pausada | [dist/openapi.json · linha 149](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L149) |
| GET | `/campanhas/{id}` | Andamento e relatório | [dist/openapi.json · linha 468](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L468) |
| GET | `/campanhas/{id}/leads` | Leads da campanha | [dist/openapi.json · linha 604](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L604) |
| POST | `/campanhas/{id}/leads` | Adicionar leads à campanha pausada | [dist/openapi.json · linha 604](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L604) |
| GET | `/campanhas/{id}/leads/status/{status}` | Listar todos os leads com um status | [dist/openapi.json · linha 955](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L955) |
| POST | `/campanhas/{id}/iniciar` | Iniciar ou retomar campanha | [dist/openapi.json · linha 1111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L1111) |
| POST | `/campanhas/{id}/pausar` | Pausar novas consultas | [dist/openapi.json · linha 1259](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L1259) |
| POST | `/campanhas/{id}/repetir-revisoes` | Reenfileirar erros e revisões | [dist/openapi.json · linha 1407](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L1407) |
| GET | `/leads/{id}` | Registro individual e resultado | [dist/openapi.json · linha 1555](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L1555) |
| POST | `/leads/buscar` | Buscar registros por CPF | [dist/openapi.json · linha 1687](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L1687) |
| POST | `/consultas` | Solicitar consulta individual | [dist/openapi.json · linha 1839](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L1839) |
| GET | `/consultas/{id}` | Acompanhar consulta individual | [dist/openapi.json · linha 2000](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2000) |
| GET | `/oportunidades` | Listar oportunidades | [dist/openapi.json · linha 2132](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2132) |
| GET | `/oportunidades/{id}` | Consultar oportunidade | [dist/openapi.json · linha 2308](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2308) |
| POST | `/oportunidades/{id}/etapa` | Mover oportunidade | [dist/openapi.json · linha 2441](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2441) |
| POST | `/oportunidades/exportacao` | Confirmar exportação de oportunidades | [dist/openapi.json · linha 2606](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2606) |
| GET | `/clientes/convenios` | Listar convênios e requisitos de importação | [dist/openapi.json · linha 2742](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2742) |
| POST | `/clientes/importacoes` | Importar clientes de um convênio | [dist/openapi.json · linha 2864](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2864) |
| GET | `/clientes/importacoes` | Listar histórico de importações | [dist/openapi.json · linha 2864](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L2864) |
| POST | `/clientes/importacoes/previa` | Conferir importação | [dist/openapi.json · linha 3163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L3163) |
| GET | `/clientes/importacoes/{id}` | Consultar lote de importação | [dist/openapi.json · linha 3373](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L3373) |
| GET | `/crm/etapas` | Listar etapas | [dist/openapi.json · linha 3403](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L3403) |
| POST | `/crm/etapas` | Criar etapa | [dist/openapi.json · linha 3403](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L3403) |
| PATCH | `/crm/etapas/{id}` | Editar ou arquivar etapa | [dist/openapi.json · linha 3722](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L3722) |
| POST | `/clientes/buscar` | Buscar cliente por CPF ou telefone | [dist/openapi.json · linha 3914](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L3914) |
| GET | `/clientes/{id}` | Consultar perfil pelo ID do cliente | [dist/openapi.json · linha 4114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L4114) |
| GET | `/clientes/{id}/consultas` | Listar consultas do cliente | [dist/openapi.json · linha 4286](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L4286) |
| GET | `/oportunidades/{id}/movimentacoes` | Listar movimentações da oportunidade | [dist/openapi.json · linha 4467](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L4467) |

## Pontos de revisão e riscos com evidência

| Achado | Efeito | Localização |
| --- | --- | --- |
| Login depende de Auth e de validação de permissões | Timeout pode ocorrer antes ou depois da autenticação. | [dist/supabase.js · linha 196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L196) |
| Parada emergencial precede acesso remoto à fila | Falha de requeue mantém serviços parados e estado de tarefas sem confirmação. | [scripts/stop-consultas.py · linha 100](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L100) |
| Resultado em memória durante repetição de persistência | Encerramento do processo pode perder um resultado ainda não salvo. | [vps/worker.py · linha 211](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L211) |
| Preflight remoto bloqueia atualização completa | É possível baixar um commit sem publicar os arquivos na aplicação. | [scripts/update-core.sh · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/update-core.sh#L27) |
| Opção 7 atualiza somente um arquivo | Atualização isolada não migra banco, API ou workers. | [instalar.sh · linha 92](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/instalar.sh#L92) |
| Autorização privilegiada no gateway | Validar propriedade de dados e perfil em cada controlador/RPC. | [vps/api.py · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L35) |
| Scripts globais carregados sequencialmente | A ordem e a substituição de funções interferem no comportamento. | [dist/index.html · linha 147](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/index.html#L147) |
| Configuração MinIO não demonstra uso como banco | O módulo configura e testa armazenamento de objetos. | [vps/minio_settings.py · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L79) |
| Concorrência máxima é um teto de configuração | Capacidade sustentada depende de recursos e fornecedor. | [vps/robot_metrics.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L7) |
| Motor financeiro substituído por migração específica | Conferir cálculo residual, mínimo e versão aplicada ao banco. | [supabase/upgrade_amigoz_debt_cash.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_debt_cash.sql#L4) |

O incidente informado nesta conversa terminou com timeout no Auth e no requeue das três filas, após parada dos serviços. O código acima explica esse comportamento, mas não comprova a causa do transporte. Cache local de autenticação, PostgreSQL próprio na VPS e spool durável de resultados são propostas ainda sem implementação comprovada no commit analisado.

## Procedimento para alterar uma funcionalidade

1. Abrir o ponto de entrada da funcionalidade no mapa.
2. Acompanhar chamadas do módulo e consultar as definições SQL referenciadas.
3. Conferir redefinições da função nas migrações e a versão aplicada no ambiente.
4. Atualizar contrato OpenAPI quando houver mudança externa.
5. Localizar testes no catálogo a seguir e executar os pertinentes à mudança.
6. Validar pela interface ou API normal, incluindo erro, repetição e isolamento de conta.
7. Registrar o commit implantado e verificar o resultado em produção.

## Catálogo de símbolos JavaScript, Python e testes

Cada item aponta para uma declaração real. Métodos de classes aparecem com a assinatura encontrada. O catálogo complementa o mapa funcional com pontos de implementação menores e casos de teste.

### dist/amigoz-api.js

| Símbolo ou teste | Código |
| --- | --- |
| `async function loadAmigozCatalog()` | [dist/amigoz-api.js · linha 56](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L56) |
| `async function amigozRequest(route,body)` | [dist/amigoz-api.js · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L67) |
| `function updateAmigozPanel()` | [dist/amigoz-api.js · linha 92](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L92) |
| `async function loadAmigozConfig()` | [dist/amigoz-api.js · linha 126](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L126) |
| `async function changeAmigozConfig(route,payload,message)` | [dist/amigoz-api.js · linha 136](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L136) |
| `function optionsAmigoz(select,placeholder,items)` | [dist/amigoz-api.js · linha 152](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L152) |
| `function updateAmigozConvenio()` | [dist/amigoz-api.js · linha 155](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L155) |
| `function showAmigozResult(result)` | [dist/amigoz-api.js · linha 194](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-api.js#L194) |

### dist/amigoz-campaigns.js

| Símbolo ou teste | Código |
| --- | --- |
| `function amigozCampaignCards(groups,` | [dist/amigoz-campaigns.js · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-campaigns.js#L7) |
| `async function refreshAmigozCampaignList()` | [dist/amigoz-campaigns.js · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-campaigns.js#L26) |

### dist/amigoz-coefficients.js

| Símbolo ou teste | Código |
| --- | --- |
| `function coefficientRequest(name, body) ` | [dist/amigoz-coefficients.js · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L34) |
| `function setCoefficientBusy(busy) ` | [dist/amigoz-coefficients.js · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L37) |
| `function coefficientMarginFields() ` | [dist/amigoz-coefficients.js · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L40) |
| `function coefficientTablesValidated(result) ` | [dist/amigoz-coefficients.js · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L47) |
| `function coefficientResultCards(result) ` | [dist/amigoz-coefficients.js · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L50) |
| `async function loadCoefficientContext() ` | [dist/amigoz-coefficients.js · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L65) |
| `function canViewAmigozMarginDiagnostic() ` | [dist/amigoz-coefficients.js · linha 110](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L110) |
| `function clearAmigozMarginDiagnostic() ` | [dist/amigoz-coefficients.js · linha 113](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L113) |
| `function showAmigozMarginDiagnostic(diagnostic,convenio,consultaId) ` | [dist/amigoz-coefficients.js · linha 118](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L118) |
| `async function openAmigozClient(cpf, convenio='', jobId=null, name='', margin=false) ` | [dist/amigoz-coefficients.js · linha 139](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L139) |
| `async function amigozExportEstimates(inputs) ` | [dist/amigoz-coefficients.js · linha 250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L250) |
| `async function amigozAppendExport(rows, inputs) ` | [dist/amigoz-coefficients.js · linha 265](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L265) |
| `function amigozCsvCells(row) ` | [dist/amigoz-coefficients.js · linha 313](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-coefficients.js#L313) |

### dist/amigoz-tables.js

| Símbolo ou teste | Código |
| --- | --- |
| `function bankTableSelected() ` | [dist/amigoz-tables.js · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L36) |
| `function bankTableCommission(rule,table) ` | [dist/amigoz-tables.js · linha 39](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L39) |
| `function bankTableStatus(text) ` | [dist/amigoz-tables.js · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L44) |
| `function bankTableRender(preferred) ` | [dist/amigoz-tables.js · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L46) |
| `function bankTableRenderRows() ` | [dist/amigoz-tables.js · linha 64](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L64) |
| `function bankTableDuplicate(tables) ` | [dist/amigoz-tables.js · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L146) |
| `async function loadAmigozTables(preferred,force=false) ` | [dist/amigoz-tables.js · linha 172](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz-tables.js#L172) |

### dist/amigoz.js

| Símbolo ou teste | Código |
| --- | --- |
| `function amigozAction(r)` | [dist/amigoz.js · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L6) |
| `function resetAmigoz()` | [dist/amigoz.js · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L11) |
| `function refreshAmigoz()` | [dist/amigoz.js · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L12) |
| `async function simulateAmigoz(id)` | [dist/amigoz.js · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L19) |
| `function rateKey(rate)` | [dist/amigoz.js · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L32) |
| `function readAmigozConditions()` | [dist/amigoz.js · linha 33](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L33) |
| `function renderAmigozTables(tables)` | [dist/amigoz.js · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L36) |
| `function renderAmigozTable(t,best=false)` | [dist/amigoz.js · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L41) |
| `function closeAmigoz()` | [dist/amigoz.js · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/amigoz.js#L45) |

### dist/app.js

| Símbolo ou teste | Código |
| --- | --- |
| `function selectedService()` | [dist/app.js · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L4) |
| `function serviceLabel(id)` | [dist/app.js · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L5) |
| `function toast(message)` | [dist/app.js · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L7) |
| `function statusLabel(status)` | [dist/app.js · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L8) |
| `function resultMessage(r)` | [dist/app.js · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L9) |
| `function consultationWasPerformed(row)` | [dist/app.js · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L16) |
| `function consultationLogRecords()` | [dist/app.js · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L19) |
| `function downloadConsultationLog(text, filename) ` | [dist/app.js · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L25) |
| `function createConsultationLog(id, filename, emptyMessage) ` | [dist/app.js · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L36) |
| `function renderLogs()` | [dist/app.js · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L65) |
| `function campaignRecords(id)` | [dist/app.js · linha 76](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L76) |
| `function individualRecords()` | [dist/app.js · linha 77](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L77) |
| `function campaignStats(rows)` | [dist/app.js · linha 78](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L78) |
| `function rowsHTML(rows)` | [dist/app.js · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L81) |
| `function renderCampaigns(renderRows=true)` | [dist/app.js · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L82) |
| `function render()` | [dist/app.js · linha 100](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L100) |
| `function formatCpf(value)` | [dist/app.js · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L122) |
| `function matchesLeadSearch(row,query)` | [dist/app.js · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L123) |
| `function validate(r,service=selectedService())` | [dist/app.js · linha 128](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L128) |
| `function csvParse(text)` | [dist/app.js · linha 134](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L134) |
| `function syncImportButton(message)` | [dist/app.js · linha 141](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L141) |
| `function importHeader(value)` | [dist/app.js · linha 148](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L148) |
| `function validateImportClassification(headers, rows, expected = null) ` | [dist/app.js · linha 152](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L152) |
| `function download(name,content)` | [dist/app.js · linha 238](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L238) |
| `async function exportResults(items,filename='consultas.csv') ` | [dist/app.js · linha 239](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L239) |
| `function navigate(page)` | [dist/app.js · linha 262](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/app.js#L262) |

### dist/campaign-reuse.js

| Símbolo ou teste | Código |
| --- | --- |
| `async function history()` | [dist/campaign-reuse.js · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/campaign-reuse.js#L26) |
| `function render()` | [dist/campaign-reuse.js · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/campaign-reuse.js#L35) |
| `async function loadPage()` | [dist/campaign-reuse.js · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/campaign-reuse.js#L80) |
| `function reset()` | [dist/campaign-reuse.js · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/campaign-reuse.js#L95) |

### dist/crm-import.js

| Símbolo ou teste | Código |
| --- | --- |
| `async function crmConfirmWithReceipt(rpcName, payload, requestId) ` | [dist/crm-import.js · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L1) |
| `async function crmConfirmImportBatches(payload, requestId, filename, onProgress) ` | [dist/crm-import.js · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L22) |
| `async function crmReadClientFile(file, uf, convenio, convenioNome = convenio, services = null) ` | [dist/crm-import.js · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L74) |
| `function crmAgreementTemplate(agreement,example) ` | [dist/crm-import.js · linha 191](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L191) |
| `function crmWriteAgreementTemplate(agreement,example) ` | [dist/crm-import.js · linha 204](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L204) |
| `function crmAgreementWorkbook(agreement,data,example=false) ` | [dist/crm-import.js · linha 209](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L209) |
| `async function crmOpenClientImport(amigozCampaign=false) ` | [dist/crm-import.js · linha 239](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L239) |
| `function importProgress(step)` | [dist/crm-import.js · linha 287](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L287) |
| `function showErrors(errors)` | [dist/crm-import.js · linha 288](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L288) |
| `function refresh() ` | [dist/crm-import.js · linha 343](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L343) |
| `function resetFile() ` | [dist/crm-import.js · linha 363](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L363) |
| `async function crmGetImportCatalog() ` | [dist/crm-import.js · linha 490](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L490) |
| `function crmAddPlannedActions(item, client, agreement, planned) ` | [dist/crm-import.js · linha 499](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L499) |
| `async function crmOpenImportHistory()` | [dist/crm-import.js · linha 547](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-import.js#L547) |

### dist/crm-reset.js

| Símbolo ou teste | Código |
| --- | --- |
| `function syncCrmResetAccess() ` | [dist/crm-reset.js · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm-reset.js#L9) |

### dist/crm.js

| Símbolo ou teste | Código |
| --- | --- |
| `function crmRow(cells) ` | [dist/crm.js · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L11) |
| `function crmPath(view, params) ` | [dist/crm.js · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L21) |
| `async function loadCrmClients(page) ` | [dist/crm.js · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L25) |
| `async function loadCrmLinks(client) ` | [dist/crm.js · linha 70](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L70) |
| `function crmAmigozColumns(result, money) ` | [dist/crm.js · linha 129](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L129) |
| `async function loadCrmHistory() ` | [dist/crm.js · linha 152](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L152) |
| `function closeCrmHistory(restoreFocus = false) ` | [dist/crm.js · linha 202](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L202) |
| `function syncCrmPage(page) ` | [dist/crm.js · linha 212](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L212) |
| `function crmStageOptions(select, value, includeAll = false) ` | [dist/crm.js · linha 256](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L256) |
| `function crmRenderBulk()` | [dist/crm.js · linha 279](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L279) |
| `async function crmSelectStage(stage,filters,request,control)` | [dist/crm.js · linha 297](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L297) |
| `async function crmApplyBulk(excluir)` | [dist/crm.js · linha 317](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L317) |
| `async function loadCrmPipeline() ` | [dist/crm.js · linha 339](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L339) |
| `async function crmOpportunityExportDetails(cpfs, epoch) ` | [dist/crm.js · linha 484](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L484) |
| `function crmOpportunityExportValues(cpf, details, row=` | [dist/crm.js · linha 517](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L517) |
| `async function crmUpgradeSavedOpportunityWorkbook(workbookRows, epoch) ` | [dist/crm.js · linha 562](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L562) |
| `function crmExportAgreement(row,details,preferred='') ` | [dist/crm.js · linha 575](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L575) |
| `async function crmExportPageRows(` | [dist/crm.js · linha 584](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L584) |
| `function crmOfferReexport(form,filters,button,status,count) ` | [dist/crm.js · linha 601](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L601) |
| `async function crmDownloadOpportunities(filters,button,status,previewForm) ` | [dist/crm.js · linha 618](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L618) |
| `function crmElement(tag,className='',text='') ` | [dist/crm.js · linha 737](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L737) |
| `function crmRpc(name,params=` | [dist/crm.js · linha 738](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L738) |
| `async function loadCrmFilterOptions()` | [dist/crm.js · linha 739](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L739) |
| `function crmUpdateAgreements()` | [dist/crm.js · linha 757](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L757) |
| `function crmCsvCell(value)` | [dist/crm.js · linha 764](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L764) |
| `async function crmExportClients(template,excel=false)` | [dist/crm.js · linha 768](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L768) |
| `async function crmClientTemplateRows(rows,filters,headers)` | [dist/crm.js · linha 828](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L828) |
| `async function crmLoadSettings()` | [dist/crm.js · linha 904](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L904) |
| `async function crmMoveOpportunity(id,stage,request,extra=` | [dist/crm.js · linha 908](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L908) |
| `function crmOpportunityCard(row,settings,request)` | [dist/crm.js · linha 936](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L936) |
| `function crmOpportunityMargins(signals) ` | [dist/crm.js · linha 962](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L962) |
| `function crmCardFinance(row,target,request)` | [dist/crm.js · linha 970](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L970) |
| `function crmSaveOpportunityWorkbook(rows) ` | [dist/crm.js · linha 1008](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L1008) |
| `async function crmOpenClientProfile(row,selectedId) ` | [dist/crm.js · linha 1054](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L1054) |
| `function crmDialog(title)` | [dist/crm.js · linha 1175](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L1175) |
| `function crmLabeled(form,text,input)` | [dist/crm.js · linha 1182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L1182) |
| `function crmEditOpportunity(row,settings,request)` | [dist/crm.js · linha 1183](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/crm.js#L1183) |

### dist/digimais-pilot.js

| Símbolo ou teste | Código |
| --- | --- |
| `function renderDigiPilotMode()` | [dist/digimais-pilot.js · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L8) |
| `function showSavedDigiPilot(preference)` | [dist/digimais-pilot.js · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L20) |
| `async function loadDigiPilot()` | [dist/digimais-pilot.js · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L25) |
| `function resetDigiLogView()` | [dist/digimais-pilot.js · linha 55](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L55) |
| `function renderDigiLogEntries(rows)` | [dist/digimais-pilot.js · linha 59](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L59) |
| `async function renderDigiApiLogs()` | [dist/digimais-pilot.js · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L81) |
| `function isDigiLogOpen()` | [dist/digimais-pilot.js · linha 125](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/digimais-pilot.js#L125) |

### dist/exclusao.js

| Símbolo ou teste | Código |
| --- | --- |
| `async function deleteConsultation(id)` | [dist/exclusao.js · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/exclusao.js#L3) |

### dist/minio-settings.js

| Símbolo ou teste | Código |
| --- | --- |
| `function resetMinioSettings()` | [dist/minio-settings.js · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/minio-settings.js#L31) |
| `async function requestMinio(action)` | [dist/minio-settings.js · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/minio-settings.js#L41) |

### dist/monitoramento.js

| Símbolo ou teste | Código |
| --- | --- |
| `function metricBytes(v)` | [dist/monitoramento.js · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L3) |
| `function renderMonitoring()` | [dist/monitoramento.js · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L4) |
| `function resetMonitoring()` | [dist/monitoramento.js · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L20) |
| `async function tickMonitoring()` | [dist/monitoramento.js · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L21) |
| `function robotDuration(value)` | [dist/monitoramento.js · linha 30](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L30) |
| `function renderRobotHealth(data,collectorFresh)` | [dist/monitoramento.js · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/monitoramento.js#L34) |

### dist/partners.js

| Símbolo ou teste | Código |
| --- | --- |
| `function hasIntegrationAccess()` | [dist/partners.js · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L3) |
| `function accessRule(service)` | [dist/partners.js · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L4) |
| `function sharedQuotaText(access)` | [dist/partners.js · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L7) |
| `function campaignImportLimit()` | [dist/partners.js · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L11) |
| `function campaignImportError(count)` | [dist/partners.js · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L15) |
| `function assertCanSubmit(service,mode)` | [dist/partners.js · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L21) |
| `function updateQuotaNotice()` | [dist/partners.js · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L43) |
| `function applyAccessUi()` | [dist/partners.js · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L51) |
| `async function partnerRequest(path,body)` | [dist/partners.js · linha 86](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L86) |
| `function syncPartnerQuotaFields()` | [dist/partners.js · linha 92](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L92) |
| `function resetPartnerSettings()` | [dist/partners.js · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L105) |
| `function clearPartnerForm()` | [dist/partners.js · linha 106](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L106) |
| `async function loadPartners()` | [dist/partners.js · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L112) |
| `function renderPartnerDigiSelection()` | [dist/partners.js · linha 144](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L144) |
| `async function loadPartnerDigiAccess()` | [dist/partners.js · linha 150](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/partners.js#L150) |

### dist/settings.js

| Símbolo ou teste | Código |
| --- | --- |
| `function switchSettings(id)` | [dist/settings.js · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L14) |
| `async function copyApi(text)` | [dist/settings.js · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L20) |
| `function clearNewApiToken()` | [dist/settings.js · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L22) |
| `function resetApiSettings()` | [dist/settings.js · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L23) |
| `async function loadApiTokens()` | [dist/settings.js · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L26) |
| `async function loadApiDocs()` | [dist/settings.js · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L45) |
| `function renderApiRoute()` | [dist/settings.js · linha 76](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/settings.js#L76) |

### dist/supabase.js

| Símbolo ou teste | Código |
| --- | --- |
| `function showLogin(message='')` | [dist/supabase.js · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L7) |
| `function saveSession(data)` | [dist/supabase.js · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L12) |
| `async function raw(path,options=` | [dist/supabase.js · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L13) |
| `async function refreshSession()` | [dist/supabase.js · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L27) |
| `async function sbRequest(path,options=` | [dist/supabase.js · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L32) |
| `async function fetchAll(path)` | [dist/supabase.js · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L36) |
| `async function createCampaign(name,items)` | [dist/supabase.js · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L41) |
| `async function retryCampaign(id)` | [dist/supabase.js · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L80) |
| `async function loadConsultationLogDetail(row)` | [dist/supabase.js · linha 90](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L90) |
| `function cloudSyncVisible()` | [dist/supabase.js · linha 99](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L99) |
| `function normalizeCloudRow(r)` | [dist/supabase.js · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L105) |
| `async function syncCloudPages(epoch)` | [dist/supabase.js · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L111) |
| `function loadCloud()` | [dist/supabase.js · linha 143](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L143) |
| `async function add(items,service=selectedService(),convenio=null)` | [dist/supabase.js · linha 169](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L169) |
| `async function refreshMyAccess(force=false)` | [dist/supabase.js · linha 176](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L176) |
| `function isConnectionFailure(error)` | [dist/supabase.js · linha 184](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L184) |
| `function loginFailureMessage(error)` | [dist/supabase.js · linha 187](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L187) |
| `async function openPanel()` | [dist/supabase.js · linha 196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L196) |
| `function setPasswordVisible(visible)` | [dist/supabase.js · linha 222](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L222) |
| `async function signOut()` | [dist/supabase.js · linha 252](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L252) |
| `async function restoreSession()` | [dist/supabase.js · linha 264](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/supabase.js#L264) |

### dist/tjba.js

| Símbolo ou teste | Código |
| --- | --- |
| `function selectedConvenio()` | [dist/tjba.js · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L2) |
| `function convenioLabel(value)` | [dist/tjba.js · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L3) |
| `function tjbaAccessSlot()` | [dist/tjba.js · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L6) |
| `function selectedTjbaAccess()` | [dist/tjba.js · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L9) |
| `function closeTjbaAccessEditor()` | [dist/tjba.js · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L13) |
| `function renderTjbaAccess()` | [dist/tjba.js · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L19) |
| `function resetTjbaSettings()` | [dist/tjba.js · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L37) |
| `function requestTjbaAccess(input=` | [dist/tjba.js · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L52) |
| `async function loadTjbaSettings()` | [dist/tjba.js · linha 55](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L55) |
| `function setTableHead(service,id)` | [dist/tjba.js · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L111) |
| `function updateServiceCopy()` | [dist/tjba.js · linha 145](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L145) |
| `function selectHygieneService()` | [dist/tjba.js · linha 153](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/tjba.js#L153) |

### dist/webhooks.js

| Símbolo ou teste | Código |
| --- | --- |
| `function switchIntegration(id)` | [dist/webhooks.js · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L18) |
| `function whRpc(action,input=` | [dist/webhooks.js · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L21) |
| `function whClearSecret()` | [dist/webhooks.js · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L22) |
| `function resetWebhooks()` | [dist/webhooks.js · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L23) |
| `function whShowSecret(secret)` | [dist/webhooks.js · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L24) |
| `function whDate(value)` | [dist/webhooks.js · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L26) |
| `function whOrigin(w)` | [dist/webhooks.js · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L27) |
| `function whRenderList()` | [dist/webhooks.js · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L28) |
| `function whRenderHistory(rows)` | [dist/webhooks.js · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L32) |
| `async function loadWebhooks()` | [dist/webhooks.js · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L36) |
| `function whScopeChanged()` | [dist/webhooks.js · linha 42](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L42) |
| `function whFiltersChanged()` | [dist/webhooks.js · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L43) |
| `function whEdit(w=null,campaignId=null)` | [dist/webhooks.js · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L45) |
| `async function whMutate(button,fn,onSuccess)` | [dist/webhooks.js · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/webhooks.js#L52) |

### dist/workspace.js

| Símbolo ou teste | Código |
| --- | --- |
| `function orderedClients(rows)` | [dist/workspace.js · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L5) |
| `function campaignPhase(c,rows)` | [dist/workspace.js · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L8) |
| `function campaignPhaseLabel(c,rows)` | [dist/workspace.js · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L9) |
| `function campaignEta(campaign, rows, pending, running, now=Date.now())` | [dist/workspace.js · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L10) |
| `function queryDescription(c)` | [dist/workspace.js · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L37) |
| `function resultProgress(r)` | [dist/workspace.js · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L38) |
| `function canOpenConsultationLog(row) ` | [dist/workspace.js · linha 39](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L39) |
| `function consultationLogActions(row) ` | [dist/workspace.js · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L43) |
| `function consultationLogText(row) ` | [dist/workspace.js · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L48) |
| `function appendResult(label, result) ` | [dist/workspace.js · linha 57](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L57) |
| `function clearConsultationLogDialog() ` | [dist/workspace.js · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L81) |
| `async function downloadRowConsultationLog(id) ` | [dist/workspace.js · linha 87](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L87) |
| `function resultActions(r)` | [dist/workspace.js · linha 116](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L116) |
| `function renderCampaignList()` | [dist/workspace.js · linha 124](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L124) |
| `function syncQueryContext()` | [dist/workspace.js · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L210) |
| `function drawCreationStep(moveFocus=false)` | [dist/workspace.js · linha 236](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L236) |
| `function moveQueryContext()` | [dist/workspace.js · linha 248](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L248) |
| `function simplifyMarginForm()` | [dist/workspace.js · linha 259](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/workspace.js#L259) |

### scripts/configure_api.py

| Símbolo ou teste | Código |
| --- | --- |
| `def configure(text,root,include):` | [scripts/configure_api.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_api.py#L5) |
| `def main():` | [scripts/configure_api.py · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_api.py#L22) |

### scripts/configure_supabase.py

| Símbolo ou teste | Código |
| --- | --- |
| `def role(key):` | [scripts/configure_supabase.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L7) |
| `def validate(url, public, secret):` | [scripts/configure_supabase.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L11) |
| `class ProbeError(Exception):` | [scripts/configure_supabase.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L21) |
| `def check_endpoint(url, path, headers):` | [scripts/configure_supabase.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L24) |
| `def probe(url, public, secret):` | [scripts/configure_supabase.py · linha 61](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L61) |
| `def atomic(path,content,mode):` | [scripts/configure_supabase.py · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L75) |
| `def public_from_js(path):` | [scripts/configure_supabase.py · linha 84](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L84) |
| `def configure(app,url,public,secret,check=probe):` | [scripts/configure_supabase.py · linha 87](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L87) |
| `def main():` | [scripts/configure_supabase.py · linha 106](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/configure_supabase.py#L106) |

### scripts/drain_queue.py

| Símbolo ou teste | Código |
| --- | --- |
| `def rpc(app,token,release=False):` | [scripts/drain_queue.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/drain_queue.py#L6) |
| `def drain(app,release=False,call=rpc,wait=time.sleep,clock=time.monotonic):` | [scripts/drain_queue.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/drain_queue.py#L16) |

### scripts/stop-consultas.py

| Símbolo ou teste | Código |
| --- | --- |
| `def stop_services(run=subprocess.run, sleep=time.sleep):` | [scripts/stop-consultas.py · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L25) |
| `def api_client(app):` | [scripts/stop-consultas.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L45) |
| `def request(path, payload=None):` | [scripts/stop-consultas.py · linha 55](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L55) |
| `def requeue_batch(request, table, rows, payload):` | [scripts/stop-consultas.py · linha 64](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L64) |
| `def requeue(request):` | [scripts/stop-consultas.py · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L80) |
| `def main():` | [scripts/stop-consultas.py · linha 100](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/stop-consultas.py#L100) |

### tests/test_amigoz_api.py

| Símbolo ou teste | Código |
| --- | --- |
| `class AmigozTests(unittest.TestCase):` | [tests/test_amigoz_api.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L16) |
| `def test_catalog_and_non_operational_record(self):` | [tests/test_amigoz_api.py · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L17) |
| `def test_full_catalog_is_backend_only_and_keeps_provider_rules(self):` | [tests/test_amigoz_api.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L24) |
| `def test_saved_password_is_private_and_cannot_follow_a_changed_host(self):` | [tests/test_amigoz_api.py · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L35) |
| `def test_auth_uses_login_access_directly_and_refreshes_once(self):` | [tests/test_amigoz_api.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L46) |
| `def test_both_modes_preserve_success_and_match_only_selected_convenio(self):` | [tests/test_amigoz_api.py · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L60) |
| `def test_pmsp_both_with_only_cpf_client_data(self):` | [tests/test_amigoz_api.py · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L75) |
| `def test_missing_averbadora_does_not_contact_provider(self):` | [tests/test_amigoz_api.py · linha 83](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L83) |
| `def test_admin_denial_precedes_provider_access(self):` | [tests/test_amigoz_api.py · linha 89](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L89) |
| `def test_partner_consultation_checks_access_and_consumes_one_shared_unit(self):` | [tests/test_amigoz_api.py · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L97) |
| `def test_exhausted_partner_never_contacts_provider(self):` | [tests/test_amigoz_api.py · linha 108](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L108) |
| `def test_history_save_failure_preserves_response_and_warns(self):` | [tests/test_amigoz_api.py · linha 116](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L116) |
| `def test_partner_cannot_read_configuration(self):` | [tests/test_amigoz_api.py · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L123) |
| `def test_private_address_is_rejected_before_dial(self):` | [tests/test_amigoz_api.py · linha 131](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_api.py#L131) |

### tests/test_amigoz_optional_fields.cjs

| Símbolo ou teste | Código |
| --- | --- |
| `test('PM SP can submit margin and saque with CPF and no registration/password',()=>` | [tests/test_amigoz_optional_fields.cjs · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_optional_fields.cjs#L5) |
| `test('simulator margin adapter reuses authenticated route and validates agreement',async()=>` | [tests/test_amigoz_optional_fields.cjs · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_optional_fields.cjs#L19) |

### tests/test_amigoz_queue.py

| Símbolo ou teste | Código |
| --- | --- |
| `class QueueTests(unittest.TestCase):` | [tests/test_amigoz_queue.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_queue.py#L8) |
| `def test_modes_and_partial_result_preserved(self):` | [tests/test_amigoz_queue.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_queue.py#L9) |
| `def test_database_retry_does_not_repeat_provider(self):` | [tests/test_amigoz_queue.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_queue.py#L16) |
| `def db(path,payload):` | [tests/test_amigoz_queue.py · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_queue.py#L18) |
| `def test_missing_config_does_not_claim_or_call_provider(self):` | [tests/test_amigoz_queue.py · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_amigoz_queue.py#L27) |

### tests/test_api.py

| Símbolo ou teste | Código |
| --- | --- |
| `class ApiHTTPTests(unittest.TestCase):` | [tests/test_api.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L6) |
| `def setUpClass(cls):` | [tests/test_api.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L8) |
| `def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();cls.thread.join()` | [tests/test_api.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L11) |
| `def call(self,path,method='GET',body=None,headers=None):` | [tests/test_api.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L12) |
| `def test_no_auth_is_rejected_without_touching_database(self):` | [tests/test_api.py · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L17) |
| `def test_health_and_hash_only_upstream(self):` | [tests/test_api.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L20) |
| `def test_post_key_payload_and_replay(self):` | [tests/test_api.py · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L25) |
| `def test_unsupported_filters_and_content_type(self):` | [tests/test_api.py · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L29) |
| `def test_campaign_full_listing_and_status_route(self):` | [tests/test_api.py · linha 33](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L33) |
| `def test_cpf_format_in_individual_lists_and_import_results(self):` | [tests/test_api.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L43) |
| `def test_opportunity_routes_forward_filters_and_format_detail_cpf(self):` | [tests/test_api.py · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L62) |
| `def test_outage_hides_internal_details(self):` | [tests/test_api.py · linha 72](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L72) |
| `def test_sql_only_execute_service_and_openapi_routes_match(self):` | [tests/test_api.py · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L75) |
| `class ApiNginxTests(unittest.TestCase):` | [tests/test_api.py · linha 78](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L78) |
| `def test_ssl_preserved_and_config_idempotent(self):` | [tests/test_api.py · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_api.py#L79) |

### tests/test_chat_browser.py

| Símbolo ou teste | Código |
| --- | --- |
| `class Loc:` | [tests/test_chat_browser.py · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L4) |
| `def __init__(self,page,name):self.page=page;self.name=name` | [tests/test_chat_browser.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L5) |
| `async def count(self):` | [tests/test_chat_browser.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L6) |
| `async def inner_text(self,**kw):return self.page.text` | [tests/test_chat_browser.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L9) |
| `async def click(self,**kw):` | [tests/test_chat_browser.py · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L10) |
| `class Page:` | [tests/test_chat_browser.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L12) |
| `def __init__(self,url,context):self.url=url;self.context=context;self.frames=[];self.main_frame=object();self.text='Página normal';self.handlers=[];self.before_navigation=[]` | [tests/test_chat_browser.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L13) |
| `def set_default_timeout(self,*a):pass` | [tests/test_chat_browser.py · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L14) |
| `def is_closed(self):return False` | [tests/test_chat_browser.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L15) |
| `def locator(self,name):return Loc(self,name)` | [tests/test_chat_browser.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L16) |
| `def get_by_role(self,role,**kw):return Loc(self,str(kw.get('name')))` | [tests/test_chat_browser.py · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L17) |
| `async def add_locator_handler(self,loc,handler):self.handlers.append((loc.name,handler))` | [tests/test_chat_browser.py · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L18) |
| `async def goto(self,*a,**kw):self.url=a[0];self.before_navigation=list(self.handlers);return types.SimpleNamespace(status=200)` | [tests/test_chat_browser.py · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L19) |
| `class Ctx:` | [tests/test_chat_browser.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L20) |
| `def __init__(self,variant):self.variant=variant;self.home=Page(BANK_URL,self);self.chat=Page('https://'+CHAT_HOST+'/chat',self);self.pages=[self.home]` | [tests/test_chat_browser.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L21) |
| `async def new_page(self):return self.home` | [tests/test_chat_browser.py · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L22) |
| `def opened(self):` | [tests/test_chat_browser.py · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L23) |
| `class BrowserTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_chat_browser.py · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L27) |
| `async def test_direct_chat_does_not_open_bank_or_click_widget(self):` | [tests/test_chat_browser.py · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L28) |
| `async def test_bank_failure_does_not_affect_direct_chat(self):` | [tests/test_chat_browser.py · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L32) |
| `async def guarded(url,**kwargs):` | [tests/test_chat_browser.py · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L34) |
| `async def test_new_tab(self):` | [tests/test_chat_browser.py · linha 39](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L39) |
| `async def test_same_tab(self):` | [tests/test_chat_browser.py · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L41) |
| `async def test_embedded_frame(self):` | [tests/test_chat_browser.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L43) |
| `async def test_notice_and_cookie_handlers_before_navigation(self):` | [tests/test_chat_browser.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L45) |
| `async def test_missing_form_is_diagnostic_not_non_client(self):` | [tests/test_chat_browser.py · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L48) |
| `def test_network_errors_keep_actual_code(self):` | [tests/test_chat_browser.py · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L51) |
| `def test_unknown_exception_does_not_publish_client_data(self):` | [tests/test_chat_browser.py · linha 55](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L55) |
| `def test_http_error_stops_without_alternate_route(self):` | [tests/test_chat_browser.py · linha 57](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L57) |
| `def test_verification_stops(self):` | [tests/test_chat_browser.py · linha 59](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_chat_browser.py#L59) |

### tests/test_consultation_picker.cjs

| Símbolo ou teste | Código |
| --- | --- |
| `function element() ` | [tests/test_consultation_picker.cjs · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_consultation_picker.cjs#L5) |

### tests/test_crm_frontend.cjs

| Símbolo ou teste | Código |
| --- | --- |
| `class Element ` | [tests/test_crm_frontend.cjs · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_crm_frontend.cjs#L2) |

### tests/test_crm_import.cjs

| Símbolo ou teste | Código |
| --- | --- |
| `test('imports CPF and optional contact fields, preserving leading zeros', async () => ` | [tests/test_crm_import.cjs · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_crm_import.cjs#L14) |
| `test('rejects mismatched region and duplicate CPF without partial import', async () => ` | [tests/test_crm_import.cjs · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_crm_import.cjs#L19) |
| `test('accepts the provider code or catalog display name in an imported row', async () => ` | [tests/test_crm_import.cjs · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_crm_import.cjs#L25) |
| `test('imports reported margin and Amigoz eligibility without treating blank as zero', async () => ` | [tests/test_crm_import.cjs · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_crm_import.cjs#L36) |
| `test('downloads a real Excel template with exactly the import columns', () => ` | [tests/test_crm_import.cjs · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_crm_import.cjs#L47) |
| `test('filled agreement workbooks round-trip through the Excel import', async () => ` | [tests/test_crm_import.cjs · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_crm_import.cjs#L60) |

### tests/test_digimais_api_pilot.py

| Símbolo ou teste | Código |
| --- | --- |
| `class PilotTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_digimais_api_pilot.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L8) |
| `def test_original_false_success_is_preserved_and_observable(self):` | [tests/test_digimais_api_pilot.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L9) |
| `def test_cpf_chat_format_is_idempotent(self):` | [tests/test_digimais_api_pilot.py · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L14) |
| `def test_values(self):` | [tests/test_digimais_api_pilot.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L20) |
| `async def test_http_timeout_and_menu_failures_are_persistable_and_sanitized(self):` | [tests/test_digimais_api_pilot.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L24) |
| `async def test_missing_menu_records_exact_stage(self):` | [tests/test_digimais_api_pilot.py · linha 42](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L42) |
| `class Headers:` | [tests/test_digimais_api_pilot.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L43) |
| `def get_all(self,*args):return []` | [tests/test_digimais_api_pilot.py · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L44) |
| `class Response:` | [tests/test_digimais_api_pilot.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L45) |
| `def __init__(self,data):self.data=data` | [tests/test_digimais_api_pilot.py · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L47) |
| `def __enter__(self):return self` | [tests/test_digimais_api_pilot.py · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L48) |
| `def __exit__(self,*args):pass` | [tests/test_digimais_api_pilot.py · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L49) |
| `def read(self):return json.dumps(self.data).encode()` | [tests/test_digimais_api_pilot.py · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L50) |
| `def test_wrapped_messages_and_incoming_text(self):` | [tests/test_digimais_api_pilot.py · linha 59](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L59) |
| `async def test_closed_service_stops_after_saldo_and_rotates_session_cookies(self):` | [tests/test_digimais_api_pilot.py · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L65) |
| `class Headers:` | [tests/test_digimais_api_pilot.py · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L67) |
| `def __init__(self,cookies):self.cookies=cookies` | [tests/test_digimais_api_pilot.py · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L68) |
| `def get_all(self,*args):return self.cookies` | [tests/test_digimais_api_pilot.py · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L69) |
| `class Response:` | [tests/test_digimais_api_pilot.py · linha 70](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L70) |
| `def __init__(self,data,cookies=[]):self.data=data;self.headers=Headers(cookies)` | [tests/test_digimais_api_pilot.py · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L71) |
| `def __enter__(self):return self` | [tests/test_digimais_api_pilot.py · linha 72](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L72) |
| `def __exit__(self,*args):pass` | [tests/test_digimais_api_pilot.py · linha 73](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L73) |
| `def read(self):return json.dumps(self.data).encode()` | [tests/test_digimais_api_pilot.py · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L74) |
| `def request(req,timeout):` | [tests/test_digimais_api_pilot.py · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L75) |
| `async def test_definitive_chat_replies_before_option_lookup(self):` | [tests/test_digimais_api_pilot.py · linha 102](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L102) |
| `class Headers:` | [tests/test_digimais_api_pilot.py · linha 110](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L110) |
| `def get_all(self,*args):return []` | [tests/test_digimais_api_pilot.py · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L111) |
| `class Response:` | [tests/test_digimais_api_pilot.py · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L112) |
| `def __init__(self,data):self.data=data` | [tests/test_digimais_api_pilot.py · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L114) |
| `def __enter__(self):return self` | [tests/test_digimais_api_pilot.py · linha 115](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L115) |
| `def __exit__(self,*args):pass` | [tests/test_digimais_api_pilot.py · linha 116](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L116) |
| `def read(self):return json.dumps(self.data).encode()` | [tests/test_digimais_api_pilot.py · linha 117](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L117) |
| `def request(req,timeout):` | [tests/test_digimais_api_pilot.py · linha 118](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L118) |
| `async def test_sequential_checkpoint_and_referral(self):` | [tests/test_digimais_api_pilot.py · linha 136](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L136) |
| `async def flow(job,kind):` | [tests/test_digimais_api_pilot.py · linha 138](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L138) |
| `async def save(data):events.append('saved')` | [tests/test_digimais_api_pilot.py · linha 142](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L142) |
| `async def test_failed_checkpoint_does_not_start_parcela(self):` | [tests/test_digimais_api_pilot.py · linha 145](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L145) |
| `async def test_protocol_waits_and_session_isolation(self):` | [tests/test_digimais_api_pilot.py · linha 149](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L149) |
| `class Headers:` | [tests/test_digimais_api_pilot.py · linha 151](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L151) |
| `def get_all(self,*args):return ['session=isolated; Secure']` | [tests/test_digimais_api_pilot.py · linha 152](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L152) |
| `class Response:` | [tests/test_digimais_api_pilot.py · linha 153](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L153) |
| `def __init__(self,data):self.data=data` | [tests/test_digimais_api_pilot.py · linha 155](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L155) |
| `def __enter__(self):return self` | [tests/test_digimais_api_pilot.py · linha 156](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L156) |
| `def __exit__(self,*args):pass` | [tests/test_digimais_api_pilot.py · linha 157](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L157) |
| `def read(self):return json.dumps(self.data).encode()` | [tests/test_digimais_api_pilot.py · linha 158](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L158) |
| `def request(req,timeout):` | [tests/test_digimais_api_pilot.py · linha 159](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L159) |
| `class ApiPoolTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_digimais_api_pilot.py · linha 182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L182) |
| `async def test_fifty_clients_no_requery_when_saving_fails(self):` | [tests/test_digimais_api_pilot.py · linha 183](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L183) |
| `def request(route,payload=None,method='POST',timeout=30):` | [tests/test_digimais_api_pilot.py · linha 189](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L189) |
| `async def process(job,adapter):` | [tests/test_digimais_api_pilot.py · linha 199](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L199) |
| `async def quick(_):await real_sleep(.001)` | [tests/test_digimais_api_pilot.py · linha 206](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_api_pilot.py#L206) |

### tests/test_digimais_concurrency.py

| Símbolo ou teste | Código |
| --- | --- |
| `class ConcurrentDigiTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_digimais_concurrency.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L7) |
| `async def test_four_slots_share_both_queues_and_save_retry_never_requeries(self):` | [tests/test_digimais_concurrency.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L8) |
| `def request(route,data=None,method='POST',timeout=30):` | [tests/test_digimais_concurrency.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L15) |
| `async def process(job,adapter):` | [tests/test_digimais_concurrency.py · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L25) |
| `async def short_sleep(seconds):await original_sleep(.001)` | [tests/test_digimais_concurrency.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L31) |
| `async def full_capacity(capacity):` | [tests/test_digimais_concurrency.py · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L32) |
| `async def test_single_worker_setting_does_not_start_extra_executor(self):` | [tests/test_digimais_concurrency.py · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L44) |
| `async def test_capacity_pauses_and_recovers_one_slot_at_a_time(self):` | [tests/test_digimais_concurrency.py · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_concurrency.py#L53) |

### tests/test_digimais_sessions.py

| Símbolo ou teste | Código |
| --- | --- |
| `class SessionsTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_digimais_sessions.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L9) |
| `def engines(self,fail=False):` | [tests/test_digimais_sessions.py · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L10) |
| `def factory():` | [tests/test_digimais_sessions.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L12) |
| `async def test_reuse_across_customers_but_each_chat_is_clean(self):` | [tests/test_digimais_sessions.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L16) |
| `async def test_nonclient_skips_parcela_and_reuses_browser(self):` | [tests/test_digimais_sessions.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L31) |
| `async def test_isolation_when_owner_changes_and_browser_disconnects(self):` | [tests/test_digimais_sessions.py · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L38) |
| `async def test_default_reuses_within_cpf_then_releases_browser(self):` | [tests/test_digimais_sessions.py · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L49) |
| `async def test_idle_age_and_job_limit_recycle(self):` | [tests/test_digimais_sessions.py · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L60) |
| `async def test_failure_before_cpf_switches_from_consignado_to_cobranca(self):` | [tests/test_digimais_sessions.py · linha 72](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L72) |
| `async def test_failure_after_cpf_tries_only_one_alternate_route(self):` | [tests/test_digimais_sessions.py · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L85) |
| `async def test_busy_executor_rejects_overlap_and_cancellation_cleans_up(self):` | [tests/test_digimais_sessions.py · linha 98](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L98) |
| `async def running(*args,**kwargs):entered.set();await asyncio.Event().wait()` | [tests/test_digimais_sessions.py · linha 101](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_digimais_sessions.py#L101) |

### tests/test_drain_queue.py

| Símbolo ou teste | Código |
| --- | --- |
| `class DrainTests(unittest.TestCase):` | [tests/test_drain_queue.py · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_drain_queue.py#L4) |
| `def test_waits_for_saved_results_and_releases_same_token(self):` | [tests/test_drain_queue.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_drain_queue.py#L5) |
| `def call(app,token,release=False):calls.append((token,release));return 0 if release else next(pending)` | [tests/test_drain_queue.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_drain_queue.py#L7) |
| `def test_timeout_unpauses_without_requeueing_jobs(self):` | [tests/test_drain_queue.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_drain_queue.py#L13) |
| `def call(app,token,release=False):calls.append(release);return 1` | [tests/test_drain_queue.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_drain_queue.py#L15) |

### tests/test_frontend.cjs

| Símbolo ou teste | Código |
| --- | --- |
| `function setup(stored)` | [tests/test_frontend.cjs · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_frontend.cjs#L2) |

### tests/test_import_formats.cjs

| Símbolo ou teste | Código |
| --- | --- |
| `function excelFile(bookType,rows)` | [tests/test_import_formats.cjs · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_import_formats.cjs#L4) |
| `function textFile(name,text)` | [tests/test_import_formats.cjs · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_import_formats.cjs#L5) |

### tests/test_installer.py

| Símbolo ou teste | Código |
| --- | --- |
| `class InstallerTests(unittest.TestCase):` | [tests/test_installer.py · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_installer.py#L4) |
| `def simulate(self,domain='consultas.example.com',dns_ok=True):` | [tests/test_installer.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_installer.py#L5) |
| `def mock(name,text):` | [tests/test_installer.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_installer.py#L21) |
| `def test_install_success(self):` | [tests/test_installer.py · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_installer.py#L52) |
| `def test_dns_failure_restores_nginx(self):` | [tests/test_installer.py · linha 54](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_installer.py#L54) |
| `def test_invalid_domain_rejected_before_changes(self):` | [tests/test_installer.py · linha 56](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_installer.py#L56) |

### tests/test_menu.py

| Símbolo ou teste | Código |
| --- | --- |
| `class MenuTests(unittest.TestCase):` | [tests/test_menu.py · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_menu.py#L3) |
| `def exercise(self,installed,choice):` | [tests/test_menu.py · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_menu.py#L4) |
| `def test_existing_instance_only_updates(self):` | [tests/test_menu.py · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_menu.py#L26) |
| `def test_new_instance_installs(self):` | [tests/test_menu.py · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_menu.py#L28) |
| `def test_exit_does_not_mutate(self):` | [tests/test_menu.py · linha 30](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_menu.py#L30) |

### tests/test_monitor.py

| Símbolo ou teste | Código |
| --- | --- |
| `class MonitorTests(unittest.TestCase):` | [tests/test_monitor.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_monitor.py#L5) |
| `def test_cpu_delta(self):` | [tests/test_monitor.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_monitor.py#L6) |
| `def test_available_memory(self):` | [tests/test_monitor.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_monitor.py#L9) |
| `def test_unknown_service(self):` | [tests/test_monitor.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_monitor.py#L13) |
| `def test_publish(self):` | [tests/test_monitor.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_monitor.py#L15) |

### tests/test_partners_admin.py

| Símbolo ou teste | Código |
| --- | --- |
| `class PartnerAdminTests(unittest.TestCase):` | [tests/test_partners_admin.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L7) |
| `def test_integration_token_cannot_create_account(self):` | [tests/test_partners_admin.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L8) |
| `def test_partner_jwt_cannot_create_account(self):` | [tests/test_partners_admin.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L12) |
| `def upstream(path,*args,**kwargs):` | [tests/test_partners_admin.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L13) |
| `def test_admin_creates_auth_user_and_restricts_profile_to_partner(self):` | [tests/test_partners_admin.py · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L19) |
| `def upstream(path,payload=None,**kwargs):` | [tests/test_partners_admin.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L20) |
| `def test_failed_permission_setup_cleans_up_new_auth_user(self):` | [tests/test_partners_admin.py · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L27) |
| `def upstream(path,payload=None,**kwargs):` | [tests/test_partners_admin.py · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L28) |
| `def test_invalid_quota_rejected_before_creating_auth_user(self):` | [tests/test_partners_admin.py · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L37) |
| `def test_integration_flag_is_forwarded_as_boolean(self):` | [tests/test_partners_admin.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L43) |
| `def test_invalid_integration_flag_is_rejected(self):` | [tests/test_partners_admin.py · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_partners_admin.py#L48) |

### tests/test_registration.py

| Símbolo ou teste | Código |
| --- | --- |
| `class Field:` | [tests/test_registration.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L6) |
| `def __init__(self,chat,index=0):self.chat=chat;self.index=index` | [tests/test_registration.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L7) |
| `def nth(self,index):return Field(self.chat,index)` | [tests/test_registration.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L8) |
| `async def fill(self,value):self.chat.values[self.index]=value` | [tests/test_registration.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L9) |
| `async def press_sequentially(self,value,**kwargs):` | [tests/test_registration.py · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L10) |
| `async def press(self,key):pass` | [tests/test_registration.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L12) |
| `async def inner_text(self,**kwargs):return self.chat.text` | [tests/test_registration.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L13) |
| `class Button:` | [tests/test_registration.py · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L14) |
| `def __init__(self,chat,name):self.chat=chat;self.name=name` | [tests/test_registration.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L15) |
| `def first(self):return self` | [tests/test_registration.py · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L17) |
| `async def is_visible(self):return self.chat.ready` | [tests/test_registration.py · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L18) |
| `async def click(self,**kwargs):` | [tests/test_registration.py · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L19) |
| `class Chat:` | [tests/test_registration.py · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L23) |
| `def __init__(self):self.values=['',''];self.valid=[False,False];self.ready=False;self.text='';self.submissions=0` | [tests/test_registration.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L24) |
| `def locator(self,name):return Field(self)` | [tests/test_registration.py · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L25) |
| `def get_by_role(self,role,**kwargs):return Button(self,kwargs.get('name'))` | [tests/test_registration.py · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L26) |
| `class RegistrationTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_registration.py · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L27) |
| `def test_bank_rejects_cpf_is_review_not_nonclient(self):` | [tests/test_registration.py · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L28) |
| `async def test_keyboard_events_accept_form_once(self):` | [tests/test_registration.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L31) |
| `async def test_rejected_form_fails_without_waiting_for_menu(self):` | [tests/test_registration.py · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L34) |
| `async def test_expired_session_never_restarts_or_resubmits(self):` | [tests/test_registration.py · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L37) |
| `async def test_bank_absent_menu_has_specific_failure(self):` | [tests/test_registration.py · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L41) |
| `async def test_delayed_menu_is_observed_without_duplicate_submit(self):` | [tests/test_registration.py · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L44) |
| `async def become_ready(*args):c.ready=True` | [tests/test_registration.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_registration.py#L46) |

### tests/test_robot.py

| Símbolo ou teste | Código |
| --- | --- |
| `class ResponseTests(unittest.TestCase):` | [tests/test_robot.py · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L4) |
| `def test_saldo(self):` | [tests/test_robot.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L5) |
| `def test_observed_bank_response_with_decimal_dot(self):` | [tests/test_robot.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L8) |
| `def test_valor_saldo_brazilian_number(self):` | [tests/test_robot.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L11) |
| `def test_incomplete_decimal_not_accepted(self):` | [tests/test_robot.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L13) |
| `def test_missing_not_zero(self):` | [tests/test_robot.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L15) |
| `def test_partial_response(self):` | [tests/test_robot.py · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L18) |
| `def test_full_balance_survives_closure_and_inactivity_text(self):` | [tests/test_robot.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L20) |
| `def test_closed_with_only_balance_keeps_amount(self):` | [tests/test_robot.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L24) |
| `def test_unrecognized_not_success(self):self.assertIsNone(parse_response('Aguarde um momento.'))` | [tests/test_robot.py · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L29) |
| `def test_expired(self):self.assertEqual(parse_response('Seu atendimento foi encerrado por falta de interação.')['status'],'erro')` | [tests/test_robot.py · linha 30](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L30) |
| `def test_formatted_cpf(self):` | [tests/test_robot.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L31) |
| `def test_invalid_cpf(self):` | [tests/test_robot.py · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L34) |
| `def test_silent_closure_is_not_non_client(self):` | [tests/test_robot.py · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L36) |
| `def test_technical_failure_is_not_non_client(self):` | [tests/test_robot.py · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L38) |
| `def test_nonbreaking_whitespace(self):` | [tests/test_robot.py · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot.py#L40) |

### tests/test_robot_flow.py

| Símbolo ou teste | Código |
| --- | --- |
| `class Timeout(Exception):pass` | [tests/test_robot_flow.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L6) |
| `class Locator:` | [tests/test_robot_flow.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L7) |
| `def __init__(self,page,name):self.page=page;self.name=name` | [tests/test_robot_flow.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L8) |
| `def first(self):return self` | [tests/test_robot_flow.py · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L10) |
| `def nth(self,i):return Locator(self.page,self.name+str(i))` | [tests/test_robot_flow.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L11) |
| `async def fill(self,value):self.page.actions.append(('fill',self.name,value))` | [tests/test_robot_flow.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L12) |
| `async def press_sequentially(self,value,**kwargs):self.page.actions.append(('type',self.name,value))` | [tests/test_robot_flow.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L13) |
| `async def press(self,key):self.page.actions.append(('key',self.name,key))` | [tests/test_robot_flow.py · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L14) |
| `async def click(self,**kwargs):` | [tests/test_robot_flow.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L15) |
| `async def count(self):` | [tests/test_robot_flow.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L24) |
| `async def is_visible(self):` | [tests/test_robot_flow.py · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L29) |
| `async def inner_text(self,**kwargs):` | [tests/test_robot_flow.py · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L34) |
| `class Page:` | [tests/test_robot_flow.py · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L41) |
| `def __init__(self,actions,fail=False):self.actions=actions;self.registered=False;self.finished=False;self.history=False;self.sent=False;self.fail=fail;self.url='https://www.bancodigimais.com` | [tests/test_robot_flow.py · linha 42](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L42) |
| `def is_closed(self):return False` | [tests/test_robot_flow.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L43) |
| `def set_default_timeout(self,*a):pass` | [tests/test_robot_flow.py · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L44) |
| `async def goto(self,*a,**kw):self.url=a[0];self.actions.append(('goto',a[0]));return types.SimpleNamespace(status=200)` | [tests/test_robot_flow.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L45) |
| `async def wait_for_load_state(self,*a):pass` | [tests/test_robot_flow.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L46) |
| `async def add_locator_handler(self,*a):pass` | [tests/test_robot_flow.py · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L47) |
| `async def wait_for_function(self,*a,**kw):self.actions.append(('wait-cpf',))` | [tests/test_robot_flow.py · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L48) |
| `def get_by_role(self,role,**kw):return Locator(self,str(kw.get('name')))` | [tests/test_robot_flow.py · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L49) |
| `def get_by_placeholder(self,name,**kw):return Locator(self,name)` | [tests/test_robot_flow.py · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L50) |
| `def locator(self,name):return Locator(self,name)` | [tests/test_robot_flow.py · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L51) |
| `class Opened:` | [tests/test_robot_flow.py · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L52) |
| `def __init__(self,page):self.page=page` | [tests/test_robot_flow.py · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L53) |
| `async def __aenter__(self):return self` | [tests/test_robot_flow.py · linha 54](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L54) |
| `async def __aexit__(self,*a):pass` | [tests/test_robot_flow.py · linha 55](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L55) |
| `def value(self):` | [tests/test_robot_flow.py · linha 57](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L57) |
| `async def resolve():return self.page` | [tests/test_robot_flow.py · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L58) |
| `class Context:` | [tests/test_robot_flow.py · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L60) |
| `def __init__(self,actions,fail):` | [tests/test_robot_flow.py · linha 61](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L61) |
| `async def new_page(self):` | [tests/test_robot_flow.py · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L63) |
| `def expect_page(self,**kw):return Opened(self.chat)` | [tests/test_robot_flow.py · linha 66](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L66) |
| `async def close(self):self.closed=True` | [tests/test_robot_flow.py · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L67) |
| `class Browser:` | [tests/test_robot_flow.py · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L68) |
| `def __init__(self,actions,fail):self.context=Context(actions,fail);self.actions=actions;self.fail=fail;self.contexts=[];self.connected=True` | [tests/test_robot_flow.py · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L69) |
| `def is_connected(self):return self.connected` | [tests/test_robot_flow.py · linha 70](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L70) |
| `async def new_context(self,**kw):` | [tests/test_robot_flow.py · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L71) |
| `async def close(self):self.connected=False` | [tests/test_robot_flow.py · linha 73](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L73) |
| `class Engine:` | [tests/test_robot_flow.py · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L74) |
| `def __init__(self,browser):self.browser=browser;self.chromium=self` | [tests/test_robot_flow.py · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L75) |
| `async def __aenter__(self):return self` | [tests/test_robot_flow.py · linha 76](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L76) |
| `async def __aexit__(self,*a):pass` | [tests/test_robot_flow.py · linha 77](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L77) |
| `async def launch(self,**kw):` | [tests/test_robot_flow.py · linha 78](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L78) |
| `class FlowTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_robot_flow.py · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L81) |
| `async def execute(self,fail=False,kind="saldo"):` | [tests/test_robot_flow.py · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L82) |
| `async def progress(percent,stage):events.append((percent,stage))` | [tests/test_robot_flow.py · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L85) |
| `async def test_complete_negative_flow_and_format(self):` | [tests/test_robot_flow.py · linha 89](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L89) |
| `async def test_positive_flow_reads_history_after_session_closes(self):` | [tests/test_robot_flow.py · linha 96](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L96) |
| `async def test_parcela_uses_same_short_route(self):` | [tests/test_robot_flow.py · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L105) |
| `async def test_timeout_includes_exact_stage_not_nonclient(self):` | [tests/test_robot_flow.py · linha 110](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_flow.py#L110) |

### tests/test_robot_metrics.py

| Símbolo ou teste | Código |
| --- | --- |
| `class MetricsTests(unittest.TestCase):` | [tests/test_robot_metrics.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_metrics.py#L8) |
| `def test_saved_only_counts_once_and_classifies_results(self):` | [tests/test_robot_metrics.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_metrics.py#L9) |
| `def test_hourly_window_and_empty_averages(self):` | [tests/test_robot_metrics.py · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_metrics.py#L25) |
| `def test_atomic_aggregate_file_and_missing_invalid_collector(self):` | [tests/test_robot_metrics.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_metrics.py#L31) |
| `def test_single_executor(self):self.assertEqual(len(RobotMetrics(1).slots),1)` | [tests/test_robot_metrics.py · linha 42](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_robot_metrics.py#L42) |

### tests/test_stop_consultas.py

| Símbolo ou teste | Código |
| --- | --- |
| `class EmergencyStopTests(unittest.TestCase):` | [tests/test_stop_consultas.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_stop_consultas.py#L13) |
| `def test_stop_precedes_kill_and_no_restart(self):` | [tests/test_stop_consultas.py · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_stop_consultas.py#L14) |
| `def test_active_executor_blocks_requeue(self):` | [tests/test_stop_consultas.py · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_stop_consultas.py#L23) |
| `def test_only_processing_rows_requeued_without_quota(self):` | [tests/test_stop_consultas.py · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_stop_consultas.py#L28) |
| `def test_failure_attempts_other_queues_and_reports_incomplete(self):` | [tests/test_stop_consultas.py · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_stop_consultas.py#L44) |
| `def request(path, payload=None):` | [tests/test_stop_consultas.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_stop_consultas.py#L45) |
| `def test_remaining_processing_rows_are_not_reported_as_success(self):` | [tests/test_stop_consultas.py · linha 54](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_stop_consultas.py#L54) |

### tests/test_supabase_config.py

| Símbolo ou teste | Código |
| --- | --- |
| `class SettingsTests(unittest.TestCase):` | [tests/test_supabase_config.py · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_supabase_config.py#L4) |
| `def test_switch_preserves_mode_and_keeps_secret_server_side(self):` | [tests/test_supabase_config.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_supabase_config.py#L5) |
| `def test_bad_connection_leaves_files_unchanged(self):` | [tests/test_supabase_config.py · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_supabase_config.py#L10) |
| `def failed(*a):raise TimeoutError()` | [tests/test_supabase_config.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_supabase_config.py#L13) |
| `def test_secret_rejected_for_frontend(self):` | [tests/test_supabase_config.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_supabase_config.py#L16) |

### tests/test_tjba.py

| Símbolo ou teste | Código |
| --- | --- |
| `class ParseTests(unittest.TestCase):` | [tests/test_tjba.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L5) |
| `def test_decimal_values(self):` | [tests/test_tjba.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L6) |
| `def test_available_header_not_fixed_index(self):` | [tests/test_tjba.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L8) |
| `def test_only_one_verified_active(self):` | [tests/test_tjba.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L11) |
| `def test_cpf_and_status(self):` | [tests/test_tjba.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L15) |
| `class SessionTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L20) |
| `async def test_disabled_never_opens_browser(self):` | [tests/test_tjba.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L21) |
| `async def test_same_session_for_three_cpfs_and_isolated_error(self):` | [tests/test_tjba.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L24) |
| `async def test_expiration_blocks_repeated_login_until_new_revision(self):` | [tests/test_tjba.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L31) |
| `class WorkerRouteTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L37) |
| `async def test_tjba_progress_uses_tjba_table_and_credentials_stay_worker_only(self):` | [tests/test_tjba.py · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L38) |
| `def request(path,payload=None,method='POST',timeout=30):` | [tests/test_tjba.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L43) |
| `class Adapter:` | [tests/test_tjba.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L46) |
| `async def run(self,job,credentials,on_progress):` | [tests/test_tjba.py · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L47) |
| `class RecoveryTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L53) |
| `async def test_retry_only_before_submission_and_keep_diagnostics(self):` | [tests/test_tjba.py · linha 54](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L54) |
| `class FakeNavigation:` | [tests/test_tjba.py · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L81) |
| `def __init__(self,page):self.page=page` | [tests/test_tjba.py · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L82) |
| `async def __aenter__(self):return self` | [tests/test_tjba.py · linha 83](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L83) |
| `async def __aexit__(self,*args):return False` | [tests/test_tjba.py · linha 84](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L84) |
| `class FakeLoginLocator:` | [tests/test_tjba.py · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L85) |
| `def __init__(self,page,selector):self.page=page;self.selector=selector` | [tests/test_tjba.py · linha 86](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L86) |
| `def first(self):return self` | [tests/test_tjba.py · linha 88](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L88) |
| `async def is_visible(self):` | [tests/test_tjba.py · linha 89](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L89) |
| `async def wait_for(self,**kwargs):` | [tests/test_tjba.py · linha 92](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L92) |
| `async def all(self):return [self]` | [tests/test_tjba.py · linha 94](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L94) |
| `async def all_inner_texts(self):return ['TRIBUNAL JUSTICA DA BAHIA']` | [tests/test_tjba.py · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L95) |
| `async def count(self):return 1 if await self.is_visible() else 0` | [tests/test_tjba.py · linha 96](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L96) |
| `def locator(self,selector):return FakeLoginLocator(self.page, '#gvOrgao tr' if self.selector=='#gvOrgao' and selector=='tr' else selector)` | [tests/test_tjba.py · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L97) |
| `def filter(self,**kwargs):return self` | [tests/test_tjba.py · linha 98](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L98) |
| `async def inner_text(self):return 'TRIBUNAL JUSTICA DA BAHIA'` | [tests/test_tjba.py · linha 99](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L99) |
| `async def press(self,key):self.page.events.append(('press',self.selector))` | [tests/test_tjba.py · linha 100](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L100) |
| `async def check(self,**kwargs):self.page.events.append(('check',self.selector))` | [tests/test_tjba.py · linha 101](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L101) |
| `async def input_value(self):return getattr(self.page,'values',` | [tests/test_tjba.py · linha 102](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L102) |
| `async def fill(self,value):` | [tests/test_tjba.py · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L103) |
| `async def click(self,**kwargs):` | [tests/test_tjba.py · linha 106](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L106) |
| `class FakeLoginPage:` | [tests/test_tjba.py · linha 113](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L113) |
| `def __init__(self):self.state='blank';self.cookie=True;self.authenticated=False;self.events=[];self.url='about:blank'` | [tests/test_tjba.py · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L114) |
| `async def goto(self,url,**kwargs):` | [tests/test_tjba.py · linha 115](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L115) |
| `def locator(self,selector):return FakeLoginLocator(self,selector)` | [tests/test_tjba.py · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L122) |
| `def expect_navigation(self,**kwargs):return FakeNavigation(self)` | [tests/test_tjba.py · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L123) |
| `def expect_response(self,*args,**kwargs):` | [tests/test_tjba.py · linha 124](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L124) |
| `async def value():return response` | [tests/test_tjba.py · linha 127](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L127) |
| `async def wait_for_load_state(self,*args):pass` | [tests/test_tjba.py · linha 129](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L129) |
| `async def wait_for_function(self,*args,**kwargs):pass` | [tests/test_tjba.py · linha 130](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L130) |
| `class LoginFlowTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 131](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L131) |
| `async def test_public_login_cookie_convenio_then_protected_route(self):` | [tests/test_tjba.py · linha 132](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L132) |
| `async def report(p,label):progress.append(p)` | [tests/test_tjba.py · linha 134](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L134) |
| `async def test_failure_keeps_stage_and_percent_without_leaking_exception_text(self):` | [tests/test_tjba.py · linha 140](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L140) |
| `async def broken(page,cpf,on_step=None):` | [tests/test_tjba.py · linha 142](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L142) |
| `def test_chromium_transport_is_not_digimais_specific(self):` | [tests/test_tjba.py · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L146) |
| `class LoginOutcomeTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 150](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L150) |
| `async def test_rejected_login_does_not_wait_for_grid(self):` | [tests/test_tjba.py · linha 151](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L151) |
| `async def rejected(loc,**kwargs):` | [tests/test_tjba.py · linha 153](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L153) |
| `async def test_login_directly_to_agreement(self):` | [tests/test_tjba.py · linha 161](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L161) |
| `async def direct(loc,**kwargs):` | [tests/test_tjba.py · linha 163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L163) |
| `async def test_agreement_does_not_require_document_navigation(self):` | [tests/test_tjba.py · linha 170](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L170) |
| `def expect(**kwargs):` | [tests/test_tjba.py · linha 172](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L172) |
| `class LoginNoticeTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 180](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L180) |
| `def test_classification_does_not_return_raw_secrets(self):` | [tests/test_tjba.py · linha 181](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L181) |
| `async def test_confirmation_is_not_accepted(self):` | [tests/test_tjba.py · linha 185](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L185) |
| `async def test_cleared_password_stops_before_submit(self):` | [tests/test_tjba.py · linha 189](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L189) |
| `class LoginRetryTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L196) |
| `async def test_retry_then_success_same_page(self):` | [tests/test_tjba.py · linha 197](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L197) |
| `async def test_stops_at_three(self):` | [tests/test_tjba.py · linha 203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L203) |
| `async def test_explicit_rejection_never_retries(self):` | [tests/test_tjba.py · linha 207](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L207) |
| `async def test_timeout_with_challenge_stops_before_retry(self):` | [tests/test_tjba.py · linha 211](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L211) |
| `class InvalidPasswordRetryTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 216](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L216) |
| `async def test_invalid_password_repeated_once(self):` | [tests/test_tjba.py · linha 217](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L217) |
| `async def test_invalid_password_second_attempt_succeeds(self):` | [tests/test_tjba.py · linha 223](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L223) |
| `class ShowPasswordTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 229](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L229) |
| `async def test_show_password_checked_before_fill_and_submit(self):` | [tests/test_tjba.py · linha 230](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L230) |
| `class LoginDiagnosticTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 238](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L238) |
| `def test_redaction(self):` | [tests/test_tjba.py · linha 239](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L239) |
| `async def test_empty_popup_is_ignored(self):` | [tests/test_tjba.py · linha 242](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L242) |
| `class DisconnectConfirmationTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 246](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L246) |
| `def test_only_specific_confirmation_allowed(self):` | [tests/test_tjba.py · linha 247](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L247) |
| `async def test_keyboard_confirm_with_overlay_and_waits_for_authenticated_state(self):` | [tests/test_tjba.py · linha 251](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L251) |
| `def locate(selector):` | [tests/test_tjba.py · linha 256](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L256) |
| `class RegistrationRenderingTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 265](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L265) |
| `async def test_registration_in_document_does_not_block_login(self):` | [tests/test_tjba.py · linha 266](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L266) |
| `async def test_real_foreground_registration_remains_review(self):` | [tests/test_tjba.py · linha 273](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L273) |
| `class ShowPasswordResetTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 281](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L281) |
| `async def test_toggle_clearing_password_does_not_break_submit(self):` | [tests/test_tjba.py · linha 282](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L282) |
| `async def clearing(loc,**kwargs):` | [tests/test_tjba.py · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L284) |
| `class DefaultVerbaTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 292](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L292) |
| `async def test_cpf_reached_without_touching_verba(self):` | [tests/test_tjba.py · linha 293](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L293) |
| `def locate(selector):` | [tests/test_tjba.py · linha 297](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L297) |
| `class MultiConvenioTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_tjba.py · linha 307](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L307) |
| `async def test_wrong_agreement_never_accepted(self):` | [tests/test_tjba.py · linha 308](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L308) |
| `async def test_verified_active_image_button_with_missing_beneficiary_cell(self):` | [tests/test_tjba.py · linha 313](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba.py#L313) |

### tests/test_tjba_proxy.py

| Símbolo ou teste | Código |
| --- | --- |
| `class ProxyTests(unittest.TestCase):` | [tests/test_tjba_proxy.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba_proxy.py#L6) |
| `def test_missing_is_direct(self):` | [tests/test_tjba_proxy.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba_proxy.py#L7) |
| `def test_private_credentials_are_passed(self):` | [tests/test_tjba_proxy.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba_proxy.py#L9) |
| `def test_invalid_never_falls_back_or_leaks(self):` | [tests/test_tjba_proxy.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba_proxy.py#L13) |
| `def test_bad_port_and_incomplete_auth(self):` | [tests/test_tjba_proxy.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba_proxy.py#L20) |
| `def test_both_tjba_launches_use_options_and_digi_does_not(self):` | [tests/test_tjba_proxy.py · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_tjba_proxy.py#L23) |

### tests/test_two_queries.py

| Símbolo ou teste | Código |
| --- | --- |
| `class TwoQueriesTests(unittest.IsolatedAsyncioTestCase):` | [tests/test_two_queries.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L7) |
| `async def test_nonclient_never_starts_second_session(self):` | [tests/test_two_queries.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L8) |
| `async def test_balance_saved_before_parcela_then_complete(self):` | [tests/test_two_queries.py · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L14) |
| `async def one(client,timeout,report,kind):` | [tests/test_two_queries.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L16) |
| `async def test_second_failure_preserves_first_result(self):` | [tests/test_two_queries.py · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L28) |
| `async def test_transient_parcela_failure_retries_only_parcela(self):` | [tests/test_two_queries.py · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L34) |
| `async def test_interrupted_after_cpf_is_distinct_and_keeps_balance(self):` | [tests/test_two_queries.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L43) |
| `async def test_interrupted_saldo_switches_route_and_stops_on_confirmed_nonclient(self):` | [tests/test_two_queries.py · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L53) |
| `async def test_parcela_uses_other_route_on_error_and_keeps_saldo(self):` | [tests/test_two_queries.py · linha 64](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L64) |
| `async def test_failed_alternate_preserves_interruption_and_disables_job_retry(self):` | [tests/test_two_queries.py · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L74) |
| `async def test_partial_balance_is_preserved_when_alternate_cannot_confirm_it(self):` | [tests/test_two_queries.py · linha 84](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L84) |
| `async def test_route_does_not_retry_refused_cpf_or_human_verification(self):` | [tests/test_two_queries.py · linha 94](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L94) |
| `async def test_failed_checkpoint_prevents_second_call(self):` | [tests/test_two_queries.py · linha 101](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L101) |
| `async def test_inconclusive_first_call_is_not_repeated(self):` | [tests/test_two_queries.py · linha 106](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L106) |
| `def test_observed_single_decimal_parcela(self):` | [tests/test_two_queries.py · linha 110](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L110) |
| `def test_brazilian_parcela_and_no_mixing_saldo(self):` | [tests/test_two_queries.py · linha 113](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L113) |
| `def test_missing_parcela_is_not_zero(self):` | [tests/test_two_queries.py · linha 116](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_two_queries.py#L116) |

### tests/test_update.py

| Símbolo ou teste | Código |
| --- | --- |
| `class UpdateTests(unittest.TestCase):` | [tests/test_update.py · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_update.py#L4) |
| `def test_downloaded_updater_deploys_robot_panel_and_service(self):` | [tests/test_update.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_update.py#L5) |
| `def git(*args,cwd=origin):return subprocess.check_output(['/usr/bin/git',*args],cwd=cwd,env=env,stderr=subprocess.DEVNULL,text=True).strip()` | [tests/test_update.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_update.py#L9) |
| `def replace_paths(s):return s.replace('/opt/apoiarcred-src',str(repo)).replace('/opt/apoiarcred',str(app)).replace('/run/lock/apoiarcred-instalar.lock',str(base/'lock')).replace('/var/tmp/ap` | [tests/test_update.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_update.py#L13) |
| `def executable(path,content):path.write_text('#!/bin/bash\n'+content);path.chmod(0o755)` | [tests/test_update.py · linha 33](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_update.py#L33) |

### tests/test_webhooks.py

| Símbolo ou teste | Código |
| --- | --- |
| `class WebhookTests(unittest.TestCase):` | [tests/test_webhooks.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L6) |
| `def job(self):return dict(id='delivery',claim_token='claim',event_id='event',url='https://example.com/receber',secret='whsec_'+'a'*64,payload=` | [tests/test_webhooks.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L7) |
| `def dns(self,*ips):return [(socket.AF_INET,socket.SOCK_STREAM,6,'',(ip,443)) for ip in ips]` | [tests/test_webhooks.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L8) |
| `def test_signature_uses_original_utf8_body_and_timestamp(self):` | [tests/test_webhooks.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L9) |
| `def test_bad_secret_nan_and_large_payload_rejected(self):` | [tests/test_webhooks.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L15) |
| `def test_destination_rejects_all_private_or_mixed_dns_results(self):` | [tests/test_webhooks.py · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L18) |
| `def test_destination_invalid_schemes_ports_userinfo_and_fragments(self):` | [tests/test_webhooks.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L21) |
| `def test_destination_pins_public_address_and_encodes_path(self):` | [tests/test_webhooks.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L24) |
| `def test_connect_keeps_original_sni_on_pinned_ip(self):` | [tests/test_webhooks.py · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L27) |
| `def test_http_outcomes_and_headers_no_redirect_follow(self):` | [tests/test_webhooks.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L31) |
| `def test_certificate_stop_network_retry_no_error_details(self):` | [tests/test_webhooks.py · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L36) |
| `def test_invalid_destination_never_connects(self):` | [tests/test_webhooks.py · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L40) |
| `def test_ack_failure_only_retries_database_never_http(self):` | [tests/test_webhooks.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L43) |
| `def test_two_deliveries_run_concurrently(self):` | [tests/test_webhooks.py · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L47) |
| `def send(job):barrier.wait(timeout=2);return dict(p_success=True,p_http=200,p_error=None,p_retry=False)` | [tests/test_webhooks.py · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/test_webhooks.py#L49) |

### vps/amigoz_api.py

| Símbolo ou teste | Código |
| --- | --- |
| `class AmigozError(Exception):` | [vps/amigoz_api.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L16) |
| `def __init__(self,status,code,message):` | [vps/amigoz_api.py · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L17) |
| `def load_catalog():` | [vps/amigoz_api.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L24) |
| `def public_catalog():` | [vps/amigoz_api.py · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L40) |
| `def credentials_path():` | [vps/amigoz_api.py · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L50) |
| `def configuration():` | [vps/amigoz_api.py · linha 56](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L56) |
| `def public_configuration(config):` | [vps/amigoz_api.py · linha 64](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L64) |
| `def endpoint(value):` | [vps/amigoz_api.py · linha 70](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L70) |
| `def save_configuration(payload):` | [vps/amigoz_api.py · linha 83](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L83) |
| `def persist_configuration(path,config):` | [vps/amigoz_api.py · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L105) |
| `class PublicHTTPS(http.client.HTTPSConnection):` | [vps/amigoz_api.py · linha 119](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L119) |
| `def connect(self):` | [vps/amigoz_api.py · linha 120](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L120) |
| `def margin_response_diagnostic(raw,path,status,secrets):` | [vps/amigoz_api.py · linha 132](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L132) |
| `def request(config,path,payload,token=None,record_response=None):` | [vps/amigoz_api.py · linha 152](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L152) |
| `def read_tokens(response):` | [vps/amigoz_api.py · linha 191](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L191) |
| `def token(*keys):` | [vps/amigoz_api.py · linha 197](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L197) |
| `def start_session(config,refresh=None):` | [vps/amigoz_api.py · linha 203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L203) |
| `def session(config,failed=None,force=False):` | [vps/amigoz_api.py · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L215) |
| `def call(config,path,payload,record_response=None):` | [vps/amigoz_api.py · linha 235](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L235) |
| `def normalized(value):` | [vps/amigoz_api.py · linha 246](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L246) |
| `def saque_result(response,convenio):` | [vps/amigoz_api.py · linha 250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L250) |
| `def margin_result(value):` | [vps/amigoz_api.py · linha 264](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L264) |
| `def consultation(config,payload,before_request=None,diagnostics=None):` | [vps/amigoz_api.py · linha 273](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_api.py#L273) |

### vps/amigoz_queue.py

| Símbolo ou teste | Código |
| --- | --- |
| `def process(job, config):` | [vps/amigoz_queue.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_queue.py#L11) |
| `def run(call, stop):` | [vps/amigoz_queue.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_queue.py#L21) |
| `def start(call):` | [vps/amigoz_queue.py · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_queue.py#L53) |

### vps/api.py

| Símbolo ou teste | Código |
| --- | --- |
| `def format_cpf_field(record):` | [vps/api.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L11) |
| `def rpc(payload):` | [vps/api.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L16) |
| `def supabase_call(path,payload=None,method='POST',bearer=None):` | [vps/api.py · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L23) |
| `class AdminError(Exception):` | [vps/api.py · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L32) |
| `def __init__(self,status,code,message):self.status=status;self.code=code;self.message=message` | [vps/api.py · linha 33](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L33) |
| `def session_actor(auth):` | [vps/api.py · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L35) |
| `def minio_admin(auth,method,path,payload):` | [vps/api.py · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L43) |
| `def partner_admin(auth,method,path,payload):` | [vps/api.py · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L58) |
| `def manage(action,data=None):return supabase_call('/rest/v1/rpc/admin_partner_manage',dict(p_actor=actor,p_action=action,p_input=data or ` | [vps/api.py · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L60) |
| `def amigoz_admin(auth,method,path,payload):` | [vps/api.py · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L123) |
| `def authorize(consume=False):` | [vps/api.py · linha 127](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L127) |
| `def begin():` | [vps/api.py · linha 156](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L156) |
| `class Server(ThreadingHTTPServer):` | [vps/api.py · linha 200](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L200) |
| `def __init__(self,*args,**kwargs):self.slots=threading.BoundedSemaphore(16);super().__init__(*args,**kwargs)` | [vps/api.py · linha 202](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L202) |
| `def process_request(self,request,address):` | [vps/api.py · linha 203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L203) |
| `def process_request_thread(self,*args):` | [vps/api.py · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L210) |
| `class Handler(BaseHTTPRequestHandler):` | [vps/api.py · linha 214](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L214) |
| `def setup(self):super().setup();self.connection.settimeout(10)` | [vps/api.py · linha 216](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L216) |
| `def log_message(self,*args):pass # Never log tokens, CPF query strings or request bodies.` | [vps/api.py · linha 217](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L217) |
| `def send_json(self,status,body,**headers):` | [vps/api.py · linha 218](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L218) |
| `def error(self,status,code,message):self.send_json(status,` | [vps/api.py · linha 224](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L224) |
| `def handle_route(self):` | [vps/api.py · linha 225](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L225) |
| `def do_GET(self):self.handle_route()` | [vps/api.py · linha 281](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L281) |
| `def do_POST(self):self.handle_route()` | [vps/api.py · linha 282](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L282) |
| `def do_OPTIONS(self):self.request_id=str(uuid.uuid4());self.error(405,'method_not_allowed','Método não permitido. Integre pelo servidor, sem expor seu token no navegador público.')` | [vps/api.py · linha 283](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L283) |
| `def do_PUT(self):self.do_OPTIONS()` | [vps/api.py · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L284) |
| `def do_DELETE(self):self.do_OPTIONS()` | [vps/api.py · linha 285](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L285) |
| `def do_PATCH(self):` | [vps/api.py · linha 286](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/api.py#L286) |

### vps/chat_browser.py

| Símbolo ou teste | Código |
| --- | --- |
| `class NavigationIssue(Exception):` | [vps/chat_browser.py · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L10) |
| `def __init__(self, message, *, http_status=None, diagnostic_code=None):` | [vps/chat_browser.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L11) |
| `def describe_error(exc):` | [vps/chat_browser.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L16) |
| `def check_access(text,status=None):` | [vps/chat_browser.py · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L24) |
| `async def body_text(page):` | [vps/chat_browser.py · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L29) |
| `async def open_bank(context,timeout=60000,report=None):` | [vps/chat_browser.py · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L32) |
| `async def dismiss(target):await target.click()` | [vps/chat_browser.py · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L37) |
| `async def find_chat_scope(context,page):` | [vps/chat_browser.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L46) |
| `async def open_chat(context,page,timeout=60000):` | [vps/chat_browser.py · linha 66](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L66) |
| `async def open_direct_chat(context,timeout=60000,report=None):` | [vps/chat_browser.py · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/chat_browser.py#L82) |

### vps/diagnose.py

| Símbolo ou teste | Código |
| --- | --- |
| `async def main():` | [vps/diagnose.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose.py#L6) |
| `def record(name,ok,detail):` | [vps/diagnose.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose.py#L9) |
| `def tls():` | [vps/diagnose.py · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose.py#L17) |
| `async def report(percent,label):print(f'ETAPA / ` | [vps/diagnose.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose.py#L31) |

### vps/diagnose_tjba.py

| Símbolo ou teste | Código |
| --- | --- |
| `async def main():` | [vps/diagnose_tjba.py · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose_tjba.py#L5) |
| `def record(name,ok,detail):` | [vps/diagnose_tjba.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose_tjba.py#L7) |
| `def tls():` | [vps/diagnose_tjba.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/diagnose_tjba.py#L20) |

### vps/digimais_api.py

| Símbolo ou teste | Código |
| --- | --- |
| `class CpfFormatError(ValueError):` | [vps/digimais_api.py · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L9) |
| `def format_cpf(value):` | [vps/digimais_api.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L13) |
| `class FlowStopped(Exception):` | [vps/digimais_api.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L21) |
| `def __init__(self,code,reason):` | [vps/digimais_api.py · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L22) |
| `def assert_service_available(items,after_cpf=False):` | [vps/digimais_api.py · linha 33](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L33) |
| `def money(value):` | [vps/digimais_api.py · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L49) |
| `def messages(raw):` | [vps/digimais_api.py · linha 54](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L54) |
| `def parse_result(items,kind):` | [vps/digimais_api.py · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L62) |
| `class ApiSession:` | [vps/digimais_api.py · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L74) |
| `def __init__(self,config):self.config=config;self.telemetry=None` | [vps/digimais_api.py · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L75) |
| `async def flow(self,job,kind):` | [vps/digimais_api.py · linha 76](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L76) |
| `def mark(value,status='iniciada'):` | [vps/digimais_api.py · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L79) |
| `async def request_once(path,body=None,limit=None):` | [vps/digimais_api.py · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L82) |
| `def send():` | [vps/digimais_api.py · linha 84](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L84) |
| `async def call(path,body=None,limit=None,validate=None):` | [vps/digimais_api.py · linha 102](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L102) |
| `def validate_login(data):` | [vps/digimais_api.py · linha 116](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L116) |
| `def validate_menu(raw,predicate):` | [vps/digimais_api.py · linha 119](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L119) |
| `def validate_result(raw):` | [vps/digimais_api.py · linha 124](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L124) |
| `async def message(text,option=None):` | [vps/digimais_api.py · linha 131](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L131) |
| `def option(predicate):` | [vps/digimais_api.py · linha 136](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L136) |
| `async def run(self,job,on_progress=None,on_checkpoint=None):` | [vps/digimais_api.py · linha 184](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/digimais_api.py#L184) |

### vps/minio_settings.py

| Símbolo ou teste | Código |
| --- | --- |
| `class SettingsError(Exception):` | [vps/minio_settings.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L15) |
| `def __init__(self, message, status=422):` | [vps/minio_settings.py · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L16) |
| `def read_settings():` | [vps/minio_settings.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L21) |
| `def public_settings(config):` | [vps/minio_settings.py · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L28) |
| `def validate_settings(payload, saved):` | [vps/minio_settings.py · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L34) |
| `def write_settings(config):` | [vps/minio_settings.py · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L67) |
| `def test_connection(config):` | [vps/minio_settings.py · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L79) |
| `def handle_settings(method, path, payload):` | [vps/minio_settings.py · linha 101](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/minio_settings.py#L101) |

### vps/monitor.py

| Símbolo ou teste | Código |
| --- | --- |
| `def cpu_ticks(path='/proc/stat'):` | [vps/monitor.py · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L7) |
| `def cpu_percent(previous,current):` | [vps/monitor.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L11) |
| `def memory(path='/proc/meminfo'):` | [vps/monitor.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L15) |
| `def worker_state():` | [vps/monitor.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L20) |
| `def robot_activity(path='/run/apoiarcred-robots/state.json'):` | [vps/monitor.py · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L27) |
| `def snapshot(previous,current):` | [vps/monitor.py · linha 41](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L41) |
| `def publish(payload):` | [vps/monitor.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L46) |
| `def main():` | [vps/monitor.py · linha 54](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/monitor.py#L54) |

### vps/robot.py

| Símbolo ou teste | Código |
| --- | --- |
| `class RobotError(Exception):pass` | [vps/robot.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L6) |
| `def format_cpf(value):` | [vps/robot.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L8) |
| `def normalize(text):return re.sub(r'\s+',' ',text).strip()` | [vps/robot.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L13) |
| `def parse_response(text, *, ended=False, cpf_sent=False, kind="saldo"):` | [vps/robot.py · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L15) |
| `async def wait_menu(chat, name, timeout, *, registration=False):` | [vps/robot.py · linha 59](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L59) |
| `async def start_chat(chat, client, timeout):` | [vps/robot.py · linha 78](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L78) |
| `class DigiSession:` | [vps/robot.py · linha 90](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L90) |
| `def __init__(self,*,idle_seconds=90,max_age=600,max_jobs=1):` | [vps/robot.py · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L97) |
| `async def close(self):` | [vps/robot.py · linha 102](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L102) |
| `async def close_idle(self):` | [vps/robot.py · linha 113](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L113) |
| `async def prepare(self,owner):` | [vps/robot.py · linha 117](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L117) |
| `async def run(self,client,timeout=60000,on_progress=None,on_checkpoint=None):` | [vps/robot.py · linha 132](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L132) |
| `async def run_once(client,timeout=60000,on_progress=None,kind="saldo",session=None,route=None):` | [vps/robot.py · linha 149](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L149) |
| `async def emit(percent,label):` | [vps/robot.py · linha 153](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L153) |
| `async def finish(result):` | [vps/robot.py · linha 159](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L159) |
| `def route_can_retry(result):` | [vps/robot.py · linha 241](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L241) |
| `async def run_with_alternate_route(client,timeout,report,kind,**options):` | [vps/robot.py · linha 254](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L254) |
| `async def alternate_progress(percent,stage):` | [vps/robot.py · linha 264](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L264) |
| `async def run(client,timeout=60000,on_progress=None,on_checkpoint=None,session=None):` | [vps/robot.py · linha 283](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L283) |
| `async def progress(percent,label):` | [vps/robot.py · linha 286](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L286) |
| `async def first_progress(percent,label):await progress(percent//2,'1/2 Saldo: '+label)` | [vps/robot.py · linha 290](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L290) |
| `async def second_progress(percent,label):await progress(50+percent//2,'2/2 Parcela: '+label)` | [vps/robot.py · linha 291](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot.py#L291) |

### vps/robot_failures.py

| Símbolo ou teste | Código |
| --- | --- |
| `def failure(category, code, transient=False):` | [vps/robot_failures.py · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_failures.py#L23) |
| `def diagnose(error, target='portal'):` | [vps/robot_failures.py · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_failures.py#L26) |
| `def label(diagnostic):` | [vps/robot_failures.py · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_failures.py#L65) |

### vps/robot_metrics.py

| Símbolo ou teste | Código |
| --- | --- |
| `def stamp():return datetime.now(timezone.utc).isoformat()` | [vps/robot_metrics.py · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L10) |
| `class Slot:` | [vps/robot_metrics.py · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L12) |
| `def __init__(self,name):` | [vps/robot_metrics.py · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L13) |
| `def begin(self,service):` | [vps/robot_metrics.py · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L17) |
| `def report(self,progress):` | [vps/robot_metrics.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L20) |
| `def saving(self,result):` | [vps/robot_metrics.py · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L22) |
| `def saved(self):` | [vps/robot_metrics.py · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L26) |
| `def snapshot(self):` | [vps/robot_metrics.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L31) |
| `class RobotMetrics:` | [vps/robot_metrics.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L45) |
| `def __init__(self,workers,path=STATE_PATH):` | [vps/robot_metrics.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L46) |
| `def payload(self):return dict(updated_at=stamp(),started_at=self.started_at,slots=[s.snapshot() for s in self.slots],api_slots=[s.snapshot() for s in getattr(self,'api_slots',[])],api_capaci` | [vps/robot_metrics.py · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L48) |
| `def write(self,data):` | [vps/robot_metrics.py · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L49) |
| `async def publish_loop(self):` | [vps/robot_metrics.py · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/robot_metrics.py#L53) |

### vps/tjba.py

| Símbolo ou teste | Código |
| --- | --- |
| `class Review(Exception):` | [vps/tjba.py · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L18) |
| `def __init__(self,status,message,details=None):self.status=status;self.message=message;self.details=details or ` | [vps/tjba.py · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L19) |
| `def norm(text):return ' '.join(unicodedata.normalize('NFKD',str(text)).encode('ascii','ignore').decode().lower().split())` | [vps/tjba.py · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L20) |
| `def normalize_cpf(value):` | [vps/tjba.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L21) |
| `def parse_brl(value):` | [vps/tjba.py · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L25) |
| `def available_index(headers):` | [vps/tjba.py · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L36) |
| `def active_index(headers,rows):` | [vps/tjba.py · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L40) |
| `async def value(page,selector):` | [vps/tjba.py · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L46) |
| `async def assert_convenio(page,convenio='tjba'):` | [vps/tjba.py · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L52) |
| `async def challenge(page):` | [vps/tjba.py · linha 57](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L57) |
| `async def report_step(callback,percent,label):` | [vps/tjba.py · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L60) |
| `async def dismiss_cookies(page):` | [vps/tjba.py · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L62) |
| `async def install_handlers(page):` | [vps/tjba.py · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L65) |
| `async def dismiss(target):await target.click(timeout=5000)` | [vps/tjba.py · linha 66](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L66) |
| `def login_notice(text):` | [vps/tjba.py · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L68) |
| `def safe_login_text(text,credentials=None):` | [vps/tjba.py · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L80) |
| `def is_disconnect_confirmation(text):` | [vps/tjba.py · linha 89](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L89) |
| `async def active_registration_modal(loc):` | [vps/tjba.py · linha 96](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L96) |
| `async def inspect_login_notice(page,credentials=None):` | [vps/tjba.py · linha 115](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L115) |
| `async def login(page,credentials,on_step=None,convenio='tjba'):` | [vps/tjba.py · linha 138](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L138) |
| `async def login_with_retries(page,credentials,on_step=None,convenio='tjba'):` | [vps/tjba.py · linha 206](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L206) |
| `async def progress(percent,label):` | [vps/tjba.py · linha 211](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L211) |
| `async def prepare(page,convenio='tjba'):` | [vps/tjba.py · linha 234](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L234) |
| `async def choose_matricula(page):` | [vps/tjba.py · linha 245](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L245) |
| `async def read_margin(page,selector,*,include_total=False):` | [vps/tjba.py · linha 260](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L260) |
| `async def consult(page,cpf,on_step=None,convenio='tjba'):` | [vps/tjba.py · linha 281](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L281) |
| `def job_result(raw):` | [vps/tjba.py · linha 327](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L327) |
| `def failure_details(exc,page=None):` | [vps/tjba.py · linha 331](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L331) |
| `class Session:` | [vps/tjba.py · linha 368](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L368) |
| `def __init__(self):self.pw=None;self.browser=None;self.context=None;self.page=None;self.identity=None;self.blocked=None;self.blocked_diagnostic=None;self.last_used=0` | [vps/tjba.py · linha 370](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L370) |
| `async def close(self):` | [vps/tjba.py · linha 371](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L371) |
| `async def close_idle(self):` | [vps/tjba.py · linha 380](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L380) |
| `async def run(self,job,credentials,on_progress):` | [vps/tjba.py · linha 382](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L382) |
| `async def report(p,label):` | [vps/tjba.py · linha 385](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L385) |
| `def failed(raw):` | [vps/tjba.py · linha 388](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba.py#L388) |

### vps/tjba_proxy.py

| Símbolo ou teste | Código |
| --- | --- |
| `class ProxyConfigError(ValueError):` | [vps/tjba_proxy.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba_proxy.py#L6) |
| `def validate(data):` | [vps/tjba_proxy.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba_proxy.py#L11) |
| `def launch_options(path=None):` | [vps/tjba_proxy.py · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/tjba_proxy.py#L31) |

### vps/webhooks.py

| Símbolo ou teste | Código |
| --- | --- |
| `class DestinationError(Exception):pass` | [vps/webhooks.py · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L6) |
| `def destination(url):` | [vps/webhooks.py · linha 8](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L8) |
| `class PinnedHTTPS(http.client.HTTPSConnection):` | [vps/webhooks.py · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L21) |
| `def __init__(self,host,ip):super().__init__(host,443,timeout=10,context=ssl.create_default_context());self.ip=ip` | [vps/webhooks.py · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L22) |
| `def connect(self):` | [vps/webhooks.py · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L23) |
| `def signed_body(payload,secret,timestamp):` | [vps/webhooks.py · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L29) |
| `def deliver(job):` | [vps/webhooks.py · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L40) |
| `def abort():` | [vps/webhooks.py · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L45) |
| `def rpc(name,body=None):return supabase_call('/rest/v1/rpc/'+name,` | [vps/webhooks.py · linha 65](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L65) |
| `def dispatch_batch(jobs,pool):` | [vps/webhooks.py · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L67) |
| `def main():` | [vps/webhooks.py · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/webhooks.py#L81) |

### vps/worker.py

| Símbolo ou teste | Código |
| --- | --- |
| `def request(path,payload=None,method='POST',timeout=30):` | [vps/worker.py · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L11) |
| `async def process_digimais(job,adapter):` | [vps/worker.py · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L19) |
| `async def report(percent,stage):` | [vps/worker.py · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L27) |
| `async def flush():` | [vps/worker.py · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L32) |
| `async def checkpoint(data):` | [vps/worker.py · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L40) |
| `async def process_tjba(job,adapter):` | [vps/worker.py · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L50) |
| `async def report(percent,stage):` | [vps/worker.py · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L67) |
| `async def flush():` | [vps/worker.py · linha 72](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L72) |
| `def log_failure(context, diagnostic, action=''):` | [vps/worker.py · linha 99](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L99) |
| `def result_diagnostic(result):` | [vps/worker.py · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L105) |
| `async def run_with_recovery(process, job, session, name):` | [vps/worker.py · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L111) |
| `async def dispatch_robot_jobs(capacity, waiting):` | [vps/worker.py · linha 131](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L131) |
| `async def robot_loop(index, capacity, sessions, waiting):` | [vps/worker.py · linha 158](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L158) |
| `class RobotCapacity:` | [vps/worker.py · linha 223](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L223) |
| `def __init__(self, maximum):` | [vps/worker.py · linha 225](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L225) |
| `def observe(self, ram, cpu):` | [vps/worker.py · linha 231](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L231) |
| `async def watch(self):` | [vps/worker.py · linha 245](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L245) |
| `class ApiCapacity(RobotCapacity):` | [vps/worker.py · linha 262](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L262) |
| `def __init__(self,maximum=DIGIMAIS_API_MAX_CONCURRENCY):` | [vps/worker.py · linha 263](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L263) |
| `def digimais_api_handoff(job, result, finished_at):` | [vps/worker.py · linha 267](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L267) |
| `async def api_loop(index,capacity,slot,config):` | [vps/worker.py · linha 285](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L285) |
| `async def api_supervisor():` | [vps/worker.py · linha 320](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L320) |
| `async def main_async():` | [vps/worker.py · linha 338](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L338) |
| `def main():asyncio.run(main_async())` | [vps/worker.py · linha 365](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/worker.py#L365) |

## Catálogo SQL por objeto e arquivo

Referências de declaração. Uma função repetida em diferentes migrações representa versões ou sobrecargas a verificar, sem presumir ordem alfabética de aplicação.

| Tipo | Objeto | Código |
| --- | --- | --- |
| table | `public.consulta_lotes` | [supabase/schema.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1) |
| index | `consulta_lotes_owner` | [supabase/schema.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4) |
| table | `public.consulta_jobs` | [supabase/schema.sql · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5) |
| index | `consulta_jobs_owner` | [supabase/schema.sql · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L16) |
| index | `consulta_jobs_lote` | [supabase/schema.sql · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L17) |
| index | `consulta_jobs_queue` | [supabase/schema.sql · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L18) |
| policy | `lotes_read` | [supabase/schema.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L26) |
| policy | `lotes_insert` | [supabase/schema.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L27) |
| policy | `jobs_read` | [supabase/schema.sql · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L28) |
| policy | `jobs_insert` | [supabase/schema.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L29) |
| function | `public.claim_consulta_job` | [supabase/schema.sql · linha 30](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L30) |
| function | `public.create_consulta_campaign` | [supabase/schema.sql · linha 42](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L42) |
| function | `apoiarcred_private.retry_consulta_campaign` | [supabase/schema.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L63) |
| function | `public.retry_consulta_campaign` | [supabase/schema.sql · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L80) |
| table | `public.amigoz_comissoes` | [supabase/schema.sql · linha 89](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L89) |
| policy | `own_commissions` | [supabase/schema.sql · linha 99](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L99) |
| table | `public.amigoz_simulacoes` | [supabase/schema.sql · linha 101](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L101) |
| index | `amigoz_simulacoes_owner_job` | [supabase/schema.sql · linha 108](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L108) |
| index | `amigoz_simulacoes_job` | [supabase/schema.sql · linha 109](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L109) |
| policy | `own_simulations` | [supabase/schema.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L114) |
| function | `public.simular_amigoz` | [supabase/schema.sql · linha 117](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L117) |
| policy | `jobs_delete` | [supabase/schema.sql · linha 143](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L143) |
| policy | `lotes_delete` | [supabase/schema.sql · linha 145](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L145) |
| function | `public.create_consulta_campaign` | [supabase/schema.sql · linha 153](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L153) |
| function | `public.claim_consulta_job` | [supabase/schema.sql · linha 161](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L161) |
| table | `public.vps_monitoramento` | [supabase/schema.sql · linha 169](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L169) |
| policy | `monitor_read` | [supabase/schema.sql · linha 179](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L179) |
| table | `public.tjba_lotes` | [supabase/schema.sql · linha 186](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L186) |
| table | `public.tjba_jobs` | [supabase/schema.sql · linha 191](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L191) |
| index | `tjba_lotes_owner` | [supabase/schema.sql · linha 203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L203) |
| index | `tjba_jobs_owner` | [supabase/schema.sql · linha 204](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L204) |
| index | `tjba_jobs_lote` | [supabase/schema.sql · linha 205](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L205) |
| index | `tjba_jobs_queue` | [supabase/schema.sql · linha 206](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L206) |
| policy | `tjba_lotes_read` | [supabase/schema.sql · linha 214](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L214) |
| policy | `tjba_lotes_insert` | [supabase/schema.sql · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L215) |
| policy | `tjba_lotes_delete` | [supabase/schema.sql · linha 216](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L216) |
| policy | `tjba_jobs_read` | [supabase/schema.sql · linha 217](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L217) |
| policy | `tjba_jobs_delete` | [supabase/schema.sql · linha 218](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L218) |
| policy | `tjba_jobs_insert` | [supabase/schema.sql · linha 219](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L219) |
| function | `public.create_tjba_campaign` | [supabase/schema.sql · linha 220](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L220) |
| function | `public.claim_tjba_job` | [supabase/schema.sql · linha 234](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L234) |
| table | `public.consulta_tjba_historico` | [supabase/schema.sql · linha 239](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L239) |
| index | `tjba_historico_owner_job` | [supabase/schema.sql · linha 243](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L243) |
| index | `tjba_historico_job` | [supabase/schema.sql · linha 244](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L244) |
| policy | `tjba_history_read` | [supabase/schema.sql · linha 249](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L249) |
| function | `apoiarcred_private.tjba_history` | [supabase/schema.sql · linha 250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L250) |
| trigger | `save_tjba_history` | [supabase/schema.sql · linha 255](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L255) |
| table | `apoiarcred_private.tjba_credentials` | [supabase/schema.sql · linha 257](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L257) |
| function | `apoiarcred_private.save_tjba_credentials` | [supabase/schema.sql · linha 263](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L263) |
| function | `apoiarcred_private.tjba_credentials_status` | [supabase/schema.sql · linha 277](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L277) |
| function | `apoiarcred_private.get_tjba_credentials` | [supabase/schema.sql · linha 284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L284) |
| function | `public.save_tjba_credentials` | [supabase/schema.sql · linha 293](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L293) |
| function | `public.tjba_credentials_status` | [supabase/schema.sql · linha 294](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L294) |
| function | `public.get_tjba_credentials` | [supabase/schema.sql · linha 295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L295) |
| function | `apoiarcred_private.retry_tjba_campaign` | [supabase/schema.sql · linha 300](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L300) |
| function | `public.retry_tjba_campaign` | [supabase/schema.sql · linha 308](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L308) |
| policy | `tjba_credentials_no_direct_access` | [supabase/schema.sql · linha 314](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L314) |
| function | `apoiarcred_private.cleanup_tjba_secret` | [supabase/schema.sql · linha 315](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L315) |
| trigger | `cleanup_tjba_secret` | [supabase/schema.sql · linha 321](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L321) |
| function | `apoiarcred_private.save_tjba_credentials` | [supabase/schema.sql · linha 326](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L326) |
| function | `apoiarcred_private.tjba_credentials_status` | [supabase/schema.sql · linha 346](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L346) |
| view | `apoiarcred_private.tjba_credentials_admin` | [supabase/schema.sql · linha 354](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L354) |
| function | `apoiarcred_private.assign_consigx_convenio` | [supabase/schema.sql · linha 364](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L364) |
| trigger | `assign_consigx_convenio` | [supabase/schema.sql · linha 371](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L371) |
| function | `public.create_consigx_campaign` | [supabase/schema.sql · linha 372](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L372) |
| table | `apoiarcred_private.queue_maintenance` | [supabase/schema.sql · linha 390](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L390) |
| policy | `queue_maintenance_service` | [supabase/schema.sql · linha 396](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L396) |
| function | `public.consulta_queue_maintenance` | [supabase/schema.sql · linha 397](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L397) |
| function | `public.claim_consulta_job` | [supabase/schema.sql · linha 412](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L412) |
| function | `public.claim_tjba_job` | [supabase/schema.sql · linha 421](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L421) |
| index | `consulta_jobs_lot_order` | [supabase/schema.sql · linha 430](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L430) |
| index | `tjba_jobs_lot_order` | [supabase/schema.sql · linha 433](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L433) |
| function | `apoiarcred_private.set_campaign_paused` | [supabase/schema.sql · linha 434](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L434) |
| function | `public.set_campaign_paused` | [supabase/schema.sql · linha 446](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L446) |
| function | `public.claim_consulta_job` | [supabase/schema.sql · linha 449](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L449) |
| function | `public.claim_tjba_job` | [supabase/schema.sql · linha 461](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L461) |
| function | `public.create_consulta_campaign` | [supabase/schema.sql · linha 474](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L474) |
| function | `public.create_consigx_campaign` | [supabase/schema.sql · linha 489](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L489) |
| function | `apoiarcred_private.amigoz_price` | [supabase/schema.sql · linha 502](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L502) |
| function | `public.simular_amigoz_price` | [supabase/schema.sql · linha 538](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L538) |
| function | `public.simular_amigoz` | [supabase/schema.sql · linha 560](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L560) |
| table | `apoiarcred_private.api_tokens` | [supabase/schema.sql · linha 565](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L565) |
| index | `api_tokens_owner` | [supabase/schema.sql · linha 571](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L571) |
| table | `apoiarcred_private.api_idempotency` | [supabase/schema.sql · linha 572](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L572) |
| policy | `api_tokens_service` | [supabase/schema.sql · linha 582](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L582) |
| policy | `api_idempotency_service` | [supabase/schema.sql · linha 583](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L583) |
| function | `apoiarcred_private.manage_api_tokens` | [supabase/schema.sql · linha 584](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L584) |
| function | `public.manage_api_tokens` | [supabase/schema.sql · linha 609](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L609) |
| view | `apoiarcred_private.api_campaign_rows` | [supabase/schema.sql · linha 613](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L613) |
| view | `apoiarcred_private.api_lead_rows` | [supabase/schema.sql · linha 616](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L616) |
| function | `apoiarcred_private.api_format_cpf` | [supabase/schema.sql · linha 624](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L624) |
| function | `apoiarcred_private.api_response` | [supabase/schema.sql · linha 636](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L636) |
| function | `apoiarcred_private.api_error` | [supabase/schema.sql · linha 652](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L652) |
| function | `apoiarcred_private.api_route` | [supabase/schema.sql · linha 656](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L656) |
| function | `public.api_execute` | [supabase/schema.sql · linha 751](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L751) |
| table | `apoiarcred_private.user_profiles` | [supabase/schema.sql · linha 786](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L786) |
| table | `apoiarcred_private.partner_permissions` | [supabase/schema.sql · linha 791](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L791) |
| table | `apoiarcred_private.partner_daily_usage` | [supabase/schema.sql · linha 798](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L798) |
| policy | `profiles_service` | [supabase/schema.sql · linha 807](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L807) |
| policy | `permissions_service` | [supabase/schema.sql · linha 808](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L808) |
| policy | `usage_service` | [supabase/schema.sql · linha 809](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L809) |
| function | `apoiarcred_private.access_for` | [supabase/schema.sql · linha 816](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L816) |
| function | `apoiarcred_private.my_access` | [supabase/schema.sql · linha 831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L831) |
| function | `public.my_access` | [supabase/schema.sql · linha 835](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L835) |
| function | `apoiarcred_private.is_admin` | [supabase/schema.sql · linha 838](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L838) |
| function | `apoiarcred_private.my_admin` | [supabase/schema.sql · linha 841](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L841) |
| function | `public.am_i_admin` | [supabase/schema.sql · linha 844](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L844) |
| policy | `monitor_read` | [supabase/schema.sql · linha 848](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L848) |
| function | `apoiarcred_private.check_partner_access` | [supabase/schema.sql · linha 850](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L850) |
| function | `apoiarcred_private.guard_partner_lot` | [supabase/schema.sql · linha 872](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L872) |
| trigger | `guard_partner_lot` | [supabase/schema.sql · linha 880](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L880) |
| trigger | `guard_partner_lot` | [supabase/schema.sql · linha 881](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L881) |
| function | `apoiarcred_private.guard_partner_job` | [supabase/schema.sql · linha 882](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L882) |
| trigger | `guard_partner_job` | [supabase/schema.sql · linha 895](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L895) |
| trigger | `guard_partner_job` | [supabase/schema.sql · linha 896](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L896) |
| function | `public.create_individual_consulta` | [supabase/schema.sql · linha 898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L898) |
| function | `public.admin_partner_manage` | [supabase/schema.sql · linha 912](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L912) |
| function | `public.api_execute` | [supabase/schema.sql · linha 947](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L947) |
| table | `apoiarcred_private.webhooks` | [supabase/schema.sql · linha 987](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L987) |
| index | `webhooks_owner` | [supabase/schema.sql · linha 996](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L996) |
| table | `apoiarcred_private.webhook_events` | [supabase/schema.sql · linha 997](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L997) |
| index | `webhook_events_owner` | [supabase/schema.sql · linha 1001](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1001) |
| table | `apoiarcred_private.webhook_deliveries` | [supabase/schema.sql · linha 1002](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1002) |
| index | `webhook_delivery_queue` | [supabase/schema.sql · linha 1009](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1009) |
| index | `webhook_delivery_hook` | [supabase/schema.sql · linha 1010](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1010) |
| table | `apoiarcred_private.webhook_attempts` | [supabase/schema.sql · linha 1011](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1011) |
| table | `apoiarcred_private.webhook_campaign_dirty` | [supabase/schema.sql · linha 1016](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1016) |
| function | `apoiarcred_private.wh_client` | [supabase/schema.sql · linha 1027](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1027) |
| function | `apoiarcred_private.wh_result` | [supabase/schema.sql · linha 1034](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1034) |
| function | `apoiarcred_private.wh_enqueue` | [supabase/schema.sql · linha 1038](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1038) |
| function | `apoiarcred_private.wh_capture` | [supabase/schema.sql · linha 1055](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1055) |
| trigger | `capture_webhook` | [supabase/schema.sql · linha 1075](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1075) |
| trigger | `capture_webhook` | [supabase/schema.sql · linha 1076](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1076) |
| function | `apoiarcred_private.wh_campaigns` | [supabase/schema.sql · linha 1078](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1078) |
| function | `apoiarcred_private.manage_webhooks` | [supabase/schema.sql · linha 1096](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1096) |
| function | `apoiarcred_private.wh_claim` | [supabase/schema.sql · linha 1165](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1165) |
| function | `apoiarcred_private.wh_ack` | [supabase/schema.sql · linha 1181](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1181) |
| function | `public.manage_webhooks` | [supabase/schema.sql · linha 1196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1196) |
| function | `public.claim_webhook_deliveries` | [supabase/schema.sql · linha 1197](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1197) |
| function | `public.ack_webhook_delivery` | [supabase/schema.sql · linha 1198](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1198) |
| function | `apoiarcred_private.wh_cleanup` | [supabase/schema.sql · linha 1205](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1205) |
| trigger | `cleanup_webhook_secret` | [supabase/schema.sql · linha 1207](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1207) |
| function | `apoiarcred_private.can_integrate` | [supabase/schema.sql · linha 1212](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1212) |
| function | `apoiarcred_private.access_for` | [supabase/schema.sql · linha 1218](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1218) |
| function | `public.admin_partner_manage` | [supabase/schema.sql · linha 1233](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1233) |
| function | `apoiarcred_private.manage_api_tokens` | [supabase/schema.sql · linha 1267](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1267) |
| function | `public.api_execute` | [supabase/schema.sql · linha 1291](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1291) |
| function | `apoiarcred_private.manage_webhooks` | [supabase/schema.sql · linha 1327](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1327) |
| function | `apoiarcred_private.wh_enqueue` | [supabase/schema.sql · linha 1396](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1396) |
| function | `apoiarcred_private.wh_capture` | [supabase/schema.sql · linha 1414](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1414) |
| function | `apoiarcred_private.wh_campaigns` | [supabase/schema.sql · linha 1436](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1436) |
| function | `apoiarcred_private.wh_claim` | [supabase/schema.sql · linha 1455](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1455) |
| function | `public.create_consulta_campaign` | [supabase/schema.sql · linha 1474](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1474) |
| function | `public.create_tjba_campaign` | [supabase/schema.sql · linha 1490](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1490) |
| function | `public.create_consigx_campaign` | [supabase/schema.sql · linha 1504](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1504) |
| function | `apoiarcred_private.api_route` | [supabase/schema.sql · linha 1518](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1518) |
| table | `apoiarcred_private.tjba_robot_credentials` | [supabase/schema.sql · linha 1614](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1614) |
| index | `tjba_jobs_running_owner` | [supabase/schema.sql · linha 1626](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1626) |
| function | `apoiarcred_private.tjba_robot_login` | [supabase/schema.sql · linha 1628](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1628) |
| function | `apoiarcred_private.manage_tjba_robot_credentials` | [supabase/schema.sql · linha 1643](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1643) |
| function | `public.manage_tjba_robot_credentials` | [supabase/schema.sql · linha 1672](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1672) |
| function | `apoiarcred_private.get_tjba_robot_credentials` | [supabase/schema.sql · linha 1680](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1680) |
| function | `public.get_tjba_robot_credentials` | [supabase/schema.sql · linha 1687](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1687) |
| function | `apoiarcred_private.claim_consigx_for_robot` | [supabase/schema.sql · linha 1694](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1694) |
| function | `public.claim_tjba_job_for_robot` | [supabase/schema.sql · linha 1724](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1724) |
| function | `public.claim_tjba_job` | [supabase/schema.sql · linha 1731](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1731) |
| function | `public.manage_consigx_access` | [supabase/schema.sql · linha 1739](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1739) |
| function | `apoiarcred_private.tjba_robot_login` | [supabase/schema.sql · linha 1773](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1773) |
| function | `apoiarcred_private.claim_consigx_for_robot` | [supabase/schema.sql · linha 1787](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1787) |
| function | `public.claim_consulta_job_for_robot` | [supabase/schema.sql · linha 1820](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1820) |
| function | `apoiarcred_private.track_campaign_failures` | [supabase/schema.sql · linha 1847](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1847) |
| function | `apoiarcred_private.reset_campaign_failures` | [supabase/schema.sql · linha 1870](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1870) |
| trigger | `track_campaign_failures` | [supabase/schema.sql · linha 1882](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1882) |
| trigger | `track_campaign_failures` | [supabase/schema.sql · linha 1884](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1884) |
| trigger | `reset_campaign_failures` | [supabase/schema.sql · linha 1886](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1886) |
| trigger | `reset_campaign_failures` | [supabase/schema.sql · linha 1888](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1888) |
| function | `apoiarcred_private.retry_consulta_campaign` | [supabase/schema.sql · linha 1892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1892) |
| function | `apoiarcred_private.guard_partner_job` | [supabase/schema.sql · linha 1907](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1907) |
| function | `apoiarcred_private.api_route` | [supabase/schema.sql · linha 1920](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L1920) |
| function | `apoiarcred_private.wh_capture` | [supabase/schema.sql · linha 2043](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2043) |
| function | `apoiarcred_private.wh_campaigns` | [supabase/schema.sql · linha 2065](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2065) |
| function | `apoiarcred_private.manage_webhooks` | [supabase/schema.sql · linha 2084](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2084) |
| function | `apoiarcred_private.manage_tjba_robot_credentials` | [supabase/schema.sql · linha 2165](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2165) |
| function | `public.manage_consigx_access` | [supabase/schema.sql · linha 2193](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2193) |
| function | `apoiarcred_private.claim_consigx_for_robot` | [supabase/schema.sql · linha 2222](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2222) |
| function | `public.claim_consulta_job_for_robot` | [supabase/schema.sql · linha 2250](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2250) |
| function | `apoiarcred_private.track_campaign_failures` | [supabase/schema.sql · linha 2266](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2266) |
| function | `apoiarcred_private.access_for` | [supabase/schema.sql · linha 2295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2295) |
| function | `apoiarcred_private.check_partner_access` | [supabase/schema.sql · linha 2317](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2317) |
| function | `public.admin_partner_manage` | [supabase/schema.sql · linha 2350](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2350) |
| function | `public.create_consulta_campaign` | [supabase/schema.sql · linha 2393](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2393) |
| function | `public.create_tjba_campaign` | [supabase/schema.sql · linha 2409](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2409) |
| function | `public.create_consigx_campaign` | [supabase/schema.sql · linha 2423](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2423) |
| function | `apoiarcred_private.access_for` | [supabase/schema.sql · linha 2440](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2440) |
| function | `public.admin_partner_manage` | [supabase/schema.sql · linha 2463](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2463) |
| function | `public.authorize_amigoz` | [supabase/schema.sql · linha 2511](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2511) |
| view | `public.crm_consultas` | [supabase/schema.sql · linha 2540](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2540) |
| view | `public.crm_clientes` | [supabase/schema.sql · linha 2552](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2552) |
| index | `consulta_jobs_crm_cpf` | [supabase/schema.sql · linha 2565](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2565) |
| index | `tjba_jobs_crm_cpf` | [supabase/schema.sql · linha 2566](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2566) |
| table | `public.crm_cadastros` | [supabase/schema.sql · linha 2571](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2571) |
| table | `public.crm_vinculos` | [supabase/schema.sql · linha 2582](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2582) |
| policy | `crm_cadastro_leitura` | [supabase/schema.sql · linha 2600](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2600) |
| policy | `crm_vinculo_leitura` | [supabase/schema.sql · linha 2603](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2603) |
| function | `apoiarcred_private.crm_sync_job` | [supabase/schema.sql · linha 2629](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2629) |
| trigger | `crm_sync_consulta` | [supabase/schema.sql · linha 2668](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2668) |
| trigger | `crm_sync_tjba` | [supabase/schema.sql · linha 2671](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2671) |
| view | `public.crm_clientes` | [supabase/schema.sql · linha 2674](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2674) |
| table | `public.crm_oportunidades` | [supabase/schema.sql · linha 2680](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2680) |
| policy | `crm_oportunidades_owner` | [supabase/schema.sql · linha 2697](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2697) |
| policy | `crm_oportunidades_update` | [supabase/schema.sql · linha 2700](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2700) |
| policy | `crm_oportunidades_insert` | [supabase/schema.sql · linha 2704](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2704) |
| index | `crm_oportunidades_lista` | [supabase/schema.sql · linha 2720](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2720) |
| table | `public.crm_card_settings` | [supabase/schema.sql · linha 2727](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2727) |
| policy | `crm_card_settings_owner` | [supabase/schema.sql · linha 2737](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2737) |
| function | `apoiarcred_private.crm_validate_customization` | [supabase/schema.sql · linha 2741](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2741) |
| trigger | `crm_card_settings_validate` | [supabase/schema.sql · linha 2772](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2772) |
| trigger | `crm_campos_validate` | [supabase/schema.sql · linha 2774](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2774) |
| function | `public.crm_filter_clients` | [supabase/schema.sql · linha 2777](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2777) |
| function | `public.crm_filter_options` | [supabase/schema.sql · linha 2787](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2787) |
| view | `public.crm_opportunity_cards` | [supabase/schema.sql · linha 2791](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2791) |
| table | `public.crm_classificacoes` | [supabase/schema.sql · linha 2813](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2813) |
| policy | `crm_classificacao_leitura` | [supabase/schema.sql · linha 2828](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2828) |
| function | `apoiarcred_private.crm_import_clients` | [supabase/schema.sql · linha 2831](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2831) |
| function | `public.crm_import_clients` | [supabase/schema.sql · linha 2890](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2890) |
| view | `public.crm_classificacao_filtros` | [supabase/schema.sql · linha 2898](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2898) |
| function | `public.crm_filter_clients` | [supabase/schema.sql · linha 2905](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2905) |
| function | `public.crm_filter_options` | [supabase/schema.sql · linha 2915](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2915) |
| function | `apoiarcred_private.crm_reset_account` | [supabase/schema.sql · linha 2923](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2923) |
| function | `public.crm_reset_account` | [supabase/schema.sql · linha 2991](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L2991) |
| table | `public.crm_catalogo_importacao` | [supabase/schema.sql · linha 3002](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3002) |
| policy | `crm_catalogo_importacao_leitura` | [supabase/schema.sql · linha 3013](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3013) |
| function | `apoiarcred_private.crm_import_catalog_clients` | [supabase/schema.sql · linha 3141](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3141) |
| function | `public.crm_import_catalog_clients` | [supabase/schema.sql · linha 3168](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3168) |
| table | `public.crm_import_requests` | [supabase/schema.sql · linha 3295](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3295) |
| table | `public.amigoz_jobs` | [supabase/schema.sql · linha 3303](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3303) |
| policy | `amigoz_jobs_owner` | [supabase/schema.sql · linha 3318](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3318) |
| index | `amigoz_jobs_pending` | [supabase/schema.sql · linha 3319](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3319) |
| index | `amigoz_jobs_client` | [supabase/schema.sql · linha 3320](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3320) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/schema.sql · linha 3322](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3322) |
| function | `public.crm_import_and_start` | [supabase/schema.sql · linha 3369](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3369) |
| function | `public.claim_amigoz_import_job` | [supabase/schema.sql · linha 3374](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3374) |
| function | `public.finish_amigoz_import_job` | [supabase/schema.sql · linha 3393](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3393) |
| view | `public.crm_consultas` | [supabase/schema.sql · linha 3404](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3404) |
| trigger | `crm_sync_amigoz` | [supabase/schema.sql · linha 3419](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3419) |
| function | `apoiarcred_private.guard_amigoz_client_delete` | [supabase/schema.sql · linha 3422](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3422) |
| trigger | `guard_amigoz_client_delete` | [supabase/schema.sql · linha 3432](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3432) |
| function | `public.start_amigoz_individual` | [supabase/schema.sql · linha 3437](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3437) |
| function | `apoiarcred_private.crm_consolidar` | [supabase/schema.sql · linha 3463](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3463) |
| function | `apoiarcred_private.crm_enriquecer_consulta` | [supabase/schema.sql · linha 3494](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3494) |
| trigger | `zz_crm_enriquecer_digi` | [supabase/schema.sql · linha 3543](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3543) |
| trigger | `zz_crm_enriquecer_amigoz` | [supabase/schema.sql · linha 3545](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3545) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/schema.sql · linha 3547](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3547) |
| view | `public.crm_opportunity_cards` | [supabase/schema.sql · linha 3601](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3601) |
| function | `public.crm_marcar_exportadas` | [supabase/schema.sql · linha 3634](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3634) |
| function | `apoiarcred_private.crm_consolidar` | [supabase/schema.sql · linha 3656](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3656) |
| function | `apoiarcred_private.crm_consolidar_margem_consigx` | [supabase/schema.sql · linha 3699](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3699) |
| trigger | `zz_crm_oportunidade_consigx` | [supabase/schema.sql · linha 3711](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3711) |
| function | `apoiarcred_private.api_route` | [supabase/schema.sql · linha 3744](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3744) |
| function | `public.crm_export_opportunities` | [supabase/schema.sql · linha 3837](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3837) |
| view | `public.crm_opportunity_cards` | [supabase/schema.sql · linha 3864](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3864) |
| table | `public.crm_exportacoes` | [supabase/schema.sql · linha 3876](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3876) |
| policy | `crm_exportacoes_own_read` | [supabase/schema.sql · linha 3888](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3888) |
| policy | `crm_exportacoes_own_insert` | [supabase/schema.sql · linha 3889](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3889) |
| index | `crm_exportacoes_referencia` | [supabase/schema.sql · linha 3892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3892) |
| index | `crm_exportacoes_conta_data` | [supabase/schema.sql · linha 3893](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3893) |
| function | `public.crm_registrar_exportacao` | [supabase/schema.sql · linha 3895](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3895) |
| table | `public.crm_dados_cliente` | [supabase/schema.sql · linha 3923](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3923) |
| policy | `crm_dados_cliente_leitura` | [supabase/schema.sql · linha 3934](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3934) |
| function | `apoiarcred_private.crm_sync_dados_cliente` | [supabase/schema.sql · linha 3936](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3936) |
| trigger | `crm_dados_cliente_sync` | [supabase/schema.sql · linha 3955](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3955) |
| function | `public.crm_filtrar_kanban` | [supabase/schema.sql · linha 3968](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3968) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/schema.sql · linha 3984](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L3984) |
| function | `public.crm_export_opportunities` | [supabase/schema.sql · linha 4060](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4060) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/schema.sql · linha 4086](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4086) |
| function | `apoiarcred_private.api_route` | [supabase/schema.sql · linha 4180](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4180) |
| table | `public.crm_margens_vinculo` | [supabase/schema.sql · linha 4245](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4245) |
| policy | `crm_margens_leitura` | [supabase/schema.sql · linha 4255](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4255) |
| function | `apoiarcred_private.crm_store_margin` | [supabase/schema.sql · linha 4257](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4257) |
| function | `apoiarcred_private.crm_import_errors` | [supabase/schema.sql · linha 4274](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4274) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/schema.sql · linha 4324](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4324) |
| function | `public.crm_preview_import` | [supabase/schema.sql · linha 4433](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4433) |
| function | `public.crm_confirm_import` | [supabase/schema.sql · linha 4462](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4462) |
| function | `public.crm_import_history` | [supabase/schema.sql · linha 4474](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4474) |
| function | `apoiarcred_private.api_route` | [supabase/schema.sql · linha 4484](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4484) |
| function | `apoiarcred_private.crm_sync_margin_snapshot` | [supabase/schema.sql · linha 4558](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4558) |
| trigger | `crm_sync_margin_snapshot` | [supabase/schema.sql · linha 4581](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4581) |
| table | `apoiarcred_private.digimais_preferences` | [supabase/schema.sql · linha 4595](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4595) |
| table | `apoiarcred_private.digimais_api_config` | [supabase/schema.sql · linha 4604](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4604) |
| index | `consulta_jobs_api_queue` | [supabase/schema.sql · linha 4611](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4611) |
| function | `apoiarcred_private.manage_digimais_pilot` | [supabase/schema.sql · linha 4613](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4613) |
| function | `public.manage_digimais_pilot` | [supabase/schema.sql · linha 4635](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4635) |
| function | `apoiarcred_private.assign_digimais_execution` | [supabase/schema.sql · linha 4638](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4638) |
| trigger | `assign_digimais_execution` | [supabase/schema.sql · linha 4647](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4647) |
| function | `public.get_digimais_api_config` | [supabase/schema.sql · linha 4648](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4648) |
| function | `public.claim_consulta_job_for_api` | [supabase/schema.sql · linha 4651](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4651) |
| function | `public.claim_consulta_job_for_robot` | [supabase/schema.sql · linha 4670](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4670) |
| function | `public.claim_consulta_job` | [supabase/schema.sql · linha 4684](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4684) |
| table | `public.amigoz_model_versions` | [supabase/schema.sql · linha 4699](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4699) |
| policy | `amigoz_model_read` | [supabase/schema.sql · linha 4708](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4708) |
| table | `public.amigoz_coefficient_simulations` | [supabase/schema.sql · linha 4722](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4722) |
| index | `amigoz_coefficient_history` | [supabase/schema.sql · linha 4733](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4733) |
| policy | `amigoz_coefficient_owner` | [supabase/schema.sql · linha 4737](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4737) |
| function | `apoiarcred_private.amigoz_save_model` | [supabase/schema.sql · linha 4740](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4740) |
| function | `public.amigoz_save_model` | [supabase/schema.sql · linha 4772](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4772) |
| function | `public.amigoz_simulation_context` | [supabase/schema.sql · linha 4776](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4776) |
| function | `apoiarcred_private.amigoz_coefficient_calculate` | [supabase/schema.sql · linha 4829](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4829) |
| function | `public.amigoz_simular_coeficientes` | [supabase/schema.sql · linha 4869](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4869) |
| function | `public.amigoz_exportar_estimativas` | [supabase/schema.sql · linha 4939](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4939) |
| function | `public.simular_amigoz_price` | [supabase/schema.sql · linha 4960](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4960) |
| table | `public.amigoz_comissoes_tabela` | [supabase/schema.sql · linha 4993](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L4993) |
| policy | `amigoz_table_commission_read` | [supabase/schema.sql · linha 5003](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5003) |
| function | `apoiarcred_private.amigoz_save_tables` | [supabase/schema.sql · linha 5006](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5006) |
| function | `public.amigoz_save_tables` | [supabase/schema.sql · linha 5070](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5070) |
| function | `apoiarcred_private.amigoz_coefficient_calculate` | [supabase/schema.sql · linha 5077](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5077) |
| function | `public.amigoz_simular_coeficientes` | [supabase/schema.sql · linha 5115](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5115) |
| table | `public.crm_etapas` | [supabase/schema.sql · linha 5196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5196) |
| policy | `crm_etapas_conta` | [supabase/schema.sql · linha 5211](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5211) |
| function | `apoiarcred_private.crm_semear_etapas` | [supabase/schema.sql · linha 5216](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5216) |
| index | `crm_oportunidades_etapa_pagina` | [supabase/schema.sql · linha 5239](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5239) |
| table | `public.crm_movimentacoes` | [supabase/schema.sql · linha 5241](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5241) |
| index | `crm_movimentacoes_pagina` | [supabase/schema.sql · linha 5252](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5252) |
| policy | `crm_movimentacoes_conta` | [supabase/schema.sql · linha 5254](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5254) |
| function | `apoiarcred_private.crm_sincronizar_etapa` | [supabase/schema.sql · linha 5258](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5258) |
| trigger | `crm_sincronizar_etapa` | [supabase/schema.sql · linha 5284](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5284) |
| function | `public.crm_listar_etapas` | [supabase/schema.sql · linha 5287](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5287) |
| function | `public.crm_salvar_etapa` | [supabase/schema.sql · linha 5298](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5298) |
| function | `public.crm_mover_etapa` | [supabase/schema.sql · linha 5340](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5340) |
| view | `public.crm_opportunity_cards` | [supabase/schema.sql · linha 5359](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5359) |
| function | `public.crm_export_opportunities` | [supabase/schema.sql · linha 5372](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5372) |
| function | `public.crm_marcar_exportadas` | [supabase/schema.sql · linha 5391](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5391) |
| function | `public.crm_kanban` | [supabase/schema.sql · linha 5404](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5404) |
| function | `apoiarcred_private.crm_cliente_perfil` | [supabase/schema.sql · linha 5432](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5432) |
| function | `apoiarcred_private.api_route_oportunidades` | [supabase/schema.sql · linha 5449](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5449) |
| function | `apoiarcred_private.api_route` | [supabase/schema.sql · linha 5540](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5540) |
| function | `public.api_execute` | [supabase/schema.sql · linha 5624](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5624) |
| function | `apoiarcred_private.api_route_oportunidades` | [supabase/schema.sql · linha 5666](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5666) |
| function | `apoiarcred_private.crm_sincronizar_etapa` | [supabase/schema.sql · linha 5757](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5757) |
| function | `public.api_execute` | [supabase/schema.sql · linha 5784](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5784) |
| function | `apoiarcred_private.manage_api_tokens` | [supabase/schema.sql · linha 5824](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5824) |
| function | `public.api_execute` | [supabase/schema.sql · linha 5848](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5848) |
| function | `public.crm_listar_exportacao` | [supabase/schema.sql · linha 5892](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5892) |
| function | `public.crm_convenios_exportacao` | [supabase/schema.sql · linha 5914](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5914) |
| function | `public.amigoz_exportar_estimativas` | [supabase/schema.sql · linha 5933](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5933) |
| function | `public.crm_selecionar_etapa` | [supabase/schema.sql · linha 5953](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5953) |
| function | `public.crm_acao_lote` | [supabase/schema.sql · linha 5975](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L5975) |
| table | `public.painel_exclusoes` | [supabase/schema.sql · linha 6014](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6014) |
| index | `painel_exclusoes_sync` | [supabase/schema.sql · linha 6019](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6019) |
| policy | `painel_exclusoes_conta` | [supabase/schema.sql · linha 6023](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6023) |
| function | `apoiarcred_private.painel_marcar_mudanca` | [supabase/schema.sql · linha 6025](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6025) |
| index | `consulta_jobs_painel_sync` | [supabase/schema.sql · linha 6043](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6043) |
| trigger | `painel_marcar_mudanca` | [supabase/schema.sql · linha 6044](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6044) |
| index | `tjba_jobs_painel_sync` | [supabase/schema.sql · linha 6047](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6047) |
| trigger | `painel_marcar_mudanca` | [supabase/schema.sql · linha 6048](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6048) |
| index | `consulta_lotes_painel_sync` | [supabase/schema.sql · linha 6051](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6051) |
| trigger | `painel_marcar_mudanca` | [supabase/schema.sql · linha 6052](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6052) |
| index | `tjba_lotes_painel_sync` | [supabase/schema.sql · linha 6055](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6055) |
| trigger | `painel_marcar_mudanca` | [supabase/schema.sql · linha 6056](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6056) |
| function | `public.painel_consultas_sync` | [supabase/schema.sql · linha 6059](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6059) |
| function | `public.painel_consultas_sync` | [supabase/schema.sql · linha 6111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6111) |
| function | `apoiarcred_private.can_use_digimais_api` | [supabase/schema.sql · linha 6160](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6160) |
| function | `apoiarcred_private.assign_digimais_execution` | [supabase/schema.sql · linha 6172](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6172) |
| function | `public.claim_consulta_job_for_api` | [supabase/schema.sql · linha 6182](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6182) |
| function | `apoiarcred_private.admin_digimais_access` | [supabase/schema.sql · linha 6203](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6203) |
| function | `public.admin_digimais_access` | [supabase/schema.sql · linha 6228](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/schema.sql#L6228) |
| function | `public.create_consulta_campaign` | [supabase/upgrade_admin_campaign_limits.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_admin_campaign_limits.sql#L2) |
| function | `public.create_tjba_campaign` | [supabase/upgrade_admin_campaign_limits.sql · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_admin_campaign_limits.sql#L18) |
| function | `public.create_consigx_campaign` | [supabase/upgrade_admin_campaign_limits.sql · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_admin_campaign_limits.sql#L32) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_admin_campaign_limits.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_admin_campaign_limits.sql#L46) |
| table | `public.amigoz_comissoes` | [supabase/upgrade_amigoz.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz.sql#L2) |
| policy | `own_commissions` | [supabase/upgrade_amigoz.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz.sql#L12) |
| table | `public.amigoz_simulacoes` | [supabase/upgrade_amigoz.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz.sql#L14) |
| index | `amigoz_simulacoes_owner_job` | [supabase/upgrade_amigoz.sql · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz.sql#L21) |
| index | `amigoz_simulacoes_job` | [supabase/upgrade_amigoz.sql · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz.sql#L22) |
| policy | `own_simulations` | [supabase/upgrade_amigoz.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz.sql#L27) |
| function | `public.simular_amigoz` | [supabase/upgrade_amigoz.sql · linha 30](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz.sql#L30) |
| function | `public.amigoz_simulation_context` | [supabase/upgrade_amigoz_agreement_context.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_agreement_context.sql#L1) |
| function | `public.crm_criar_campanha_amigoz` | [supabase/upgrade_amigoz_campanhas_avulsas.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_campanhas_avulsas.sql#L3) |
| function | `public.crm_listar_campanhas_amigoz` | [supabase/upgrade_amigoz_campanhas_avulsas.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_campanhas_avulsas.sql#L19) |
| table | `public.amigoz_model_versions` | [supabase/upgrade_amigoz_coefficients.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L2) |
| policy | `amigoz_model_read` | [supabase/upgrade_amigoz_coefficients.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L11) |
| table | `public.amigoz_coefficient_simulations` | [supabase/upgrade_amigoz_coefficients.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L25) |
| index | `amigoz_coefficient_history` | [supabase/upgrade_amigoz_coefficients.sql · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L36) |
| policy | `amigoz_coefficient_owner` | [supabase/upgrade_amigoz_coefficients.sql · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L40) |
| function | `apoiarcred_private.amigoz_save_model` | [supabase/upgrade_amigoz_coefficients.sql · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L43) |
| function | `public.amigoz_save_model` | [supabase/upgrade_amigoz_coefficients.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L75) |
| function | `public.amigoz_simulation_context` | [supabase/upgrade_amigoz_coefficients.sql · linha 79](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L79) |
| function | `apoiarcred_private.amigoz_coefficient_calculate` | [supabase/upgrade_amigoz_coefficients.sql · linha 127](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L127) |
| function | `public.amigoz_simular_coeficientes` | [supabase/upgrade_amigoz_coefficients.sql · linha 167](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L167) |
| function | `public.amigoz_exportar_estimativas` | [supabase/upgrade_amigoz_coefficients.sql · linha 237](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L237) |
| function | `public.simular_amigoz_price` | [supabase/upgrade_amigoz_coefficients.sql · linha 258](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_coefficients.sql#L258) |
| function | `apoiarcred_private.amigoz_coefficient_calculate` | [supabase/upgrade_amigoz_debt_cash.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_debt_cash.sql#L4) |
| function | `public.amigoz_simulation_context` | [supabase/upgrade_amigoz_imported_agreement.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_imported_agreement.sql#L1) |
| function | `public.start_amigoz_individual` | [supabase/upgrade_amigoz_individual_history.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_individual_history.sql#L2) |
| function | `apoiarcred_private.amigoz_price` | [supabase/upgrade_amigoz_price.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_price.sql#L1) |
| function | `public.simular_amigoz_price` | [supabase/upgrade_amigoz_price.sql · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_price.sql#L37) |
| function | `public.simular_amigoz` | [supabase/upgrade_amigoz_price.sql · linha 59](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_price.sql#L59) |
| function | `public.crm_status_reuso` | [supabase/upgrade_amigoz_reuso_status.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_reuso_status.sql#L1) |
| table | `public.amigoz_comissoes_tabela` | [supabase/upgrade_amigoz_tables.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L1) |
| policy | `amigoz_table_commission_read` | [supabase/upgrade_amigoz_tables.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L11) |
| function | `apoiarcred_private.amigoz_save_tables` | [supabase/upgrade_amigoz_tables.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L14) |
| function | `public.amigoz_save_tables` | [supabase/upgrade_amigoz_tables.sql · linha 78](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L78) |
| function | `apoiarcred_private.amigoz_coefficient_calculate` | [supabase/upgrade_amigoz_tables.sql · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L85) |
| function | `public.amigoz_simular_coeficientes` | [supabase/upgrade_amigoz_tables.sql · linha 123](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_amigoz_tables.sql#L123) |
| table | `apoiarcred_private.api_tokens` | [supabase/upgrade_api.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L4) |
| index | `api_tokens_owner` | [supabase/upgrade_api.sql · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L10) |
| table | `apoiarcred_private.api_idempotency` | [supabase/upgrade_api.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L11) |
| policy | `api_tokens_service` | [supabase/upgrade_api.sql · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L21) |
| policy | `api_idempotency_service` | [supabase/upgrade_api.sql · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L22) |
| function | `apoiarcred_private.manage_api_tokens` | [supabase/upgrade_api.sql · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L23) |
| function | `public.manage_api_tokens` | [supabase/upgrade_api.sql · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L48) |
| view | `apoiarcred_private.api_campaign_rows` | [supabase/upgrade_api.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L52) |
| view | `apoiarcred_private.api_lead_rows` | [supabase/upgrade_api.sql · linha 55](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L55) |
| function | `apoiarcred_private.api_response` | [supabase/upgrade_api.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L62) |
| function | `apoiarcred_private.api_error` | [supabase/upgrade_api.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L63) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_api.sql · linha 67](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L67) |
| function | `public.api_execute` | [supabase/upgrade_api.sql · linha 162](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api.sql#L162) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_api_campaign_leads.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_campaign_leads.sql#L2) |
| view | `apoiarcred_private.api_campaign_rows` | [supabase/upgrade_api_campanha_convenio.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_campanha_convenio.sql#L2) |
| function | `apoiarcred_private.api_route_legacy` | [supabase/upgrade_api_campanha_convenio.sql · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_campanha_convenio.sql#L22) |
| function | `apoiarcred_private.api_format_cpf` | [supabase/upgrade_api_cpf_format.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_cpf_format.sql#L2) |
| function | `apoiarcred_private.api_response` | [supabase/upgrade_api_cpf_format.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_cpf_format.sql#L14) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_api_oportunidades.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_api_oportunidades.sql#L4) |
| function | `apoiarcred_private.track_campaign_failures` | [supabase/upgrade_campaign_failure_pause.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L11) |
| function | `apoiarcred_private.reset_campaign_failures` | [supabase/upgrade_campaign_failure_pause.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L34) |
| trigger | `track_campaign_failures` | [supabase/upgrade_campaign_failure_pause.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L46) |
| trigger | `track_campaign_failures` | [supabase/upgrade_campaign_failure_pause.sql · linha 48](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L48) |
| trigger | `reset_campaign_failures` | [supabase/upgrade_campaign_failure_pause.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L50) |
| trigger | `reset_campaign_failures` | [supabase/upgrade_campaign_failure_pause.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L52) |
| function | `apoiarcred_private.retry_consulta_campaign` | [supabase/upgrade_campaign_failure_pause.sql · linha 56](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L56) |
| function | `apoiarcred_private.guard_partner_job` | [supabase/upgrade_campaign_failure_pause.sql · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L71) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_campaign_failure_pause.sql · linha 84](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L84) |
| function | `apoiarcred_private.wh_capture` | [supabase/upgrade_campaign_failure_pause.sql · linha 178](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L178) |
| function | `apoiarcred_private.wh_campaigns` | [supabase/upgrade_campaign_failure_pause.sql · linha 200](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L200) |
| function | `apoiarcred_private.manage_webhooks` | [supabase/upgrade_campaign_failure_pause.sql · linha 219](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_failure_pause.sql#L219) |
| index | `consulta_jobs_lot_order` | [supabase/upgrade_campaign_ux.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L3) |
| index | `tjba_jobs_lot_order` | [supabase/upgrade_campaign_ux.sql · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L6) |
| function | `apoiarcred_private.set_campaign_paused` | [supabase/upgrade_campaign_ux.sql · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L7) |
| function | `public.set_campaign_paused` | [supabase/upgrade_campaign_ux.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L19) |
| function | `public.claim_consulta_job` | [supabase/upgrade_campaign_ux.sql · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L22) |
| function | `public.claim_tjba_job` | [supabase/upgrade_campaign_ux.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L34) |
| function | `public.create_consulta_campaign` | [supabase/upgrade_campaign_ux.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L47) |
| function | `public.create_consigx_campaign` | [supabase/upgrade_campaign_ux.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campaign_ux.sql#L62) |
| function | `public.create_consulta_campaign` | [supabase/upgrade_campanhas.sql · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campanhas.sql#L6) |
| function | `apoiarcred_private.retry_consulta_campaign` | [supabase/upgrade_campanhas.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campanhas.sql#L27) |
| function | `public.retry_consulta_campaign` | [supabase/upgrade_campanhas.sql · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_campanhas.sql#L44) |
| function | `apoiarcred_private.assign_consigx_convenio` | [supabase/upgrade_consigx.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx.sql#L3) |
| trigger | `assign_consigx_convenio` | [supabase/upgrade_consigx.sql · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx.sql#L10) |
| function | `public.create_consigx_campaign` | [supabase/upgrade_consigx.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx.sql#L11) |
| function | `public.manage_consigx_access` | [supabase/upgrade_consigx_access_editor.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx_access_editor.sql#L3) |
| function | `apoiarcred_private.tjba_robot_login` | [supabase/upgrade_consigx_require_robot_login.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx_require_robot_login.sql#L3) |
| function | `apoiarcred_private.claim_consigx_for_robot` | [supabase/upgrade_consigx_require_robot_login.sql · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consigx_require_robot_login.sql#L17) |
| index | `consulta_jobs_requeue_running_idx` | [supabase/upgrade_consulta_jobs_requeue_index.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_consulta_jobs_requeue_index.sql#L2) |
| function | `apoiarcred_private.api_route_oportunidades` | [supabase/upgrade_crm_auditoria_e_totais.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L4) |
| function | `apoiarcred_private.crm_sincronizar_etapa` | [supabase/upgrade_crm_auditoria_e_totais.sql · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L95) |
| function | `public.api_execute` | [supabase/upgrade_crm_auditoria_e_totais.sql · linha 122](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_auditoria_e_totais.sql#L122) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_crm_busca_telefone.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_busca_telefone.sql#L1) |
| table | `public.crm_cadastros` | [supabase/upgrade_crm_cadastros.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L3) |
| table | `public.crm_vinculos` | [supabase/upgrade_crm_cadastros.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L14) |
| policy | `crm_cadastro_leitura` | [supabase/upgrade_crm_cadastros.sql · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L32) |
| policy | `crm_vinculo_leitura` | [supabase/upgrade_crm_cadastros.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L35) |
| function | `apoiarcred_private.crm_sync_job` | [supabase/upgrade_crm_cadastros.sql · linha 61](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L61) |
| trigger | `crm_sync_consulta` | [supabase/upgrade_crm_cadastros.sql · linha 100](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L100) |
| trigger | `crm_sync_tjba` | [supabase/upgrade_crm_cadastros.sql · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L103) |
| view | `public.crm_clientes` | [supabase/upgrade_crm_cadastros.sql · linha 106](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_cadastros.sql#L106) |
| table | `public.crm_campanhas_reuso` | [supabase/upgrade_crm_campanhas_reuso.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_campanhas_reuso.sql#L2) |
| policy | `reuso_leitura` | [supabase/upgrade_crm_campanhas_reuso.sql · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_campanhas_reuso.sql#L10) |
| index | `crm_campanhas_reuso_origem` | [supabase/upgrade_crm_campanhas_reuso.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_campanhas_reuso.sql#L11) |
| function | `apoiarcred_private.crm_base_reuso` | [supabase/upgrade_crm_campanhas_reuso.sql · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_campanhas_reuso.sql#L13) |
| function | `public.crm_prever_reuso` | [supabase/upgrade_crm_campanhas_reuso.sql · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_campanhas_reuso.sql#L43) |
| function | `public.crm_confirmar_reuso` | [supabase/upgrade_crm_campanhas_reuso.sql · linha 66](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_campanhas_reuso.sql#L66) |
| function | `public.crm_status_reuso` | [supabase/upgrade_crm_campanhas_reuso.sql · linha 110](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_campanhas_reuso.sql#L110) |
| table | `public.crm_catalogo_importacao` | [supabase/upgrade_crm_catalogo_importacao.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_catalogo_importacao.sql#L3) |
| policy | `crm_catalogo_importacao_leitura` | [supabase/upgrade_crm_catalogo_importacao.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_catalogo_importacao.sql#L14) |
| function | `apoiarcred_private.crm_import_catalog_clients` | [supabase/upgrade_crm_catalogo_importacao.sql · linha 142](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_catalogo_importacao.sql#L142) |
| function | `public.crm_import_catalog_clients` | [supabase/upgrade_crm_catalogo_importacao.sql · linha 169](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_catalogo_importacao.sql#L169) |
| view | `public.crm_consultas` | [supabase/upgrade_crm_clientes.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_clientes.sql#L4) |
| view | `public.crm_clientes` | [supabase/upgrade_crm_clientes.sql · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_clientes.sql#L16) |
| index | `consulta_jobs_crm_cpf` | [supabase/upgrade_crm_clientes.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_clientes.sql#L29) |
| index | `tjba_jobs_crm_cpf` | [supabase/upgrade_crm_clientes.sql · linha 30](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_clientes.sql#L30) |
| table | `public.crm_oportunidades` | [supabase/upgrade_crm_comercial.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_comercial.sql#L3) |
| policy | `crm_oportunidades_owner` | [supabase/upgrade_crm_comercial.sql · linha 20](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_comercial.sql#L20) |
| policy | `crm_oportunidades_update` | [supabase/upgrade_crm_comercial.sql · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_comercial.sql#L23) |
| policy | `crm_oportunidades_insert` | [supabase/upgrade_crm_comercial.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_comercial.sql#L27) |
| index | `crm_oportunidades_lista` | [supabase/upgrade_crm_comercial.sql · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_comercial.sql#L43) |
| table | `public.crm_dados_cliente` | [supabase/upgrade_crm_dados_cliente.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_dados_cliente.sql#L2) |
| policy | `crm_dados_cliente_leitura` | [supabase/upgrade_crm_dados_cliente.sql · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_dados_cliente.sql#L13) |
| function | `apoiarcred_private.crm_sync_dados_cliente` | [supabase/upgrade_crm_dados_cliente.sql · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_dados_cliente.sql#L15) |
| trigger | `crm_dados_cliente_sync` | [supabase/upgrade_crm_dados_cliente.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_dados_cliente.sql#L34) |
| function | `public.crm_filtrar_kanban` | [supabase/upgrade_crm_dados_cliente.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_dados_cliente.sql#L47) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/upgrade_crm_dados_cliente.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_dados_cliente.sql#L63) |
| function | `public.crm_export_opportunities` | [supabase/upgrade_crm_dados_cliente.sql · linha 139](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_dados_cliente.sql#L139) |
| function | `apoiarcred_private.crm_consolidar` | [supabase/upgrade_crm_enriquecimento.sql · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_enriquecimento.sql#L9) |
| function | `apoiarcred_private.crm_enriquecer_consulta` | [supabase/upgrade_crm_enriquecimento.sql · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_enriquecimento.sql#L40) |
| trigger | `zz_crm_enriquecer_digi` | [supabase/upgrade_crm_enriquecimento.sql · linha 89](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_enriquecimento.sql#L89) |
| trigger | `zz_crm_enriquecer_amigoz` | [supabase/upgrade_crm_enriquecimento.sql · linha 91](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_enriquecimento.sql#L91) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/upgrade_crm_enriquecimento.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_enriquecimento.sql#L93) |
| view | `public.crm_opportunity_cards` | [supabase/upgrade_crm_enriquecimento.sql · linha 147](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_enriquecimento.sql#L147) |
| table | `public.crm_etapas` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L2) |
| policy | `crm_etapas_conta` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L17) |
| function | `apoiarcred_private.crm_semear_etapas` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L22) |
| index | `crm_oportunidades_etapa_pagina` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 45](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L45) |
| table | `public.crm_movimentacoes` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L47) |
| index | `crm_movimentacoes_pagina` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L58) |
| policy | `crm_movimentacoes_conta` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L60) |
| function | `apoiarcred_private.crm_sincronizar_etapa` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 64](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L64) |
| trigger | `crm_sincronizar_etapa` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 90](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L90) |
| function | `public.crm_listar_etapas` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L93) |
| function | `public.crm_salvar_etapa` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 104](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L104) |
| function | `public.crm_mover_etapa` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 146](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L146) |
| view | `public.crm_opportunity_cards` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 165](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L165) |
| function | `public.crm_export_opportunities` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 178](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L178) |
| function | `public.crm_marcar_exportadas` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 197](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L197) |
| function | `public.crm_kanban` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 210](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L210) |
| function | `apoiarcred_private.crm_cliente_perfil` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 238](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L238) |
| function | `apoiarcred_private.api_route_oportunidades` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 255](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L255) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 346](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L346) |
| function | `public.api_execute` | [supabase/upgrade_crm_etapas_e_clientes_api.sql · linha 430](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_etapas_e_clientes_api.sql#L430) |
| function | `public.crm_export_opportunities` | [supabase/upgrade_crm_export_filtros.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_export_filtros.sql#L2) |
| function | `public.crm_marcar_exportadas` | [supabase/upgrade_crm_exportacao.sql · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_exportacao.sql#L6) |
| view | `public.crm_opportunity_cards` | [supabase/upgrade_crm_ficha_exportacoes.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L4) |
| table | `public.crm_exportacoes` | [supabase/upgrade_crm_ficha_exportacoes.sql · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L16) |
| policy | `crm_exportacoes_own_read` | [supabase/upgrade_crm_ficha_exportacoes.sql · linha 28](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L28) |
| policy | `crm_exportacoes_own_insert` | [supabase/upgrade_crm_ficha_exportacoes.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L29) |
| index | `crm_exportacoes_referencia` | [supabase/upgrade_crm_ficha_exportacoes.sql · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L32) |
| index | `crm_exportacoes_conta_data` | [supabase/upgrade_crm_ficha_exportacoes.sql · linha 33](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L33) |
| function | `public.crm_registrar_exportacao` | [supabase/upgrade_crm_ficha_exportacoes.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_ficha_exportacoes.sql#L35) |
| function | `public.create_consigx_campaign` | [supabase/upgrade_crm_import_20k.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_20k.sql#L2) |
| function | `public.create_consulta_campaign` | [supabase/upgrade_crm_import_20k.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_20k.sql#L19) |
| function | `apoiarcred_private.crm_import_clients` | [supabase/upgrade_crm_import_20k.sql · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_20k.sql#L37) |
| function | `apoiarcred_private.crm_import_errors` | [supabase/upgrade_crm_import_20k.sql · linha 96](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_20k.sql#L96) |
| table | `public.crm_import_requests` | [supabase/upgrade_crm_import_auto.sql · linha 117](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L117) |
| table | `public.amigoz_jobs` | [supabase/upgrade_crm_import_auto.sql · linha 125](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L125) |
| policy | `amigoz_jobs_owner` | [supabase/upgrade_crm_import_auto.sql · linha 140](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L140) |
| index | `amigoz_jobs_pending` | [supabase/upgrade_crm_import_auto.sql · linha 141](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L141) |
| index | `amigoz_jobs_client` | [supabase/upgrade_crm_import_auto.sql · linha 142](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L142) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/upgrade_crm_import_auto.sql · linha 144](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L144) |
| function | `public.crm_import_and_start` | [supabase/upgrade_crm_import_auto.sql · linha 191](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L191) |
| function | `public.claim_amigoz_import_job` | [supabase/upgrade_crm_import_auto.sql · linha 196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L196) |
| function | `public.finish_amigoz_import_job` | [supabase/upgrade_crm_import_auto.sql · linha 215](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L215) |
| view | `public.crm_consultas` | [supabase/upgrade_crm_import_auto.sql · linha 226](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L226) |
| trigger | `crm_sync_amigoz` | [supabase/upgrade_crm_import_auto.sql · linha 241](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L241) |
| function | `apoiarcred_private.guard_amigoz_client_delete` | [supabase/upgrade_crm_import_auto.sql · linha 244](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L244) |
| trigger | `guard_amigoz_client_delete` | [supabase/upgrade_crm_import_auto.sql · linha 254](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_auto.sql#L254) |
| table | `public.crm_margens_vinculo` | [supabase/upgrade_crm_import_preview.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L2) |
| policy | `crm_margens_leitura` | [supabase/upgrade_crm_import_preview.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L12) |
| function | `apoiarcred_private.crm_store_margin` | [supabase/upgrade_crm_import_preview.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L14) |
| function | `apoiarcred_private.crm_import_errors` | [supabase/upgrade_crm_import_preview.sql · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L31) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/upgrade_crm_import_preview.sql · linha 81](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L81) |
| function | `public.crm_preview_import` | [supabase/upgrade_crm_import_preview.sql · linha 190](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L190) |
| function | `public.crm_confirm_import` | [supabase/upgrade_crm_import_preview.sql · linha 219](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L219) |
| function | `public.crm_import_history` | [supabase/upgrade_crm_import_preview.sql · linha 231](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L231) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_crm_import_preview.sql · linha 241](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L241) |
| function | `apoiarcred_private.crm_sync_margin_snapshot` | [supabase/upgrade_crm_import_preview.sql · linha 315](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L315) |
| trigger | `crm_sync_margin_snapshot` | [supabase/upgrade_crm_import_preview.sql · linha 338](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_preview.sql#L338) |
| function | `public.crm_preview_import` | [supabase/upgrade_crm_import_timeout.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_import_timeout.sql#L2) |
| table | `public.crm_classificacoes` | [supabase/upgrade_crm_importacao.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L3) |
| policy | `crm_classificacao_leitura` | [supabase/upgrade_crm_importacao.sql · linha 18](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L18) |
| function | `apoiarcred_private.crm_import_clients` | [supabase/upgrade_crm_importacao.sql · linha 21](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L21) |
| function | `public.crm_import_clients` | [supabase/upgrade_crm_importacao.sql · linha 80](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L80) |
| view | `public.crm_classificacao_filtros` | [supabase/upgrade_crm_importacao.sql · linha 88](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L88) |
| function | `public.crm_filter_clients` | [supabase/upgrade_crm_importacao.sql · linha 95](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L95) |
| function | `public.crm_filter_options` | [supabase/upgrade_crm_importacao.sql · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_importacao.sql#L105) |
| table | `public.crm_card_settings` | [supabase/upgrade_crm_kanban.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L2) |
| policy | `crm_card_settings_owner` | [supabase/upgrade_crm_kanban.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L12) |
| function | `apoiarcred_private.crm_validate_customization` | [supabase/upgrade_crm_kanban.sql · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L16) |
| trigger | `crm_card_settings_validate` | [supabase/upgrade_crm_kanban.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L47) |
| trigger | `crm_campos_validate` | [supabase/upgrade_crm_kanban.sql · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L49) |
| function | `public.crm_filter_clients` | [supabase/upgrade_crm_kanban.sql · linha 52](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L52) |
| function | `public.crm_filter_options` | [supabase/upgrade_crm_kanban.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L62) |
| view | `public.crm_opportunity_cards` | [supabase/upgrade_crm_kanban.sql · linha 66](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_kanban.sql#L66) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/upgrade_crm_modelos_convenio.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_modelos_convenio.sql#L3) |
| function | `apoiarcred_private.api_route` | [supabase/upgrade_crm_modelos_convenio.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_modelos_convenio.sql#L97) |
| function | `apoiarcred_private.crm_consolidar` | [supabase/upgrade_crm_oportunidades_produto.sql · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_oportunidades_produto.sql#L6) |
| function | `apoiarcred_private.crm_consolidar_margem_consigx` | [supabase/upgrade_crm_oportunidades_produto.sql · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_oportunidades_produto.sql#L49) |
| trigger | `zz_crm_oportunidade_consigx` | [supabase/upgrade_crm_oportunidades_produto.sql · linha 61](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_oportunidades_produto.sql#L61) |
| function | `apoiarcred_private.manage_api_tokens` | [supabase/upgrade_crm_permissoes_api.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L2) |
| function | `public.api_execute` | [supabase/upgrade_crm_permissoes_api.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_permissoes_api.sql#L26) |
| function | `apoiarcred_private.crm_import_and_start` | [supabase/upgrade_crm_preservar_etapa_importacao.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_preservar_etapa_importacao.sql#L2) |
| view | `public.crm_opportunity_cards` | [supabase/upgrade_crm_preservar_etapa_importacao.sql · linha 130](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_preservar_etapa_importacao.sql#L130) |
| function | `public.crm_listar_exportacao` | [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L2) |
| function | `public.crm_convenios_exportacao` | [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L24) |
| function | `public.amigoz_exportar_estimativas` | [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L43) |
| function | `public.crm_selecionar_etapa` | [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L63) |
| function | `public.crm_acao_lote` | [supabase/upgrade_crm_reexportacao_e_acoes_lote.sql · linha 85](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_reexportacao_e_acoes_lote.sql#L85) |
| function | `apoiarcred_private.crm_reset_account` | [supabase/upgrade_crm_zerar_conta.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_zerar_conta.sql#L3) |
| function | `public.crm_reset_account` | [supabase/upgrade_crm_zerar_conta.sql · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_crm_zerar_conta.sql#L71) |
| function | `public.claim_consulta_job_for_api` | [supabase/upgrade_digimais_api_campaign_pause.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_pause.sql#L2) |
| function | `apoiarcred_private.manage_digimais_pilot` | [supabase/upgrade_digimais_api_campaign_switch.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_campaign_switch.sql#L1) |
| function | `apoiarcred_private.manage_digimais_pilot` | [supabase/upgrade_digimais_api_concurrency_100.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L3) |
| function | `public.claim_consulta_job_for_api` | [supabase/upgrade_digimais_api_concurrency_100.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L29) |
| function | `apoiarcred_private.admin_digimais_access` | [supabase/upgrade_digimais_api_concurrency_100.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_100.sql#L50) |
| function | `apoiarcred_private.manage_digimais_pilot` | [supabase/upgrade_digimais_api_concurrency_50.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L12) |
| function | `public.claim_consulta_job_for_api` | [supabase/upgrade_digimais_api_concurrency_50.sql · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_concurrency_50.sql#L38) |
| table | `apoiarcred_private.digimais_preferences` | [supabase/upgrade_digimais_api_pilot.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L2) |
| table | `apoiarcred_private.digimais_api_config` | [supabase/upgrade_digimais_api_pilot.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L11) |
| index | `consulta_jobs_api_queue` | [supabase/upgrade_digimais_api_pilot.sql · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L17) |
| function | `apoiarcred_private.manage_digimais_pilot` | [supabase/upgrade_digimais_api_pilot.sql · linha 19](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L19) |
| function | `public.manage_digimais_pilot` | [supabase/upgrade_digimais_api_pilot.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L34) |
| function | `apoiarcred_private.assign_digimais_execution` | [supabase/upgrade_digimais_api_pilot.sql · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L37) |
| trigger | `assign_digimais_execution` | [supabase/upgrade_digimais_api_pilot.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L46) |
| function | `public.get_digimais_api_config` | [supabase/upgrade_digimais_api_pilot.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L47) |
| function | `public.claim_consulta_job_for_api` | [supabase/upgrade_digimais_api_pilot.sql · linha 50](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L50) |
| function | `public.claim_consulta_job_for_robot` | [supabase/upgrade_digimais_api_pilot.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L69) |
| function | `public.claim_consulta_job` | [supabase/upgrade_digimais_api_pilot.sql · linha 83](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_api_pilot.sql#L83) |
| function | `public.save_digimais_campaign_batch` | [supabase/upgrade_digimais_campaign_batches.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_campaign_batches.sql#L1) |
| table | `apoiarcred_private.queue_maintenance` | [supabase/upgrade_digimais_concurrency.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_concurrency.sql#L4) |
| policy | `queue_maintenance_service` | [supabase/upgrade_digimais_concurrency.sql · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_concurrency.sql#L10) |
| function | `public.consulta_queue_maintenance` | [supabase/upgrade_digimais_concurrency.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_concurrency.sql#L11) |
| function | `public.claim_consulta_job` | [supabase/upgrade_digimais_concurrency.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_concurrency.sql#L26) |
| function | `public.claim_tjba_job` | [supabase/upgrade_digimais_concurrency.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_concurrency.sql#L35) |
| function | `apoiarcred_private.can_use_digimais_api` | [supabase/upgrade_digimais_partner_access.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L3) |
| function | `apoiarcred_private.assign_digimais_execution` | [supabase/upgrade_digimais_partner_access.sql · linha 15](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L15) |
| function | `public.claim_consulta_job_for_api` | [supabase/upgrade_digimais_partner_access.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L25) |
| function | `apoiarcred_private.admin_digimais_access` | [supabase/upgrade_digimais_partner_access.sql · linha 46](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L46) |
| function | `public.admin_digimais_access` | [supabase/upgrade_digimais_partner_access.sql · linha 71](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_partner_access.sql#L71) |
| function | `apoiarcred_private.manage_digimais_pilot` | [supabase/upgrade_digimais_robot_handoff.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_digimais_robot_handoff.sql#L4) |
| policy | `jobs_delete` | [supabase/upgrade_exclusao.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_exclusao.sql#L4) |
| policy | `lotes_delete` | [supabase/upgrade_exclusao.sql · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_exclusao.sql#L6) |
| function | `apoiarcred_private.manage_tjba_robot_credentials` | [supabase/upgrade_fourth_robot.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L12) |
| function | `public.manage_consigx_access` | [supabase/upgrade_fourth_robot.sql · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L40) |
| function | `apoiarcred_private.claim_consigx_for_robot` | [supabase/upgrade_fourth_robot.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L69) |
| function | `public.claim_consulta_job_for_robot` | [supabase/upgrade_fourth_robot.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_fourth_robot.sql#L97) |
| table | `public.vps_monitoramento` | [supabase/upgrade_monitoramento.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_monitoramento.sql#L1) |
| policy | `monitor_read` | [supabase/upgrade_monitoramento.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_monitoramento.sql#L11) |
| table | `public.painel_exclusoes` | [supabase/upgrade_painel_consultas_sync.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L2) |
| index | `painel_exclusoes_sync` | [supabase/upgrade_painel_consultas_sync.sql · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L7) |
| policy | `painel_exclusoes_conta` | [supabase/upgrade_painel_consultas_sync.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L11) |
| function | `apoiarcred_private.painel_marcar_mudanca` | [supabase/upgrade_painel_consultas_sync.sql · linha 13](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L13) |
| index | `consulta_jobs_painel_sync` | [supabase/upgrade_painel_consultas_sync.sql · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L31) |
| trigger | `painel_marcar_mudanca` | [supabase/upgrade_painel_consultas_sync.sql · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L32) |
| index | `tjba_jobs_painel_sync` | [supabase/upgrade_painel_consultas_sync.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L35) |
| trigger | `painel_marcar_mudanca` | [supabase/upgrade_painel_consultas_sync.sql · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L36) |
| index | `consulta_lotes_painel_sync` | [supabase/upgrade_painel_consultas_sync.sql · linha 39](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L39) |
| trigger | `painel_marcar_mudanca` | [supabase/upgrade_painel_consultas_sync.sql · linha 40](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L40) |
| index | `tjba_lotes_painel_sync` | [supabase/upgrade_painel_consultas_sync.sql · linha 43](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L43) |
| trigger | `painel_marcar_mudanca` | [supabase/upgrade_painel_consultas_sync.sql · linha 44](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L44) |
| function | `public.painel_consultas_sync` | [supabase/upgrade_painel_consultas_sync.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_consultas_sync.sql#L47) |
| function | `public.painel_consultas_sync` | [supabase/upgrade_painel_margem_bruta.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_margem_bruta.sql#L2) |
| function | `public.painel_consultas_sync` | [supabase/upgrade_painel_motivo_tjba.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_motivo_tjba.sql#L2) |
| function | `public.painel_consultas_sync` | [supabase/upgrade_painel_sync_page.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_painel_sync_page.sql#L1) |
| function | `apoiarcred_private.access_for` | [supabase/upgrade_partner_amigoz_access.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L4) |
| function | `public.admin_partner_manage` | [supabase/upgrade_partner_amigoz_access.sql · linha 27](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L27) |
| function | `public.authorize_amigoz` | [supabase/upgrade_partner_amigoz_access.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_amigoz_access.sql#L75) |
| function | `apoiarcred_private.can_integrate` | [supabase/upgrade_partner_integrations.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L3) |
| function | `apoiarcred_private.access_for` | [supabase/upgrade_partner_integrations.sql · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L9) |
| function | `public.admin_partner_manage` | [supabase/upgrade_partner_integrations.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L24) |
| function | `apoiarcred_private.manage_api_tokens` | [supabase/upgrade_partner_integrations.sql · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L58) |
| function | `public.api_execute` | [supabase/upgrade_partner_integrations.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L82) |
| function | `apoiarcred_private.manage_webhooks` | [supabase/upgrade_partner_integrations.sql · linha 118](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L118) |
| function | `apoiarcred_private.wh_enqueue` | [supabase/upgrade_partner_integrations.sql · linha 187](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L187) |
| function | `apoiarcred_private.wh_capture` | [supabase/upgrade_partner_integrations.sql · linha 205](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L205) |
| function | `apoiarcred_private.wh_campaigns` | [supabase/upgrade_partner_integrations.sql · linha 227](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L227) |
| function | `apoiarcred_private.wh_claim` | [supabase/upgrade_partner_integrations.sql · linha 246](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_integrations.sql#L246) |
| function | `apoiarcred_private.access_for` | [supabase/upgrade_partner_trials_quota.sql · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L7) |
| function | `apoiarcred_private.check_partner_access` | [supabase/upgrade_partner_trials_quota.sql · linha 29](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L29) |
| function | `public.admin_partner_manage` | [supabase/upgrade_partner_trials_quota.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L62) |
| function | `public.create_consulta_campaign` | [supabase/upgrade_partner_trials_quota.sql · linha 105](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L105) |
| function | `public.create_tjba_campaign` | [supabase/upgrade_partner_trials_quota.sql · linha 121](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L121) |
| function | `public.create_consigx_campaign` | [supabase/upgrade_partner_trials_quota.sql · linha 135](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partner_trials_quota.sql#L135) |
| table | `apoiarcred_private.user_profiles` | [supabase/upgrade_partners.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L2) |
| table | `apoiarcred_private.partner_permissions` | [supabase/upgrade_partners.sql · linha 7](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L7) |
| table | `apoiarcred_private.partner_daily_usage` | [supabase/upgrade_partners.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L14) |
| policy | `profiles_service` | [supabase/upgrade_partners.sql · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L23) |
| policy | `permissions_service` | [supabase/upgrade_partners.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L24) |
| policy | `usage_service` | [supabase/upgrade_partners.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L25) |
| function | `apoiarcred_private.access_for` | [supabase/upgrade_partners.sql · linha 32](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L32) |
| function | `apoiarcred_private.my_access` | [supabase/upgrade_partners.sql · linha 47](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L47) |
| function | `public.my_access` | [supabase/upgrade_partners.sql · linha 51](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L51) |
| function | `apoiarcred_private.is_admin` | [supabase/upgrade_partners.sql · linha 54](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L54) |
| function | `apoiarcred_private.my_admin` | [supabase/upgrade_partners.sql · linha 57](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L57) |
| function | `public.am_i_admin` | [supabase/upgrade_partners.sql · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L60) |
| policy | `monitor_read` | [supabase/upgrade_partners.sql · linha 64](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L64) |
| function | `apoiarcred_private.check_partner_access` | [supabase/upgrade_partners.sql · linha 66](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L66) |
| function | `apoiarcred_private.guard_partner_lot` | [supabase/upgrade_partners.sql · linha 88](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L88) |
| trigger | `guard_partner_lot` | [supabase/upgrade_partners.sql · linha 96](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L96) |
| trigger | `guard_partner_lot` | [supabase/upgrade_partners.sql · linha 97](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L97) |
| function | `apoiarcred_private.guard_partner_job` | [supabase/upgrade_partners.sql · linha 98](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L98) |
| trigger | `guard_partner_job` | [supabase/upgrade_partners.sql · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L111) |
| trigger | `guard_partner_job` | [supabase/upgrade_partners.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L112) |
| function | `public.create_individual_consulta` | [supabase/upgrade_partners.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L114) |
| function | `public.admin_partner_manage` | [supabase/upgrade_partners.sql · linha 128](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L128) |
| function | `public.api_execute` | [supabase/upgrade_partners.sql · linha 163](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_partners.sql#L163) |
| function | `apoiarcred_private.track_campaign_failures` | [supabase/upgrade_pause_exclude_interrupted.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_pause_exclude_interrupted.sql#L2) |
| function | `public.claim_consulta_job_for_robot` | [supabase/upgrade_robot_log_slots.sql · linha 4](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_robot_log_slots.sql#L4) |
| function | `public.create_consulta_campaign` | [supabase/upgrade_servicos.sql · linha 6](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_servicos.sql#L6) |
| function | `public.claim_consulta_job` | [supabase/upgrade_servicos.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_servicos.sql#L14) |
| table | `apoiarcred_private.tjba_robot_credentials` | [supabase/upgrade_shared_robots.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L2) |
| index | `tjba_jobs_running_owner` | [supabase/upgrade_shared_robots.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L14) |
| function | `apoiarcred_private.tjba_robot_login` | [supabase/upgrade_shared_robots.sql · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L16) |
| function | `apoiarcred_private.manage_tjba_robot_credentials` | [supabase/upgrade_shared_robots.sql · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L31) |
| function | `public.manage_tjba_robot_credentials` | [supabase/upgrade_shared_robots.sql · linha 60](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L60) |
| function | `apoiarcred_private.get_tjba_robot_credentials` | [supabase/upgrade_shared_robots.sql · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L68) |
| function | `public.get_tjba_robot_credentials` | [supabase/upgrade_shared_robots.sql · linha 75](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L75) |
| function | `apoiarcred_private.claim_consigx_for_robot` | [supabase/upgrade_shared_robots.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L82) |
| function | `public.claim_tjba_job_for_robot` | [supabase/upgrade_shared_robots.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L112) |
| function | `public.claim_tjba_job` | [supabase/upgrade_shared_robots.sql · linha 119](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_shared_robots.sql#L119) |
| table | `public.tjba_lotes` | [supabase/upgrade_tjba.sql · linha 5](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L5) |
| table | `public.tjba_jobs` | [supabase/upgrade_tjba.sql · linha 10](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L10) |
| index | `tjba_lotes_owner` | [supabase/upgrade_tjba.sql · linha 22](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L22) |
| index | `tjba_jobs_owner` | [supabase/upgrade_tjba.sql · linha 23](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L23) |
| index | `tjba_jobs_lote` | [supabase/upgrade_tjba.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L24) |
| index | `tjba_jobs_queue` | [supabase/upgrade_tjba.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L25) |
| policy | `tjba_lotes_read` | [supabase/upgrade_tjba.sql · linha 33](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L33) |
| policy | `tjba_lotes_insert` | [supabase/upgrade_tjba.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L34) |
| policy | `tjba_lotes_delete` | [supabase/upgrade_tjba.sql · linha 35](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L35) |
| policy | `tjba_jobs_read` | [supabase/upgrade_tjba.sql · linha 36](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L36) |
| policy | `tjba_jobs_delete` | [supabase/upgrade_tjba.sql · linha 37](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L37) |
| policy | `tjba_jobs_insert` | [supabase/upgrade_tjba.sql · linha 38](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L38) |
| function | `public.create_tjba_campaign` | [supabase/upgrade_tjba.sql · linha 39](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L39) |
| function | `public.claim_tjba_job` | [supabase/upgrade_tjba.sql · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L53) |
| table | `public.consulta_tjba_historico` | [supabase/upgrade_tjba.sql · linha 58](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L58) |
| index | `tjba_historico_owner_job` | [supabase/upgrade_tjba.sql · linha 62](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L62) |
| index | `tjba_historico_job` | [supabase/upgrade_tjba.sql · linha 63](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L63) |
| policy | `tjba_history_read` | [supabase/upgrade_tjba.sql · linha 68](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L68) |
| function | `apoiarcred_private.tjba_history` | [supabase/upgrade_tjba.sql · linha 69](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L69) |
| trigger | `save_tjba_history` | [supabase/upgrade_tjba.sql · linha 74](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L74) |
| table | `apoiarcred_private.tjba_credentials` | [supabase/upgrade_tjba.sql · linha 76](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L76) |
| function | `apoiarcred_private.save_tjba_credentials` | [supabase/upgrade_tjba.sql · linha 82](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L82) |
| function | `apoiarcred_private.tjba_credentials_status` | [supabase/upgrade_tjba.sql · linha 96](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L96) |
| function | `apoiarcred_private.get_tjba_credentials` | [supabase/upgrade_tjba.sql · linha 103](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L103) |
| function | `public.save_tjba_credentials` | [supabase/upgrade_tjba.sql · linha 112](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L112) |
| function | `public.tjba_credentials_status` | [supabase/upgrade_tjba.sql · linha 113](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L113) |
| function | `public.get_tjba_credentials` | [supabase/upgrade_tjba.sql · linha 114](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L114) |
| function | `apoiarcred_private.retry_tjba_campaign` | [supabase/upgrade_tjba.sql · linha 119](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L119) |
| function | `public.retry_tjba_campaign` | [supabase/upgrade_tjba.sql · linha 127](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba.sql#L127) |
| policy | `tjba_credentials_no_direct_access` | [supabase/upgrade_tjba_privacy.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba_privacy.sql#L2) |
| function | `apoiarcred_private.cleanup_tjba_secret` | [supabase/upgrade_tjba_privacy.sql · linha 3](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba_privacy.sql#L3) |
| trigger | `cleanup_tjba_secret` | [supabase/upgrade_tjba_privacy.sql · linha 9](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba_privacy.sql#L9) |
| function | `apoiarcred_private.save_tjba_credentials` | [supabase/upgrade_tjba_privacy.sql · linha 14](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba_privacy.sql#L14) |
| function | `apoiarcred_private.tjba_credentials_status` | [supabase/upgrade_tjba_privacy.sql · linha 34](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba_privacy.sql#L34) |
| view | `apoiarcred_private.tjba_credentials_admin` | [supabase/upgrade_tjba_privacy.sql · linha 42](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_tjba_privacy.sql#L42) |
| table | `apoiarcred_private.webhooks` | [supabase/upgrade_webhooks.sql · linha 2](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L2) |
| index | `webhooks_owner` | [supabase/upgrade_webhooks.sql · linha 11](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L11) |
| table | `apoiarcred_private.webhook_events` | [supabase/upgrade_webhooks.sql · linha 12](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L12) |
| index | `webhook_events_owner` | [supabase/upgrade_webhooks.sql · linha 16](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L16) |
| table | `apoiarcred_private.webhook_deliveries` | [supabase/upgrade_webhooks.sql · linha 17](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L17) |
| index | `webhook_delivery_queue` | [supabase/upgrade_webhooks.sql · linha 24](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L24) |
| index | `webhook_delivery_hook` | [supabase/upgrade_webhooks.sql · linha 25](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L25) |
| table | `apoiarcred_private.webhook_attempts` | [supabase/upgrade_webhooks.sql · linha 26](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L26) |
| table | `apoiarcred_private.webhook_campaign_dirty` | [supabase/upgrade_webhooks.sql · linha 31](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L31) |
| function | `apoiarcred_private.wh_client` | [supabase/upgrade_webhooks.sql · linha 42](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L42) |
| function | `apoiarcred_private.wh_result` | [supabase/upgrade_webhooks.sql · linha 49](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L49) |
| function | `apoiarcred_private.wh_enqueue` | [supabase/upgrade_webhooks.sql · linha 53](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L53) |
| function | `apoiarcred_private.wh_capture` | [supabase/upgrade_webhooks.sql · linha 70](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L70) |
| trigger | `capture_webhook` | [supabase/upgrade_webhooks.sql · linha 90](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L90) |
| trigger | `capture_webhook` | [supabase/upgrade_webhooks.sql · linha 91](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L91) |
| function | `apoiarcred_private.wh_campaigns` | [supabase/upgrade_webhooks.sql · linha 93](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L93) |
| function | `apoiarcred_private.manage_webhooks` | [supabase/upgrade_webhooks.sql · linha 111](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L111) |
| function | `apoiarcred_private.wh_claim` | [supabase/upgrade_webhooks.sql · linha 180](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L180) |
| function | `apoiarcred_private.wh_ack` | [supabase/upgrade_webhooks.sql · linha 196](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L196) |
| function | `public.manage_webhooks` | [supabase/upgrade_webhooks.sql · linha 211](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L211) |
| function | `public.claim_webhook_deliveries` | [supabase/upgrade_webhooks.sql · linha 212](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L212) |
| function | `public.ack_webhook_delivery` | [supabase/upgrade_webhooks.sql · linha 213](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L213) |
| function | `apoiarcred_private.wh_cleanup` | [supabase/upgrade_webhooks.sql · linha 220](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L220) |
| trigger | `cleanup_webhook_secret` | [supabase/upgrade_webhooks.sql · linha 222](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/supabase/upgrade_webhooks.sql#L222) |

## Arquivos de infraestrutura, modelos e contratos

| Arquivo | Referência |
| --- | --- |
| `.env.example` | [.env.example · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/.env.example#L1) |
| `.gitignore` | [.gitignore · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/.gitignore#L1) |
| `README.md` | [README.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/README.md#L1) |
| `atualizar.sh` | [atualizar.sh · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/atualizar.sh#L1) |
| `compose.yaml` | [compose.yaml · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/compose.yaml#L1) |
| `deploy/apoiarcred-api-rate.nginx` | [deploy/apoiarcred-api-rate.nginx · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/deploy/apoiarcred-api-rate.nginx#L1) |
| `deploy/apoiarcred-api.nginx` | [deploy/apoiarcred-api.nginx · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/deploy/apoiarcred-api.nginx#L1) |
| `deploy/apoiarcred-api.service` | [deploy/apoiarcred-api.service · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/deploy/apoiarcred-api.service#L1) |
| `deploy/apoiarcred-monitor.service` | [deploy/apoiarcred-monitor.service · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/deploy/apoiarcred-monitor.service#L1) |
| `deploy/apoiarcred-robo.service` | [deploy/apoiarcred-robo.service · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/deploy/apoiarcred-robo.service#L1) |
| `deploy/apoiarcred-webhooks.service` | [deploy/apoiarcred-webhooks.service · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/deploy/apoiarcred-webhooks.service#L1) |
| `dist/api-catalog.json` | [dist/api-catalog.json · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/api-catalog.json#L1) |
| `dist/index.html` | [dist/index.html · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/index.html#L1) |
| `dist/interface.css` | [dist/interface.css · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/interface.css#L1) |
| `dist/modelo-clientes.csv` | [dist/modelo-clientes.csv · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/modelo-clientes.csv#L1) |
| `dist/modelo-importacao.csv` | [dist/modelo-importacao.csv · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/modelo-importacao.csv#L1) |
| `dist/modelo-tjba.csv` | [dist/modelo-tjba.csv · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/modelo-tjba.csv#L1) |
| `dist/openapi.json` | [dist/openapi.json · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/openapi.json#L1) |
| `dist/swagger.html` | [dist/swagger.html · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/swagger.html#L1) |
| `dist/ux-crm.css` | [dist/ux-crm.css · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/dist/ux-crm.css#L1) |
| `docs/amigoz-coefficients.md` | [docs/amigoz-coefficients.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/amigoz-coefficients.md#L1) |
| `docs/api.md` | [docs/api.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/api.md#L1) |
| `docs/crm-validacao.md` | [docs/crm-validacao.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/crm-validacao.md#L1) |
| `docs/digimais-api-pilot.md` | [docs/digimais-api-pilot.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/digimais-api-pilot.md#L1) |
| `docs/diretrizes/accessibility-audit.md` | [docs/diretrizes/accessibility-audit.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/accessibility-audit.md#L1) |
| `docs/diretrizes/ai-slop-check.md` | [docs/diretrizes/ai-slop-check.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/ai-slop-check.md#L1) |
| `docs/diretrizes/design-system-extract.md` | [docs/diretrizes/design-system-extract.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/design-system-extract.md#L1) |
| `docs/diretrizes/discovery-questions.md` | [docs/diretrizes/discovery-questions.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/discovery-questions.md#L1) |
| `docs/diretrizes/frontend-aesthetic-direction.md` | [docs/diretrizes/frontend-aesthetic-direction.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/frontend-aesthetic-direction.md#L1) |
| `docs/diretrizes/system-prompt.md` | [docs/diretrizes/system-prompt.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/system-prompt.md#L1) |
| `docs/diretrizes/ux-ui-v2.md` | [docs/diretrizes/ux-ui-v2.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/ux-ui-v2.md#L1) |
| `docs/diretrizes/wireframe.md` | [docs/diretrizes/wireframe.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/diretrizes/wireframe.md#L1) |
| `docs/interromper-consultas.md` | [docs/interromper-consultas.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/interromper-consultas.md#L1) |
| `docs/plano-diretor.md` | [docs/plano-diretor.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/plano-diretor.md#L1) |
| `docs/webhooks.md` | [docs/webhooks.md · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/docs/webhooks.md#L1) |
| `instalar.sh` | [instalar.sh · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/instalar.sh#L1) |
| `scripts/install-core.sh` | [scripts/install-core.sh · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/install-core.sh#L1) |
| `scripts/update-core.sh` | [scripts/update-core.sh · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/scripts/update-core.sh#L1) |
| `vps/Dockerfile.worker` | [vps/Dockerfile.worker · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/Dockerfile.worker#L1) |
| `vps/amigoz_convenios.json` | [vps/amigoz_convenios.json · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/amigoz_convenios.json#L1) |
| `vps/requirements.txt` | [vps/requirements.txt · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/vps/requirements.txt#L1) |

## Testes SQL disponíveis

A presença do arquivo comprova cobertura prevista, não execução ou sucesso nesta revisão.

- [tests/amigoz_coefficients_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/amigoz_coefficients_database.sql#L1)
- [tests/amigoz_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/amigoz_database.sql#L1)
- [tests/amigoz_debt_cash_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/amigoz_debt_cash_database.sql#L1)
- [tests/amigoz_individual_history_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/amigoz_individual_history_database.sql#L1)
- [tests/api_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/api_database.sql#L1)
- [tests/campaign_ux_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/campaign_ux_database.sql#L1)
- [tests/campaigns_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/campaigns_database.sql#L1)
- [tests/consigx_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/consigx_database.sql#L1)
- [tests/crm_agreement_import_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/crm_agreement_import_database.sql#L1)
- [tests/crm_import_auto_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/crm_import_auto_database.sql#L1)
- [tests/crm_import_catalog_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/crm_import_catalog_database.sql#L1)
- [tests/crm_import_reset_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/crm_import_reset_database.sql#L1)
- [tests/crm_kanban_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/crm_kanban_database.sql#L1)
- [tests/digimais_api_pilot_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/digimais_api_pilot_database.sql#L1)
- [tests/digimais_concurrency_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/digimais_concurrency_database.sql#L1)
- [tests/exclusao_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/exclusao_database.sql#L1)
- [tests/partner_integrations_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/partner_integrations_database.sql#L1)
- [tests/partner_trials_quota_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/partner_trials_quota_database.sql#L1)
- [tests/partners_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/partners_database.sql#L1)
- [tests/services_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/services_database.sql#L1)
- [tests/tjba_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/tjba_database.sql#L1)
- [tests/webhooks_database.sql · linha 1](https://github.com/lcstrindadebr/Promp-01-teste-/blob/9955a723edd4145373175784e893ac96cafa961d/tests/webhooks_database.sql#L1)
