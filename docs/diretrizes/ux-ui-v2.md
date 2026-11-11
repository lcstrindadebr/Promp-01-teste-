# PLANO DE REDESENHO UX/UI — SISTEMA DE CONSULTAS → CRM APOIARCRED

**Versão:** 2.0 — instruções objetivas para desenvolvimento  
**Finalidade:** servir como especificação de execução para um desenvolvedor ou agente de IA  
**Escopo:** modernizar o front-end e integrar visualmente os módulos de consultas, campanhas, clientes e operação comercial  
**Status:** plano de implementação. Este documento **não afirma** que novas funções já foram construídas.

> **INSTRUÇÃO CENTRAL**  
> Modernize a experiência visual do sistema existente, usando **Attio + Linear + Clay** como referências principais. **Não elimine funcionalidades, não invente retornos de API, não altere regras de negócio e não apresente como implementado algo que ainda é apenas planejado.** Cada mudança deve ser validada com os fluxos operacionais reais.

---

## 0. Como interpretar estas instruções

Use os termos abaixo de forma literal:

- **OBRIGATÓRIO:** precisa estar presente ou preservado para uma etapa ser aprovada.
- **RECOMENDADO:** padrão visual preferencial, ajustável se a arquitetura ou o Plano Diretor justificar.
- **CONDICIONAL:** implementar **somente se** o backend, a permissão e a regra de negócio já oferecerem o suporte necessário.
- **FORA DO ESCOPO:** não deve ser criado apenas para atender ao redesenho.

### Ordem de prioridade entre documentos e sistema real

1. **Plano Diretor mais recente do projeto:** determina escopo, arquitetura, funcionalidades, regras de negócio e sequência de implementação.
2. **Contratos e regras já implantados:** banco de dados, APIs, automações, autenticação, status e processamento real não podem ser quebrados.
3. **Este documento:** determina como organizar e apresentar visualmente as funcionalidades.
4. **Referências externas:** servem como inspiração, nunca como especificação funcional.

**Se houver conflito:** preserve o comportamento atual, registre a divergência e siga a orientação do Plano Diretor vigente. Não faça alterações silenciosas no banco ou nas integrações para adaptar a interface a uma referência visual.

### Resultado que queremos

O operador deve conseguir, no mesmo sistema:

**Consultar / higienizar → localizar ou identificar cliente → consultar histórico → acompanhar oportunidade → executar próxima atividade → analisar resultados.**

Essa jornada deve ser visualmente consistente, mesmo quando partes dela ainda estiverem em desenvolvimento.

---

## 1. Referências de interface — o que copiar como padrão, não como identidade

| Produto | Usar como referência para | Não copiar |
|---|---|---|
| [Attio](https://attio.com) | acabamento visual, lista de clientes, ficha de registro, painéis laterais, Kanban | estrutura de dados ou funcionalidades que nosso sistema não possui |
| [Linear](https://linear.app) | sidebar enxuta, densidade de informação, busca, filtros, atalhos e hierarquia visual | fluxo de gestão de tarefas sem relação com o CRM |
| [Clay](https://www.clay.com) | tabelas de bases, operações por linha, filtros, lotes, enriquecimento e progresso | automações e integrações que não estejam disponíveis |
| [Twenty CRM](https://twenty.com) | organização modular, formulários, tabelas e dashboards | personalizações que dependam de backend inexistente |
| [Close CRM](https://www.close.com) | contexto da negociação, histórico do contato e ações comerciais | telefonia e comunicação que não tenham sido implantadas |

**Decisão visual:** aparência geral baseada no **Attio**, navegação baseada no **Linear**, tabelas operacionais baseadas no **Clay**, ficha comercial inspirada no **Close**.

---

## 2. Regras inegociáveis antes de mexer no código

1. **Leia o Plano Diretor e os arquivos Markdown técnicos do projeto.** Se algum documento não estiver disponível, registre essa ausência; não presuma seu conteúdo.
2. **Audite o front-end real:** rotas, páginas, componentes, bibliotecas, estados, permissões e interfaces existentes.
3. **Identifique as integrações de cada tela:** Supabase, APIs bancárias, serviços de consulta, robôs, n8n e demais serviços efetivamente conectados.
4. **Não substitua o framework nem reescreva o sistema apenas para alterar a aparência.** Reutilize a stack e a biblioteca de componentes já instaladas sempre que possível.
5. **Não altere payloads, endpoints, cálculos, nomes de campos e status do backend** sem requisito explícito do Plano Diretor e testes de compatibilidade.
6. **Não interrompa uma consulta ou campanha** quando o operador navegar para outra página ou fechar um painel. O processamento real deve continuar segundo a arquitetura existente.
7. **Não trate timeout como “Não é cliente”.** Resultado de negócio e falha técnica são situações diferentes.
8. **Não inclua dados fictícios nas telas operacionais.** Se não houver dados, use um estado vazio ou mensagem de indisponibilidade.
9. **Não exponha tokens, senhas, credenciais, logs sensíveis ou CPFs de forma incompatível com as permissões.**
10. **Não declare uma fase concluída sem testar seus principais fluxos.** Entregas parciais devem ser identificadas como parciais.

**Importante:** o redesenho visual não autoriza mudanças silenciosas no esquema do banco, políticas de acesso, mecanismos de autenticação ou automações.

---

## 3. Aparência final — decisões de design

### 3.1 Princípios

- Visual **SaaS B2B moderno, limpo e compacto**.
- Prioridade para informações relevantes e ações operacionais.
- Menos cartões grandes; mais tabelas e painéis bem organizados.
- Hierarquia consistente: título → resumo/ações → filtros → dados.
- Evitar gradientes decorativos, animações excessivas, sombras fortes e excesso de cores.
- **Tema claro como padrão**; tema escuro recomendado após estabilizar o claro.

### 3.2 Tokens de cor iniciais

| Token | Valor inicial | Uso obrigatório |
|---|---|---|
| `--brand-primary` | `#122942` | identidade e elementos institucionais |
| `--action-primary` | `#2C8B68` | ação principal |
| `--app-bg` | `#F7F9FC` | fundo do sistema |
| `--surface` | `#FFFFFF` | tabelas e painéis |
| `--border` | `#E5EAF0` | divisórias e contornos |
| `--text-primary` | `#1C2938` | conteúdo principal |
| `--text-secondary` | `#657387` | informações complementares |
| `--info` | `#647FC3` | informação / em andamento |
| `--warning` | `#C58A2A` | atenção / revisão |
| `--error` | `#C54848` | falha técnica / erro |
| `--success` | `#279C72` | conclusão / sucesso |

Esses são valores **iniciais**, sujeitos à validação de contraste **WCAG AA**. Criar tokens semânticos; não repetir códigos hexadecimais em dezenas de componentes.

### 3.3 Dimensões recomendadas para desktop

| Elemento | Padrão recomendado |
|---|---|
| Sidebar expandida | `240–256px` |
| Sidebar recolhida | `64–72px` |
| Barra superior | `56–64px` de altura |
| Espaçamento entre seções | `24px` |
| Espaçamento interno de painéis | `16–24px` |
| Altura de linhas de tabelas | `44–52px`, ajustável por densidade |
| Botões e inputs | `36–40px` de altura |
| Borda de painéis | `1px`, discreta |
| Raio de controles | `8px` |
| Raio de cartões/painéis | `10–12px` |

Essas medidas são uma **referência de layout**, não uma exigência de reestruturação da biblioteca atual.

### 3.4 Tipografia e ícones

- Fonte preferencial: **Inter**; alternativa: **Manrope**.
- Texto normal: `14px`; textos secundários e tabelas densas: `13–14px`.
- Título de página: `22–24px`; títulos menores: `16–18px`.
- Use pesos `400`, `500` e `600`; reserve negrito forte para conteúdo-chave.
- Ícones de uma única família (preferencialmente **Lucide**), com tamanho comum de `16–20px`.
- Valores financeiros e indicadores: alinhamento à direita e números tabulares quando apropriado.

### 3.5 Formatação brasileira — obrigatório

- CPF exibido: `000.000.000-00`.
- Datas: `dd/mm/aaaa`; com hora, `dd/mm/aaaa HH:mm`.
- Moeda: `R$ 1.234,56`.
- Decimal exibido: separador `,`.
- Telefones: formato brasileiro quando os dados permitirem.
- Texto da interface: **português do Brasil**.

**Separação fundamental:** formatação visual não é formato de integração. APIs de terceiros que exijam CPF com 11 dígitos devem continuar recebendo 11 dígitos. Se a API do próprio sistema tiver contrato de devolver CPF formatado, mantenha esse contrato. Não modifique indiscriminadamente os identificadores armazenados.

---

## 4. Estrutura global de navegação

### 4.1 Layout obrigatório

Usar uma estrutura consistente em todas as páginas:

```text
┌────────────────────────────────────────────────────────────────────┐
│ Sidebar      │ Barra superior: busca, contexto, notificações/perfil│
│              ├─────────────────────────────────────────────────────┤
│ Visão geral  │ Título da página                  [Ação principal] │
│ Clientes     │ Descrição curta / resumo                            │
│ Consultas    │ [Filtros] [Busca] [Ordenação]                        │
│ Campanhas    │                                                     │
│ Oportunidades│              Conteúdo da tela                      │
│ Relatórios   │        tabela, cards, Kanban ou formulário          │
│ Configurações│                                                     │
└──────────────┴─────────────────────────────────────────────────────┘
```

**Importante:** mostrar no menu apenas módulos que já funcionem ou estejam autorizados no Plano Diretor. Não criar botão ou página que simule uma função inexistente.

### 4.2 Sidebar

**Obrigatório:**

- Menu fixo à esquerda no desktop; recolhível.
- Ícone e texto quando expandido; ícone com tooltip quando recolhido.
- Página atual claramente destacada.
- Submenus apenas onde necessários.
- Exibir configurações e módulos restritos conforme permissões.

**Estrutura sugerida:** Visão Geral, Clientes, Consultas, Campanhas, Oportunidades, Relatórios e Configurações.

### 4.3 Barra superior e conteúdo

- Barra superior discreta, sem ocupar espaço excessivo.
- A busca global **só deve aparecer como global se realmente pesquisar os módulos prometidos**. Caso contrário, usar busca contextual dentro de cada página.
- A ação principal fica no canto superior direito do cabeçalho da página (ex.: **Nova campanha**).
- Filtros imediatamente acima da tabela/listagem.
- Detalhes rápidos podem abrir em **painel lateral direito** sem perder a lista atual.
- Ao retornar de um detalhe, manter os filtros e a página atual quando a arquitetura permitir.

### 4.4 Responsividade

- **Desktop primeiro**, pois o foco é operação com base e múltiplas colunas.
- Em tablet, recolher a sidebar e reorganizar filtros.
- Em celular, manter ações principais disponíveis; usar cartões ou rolagem horizontal controlada para tabelas.
- Nenhuma ação crítica pode depender exclusivamente do hover.

---

## 5. Tela por tela — o que fazer e como validar

### 5.1 Visão Geral

**Objetivo:** dar uma leitura rápida da operação.

**Organização visual recomendada:**

1. Cabeçalho `Visão Geral` + período selecionado.
2. Primeira faixa com **4 indicadores principais**, quando disponíveis.
3. Lista de campanhas em andamento com progresso.
4. Pendências que exijam ação do operador.
5. Atividade ou resultados recentes, caso haja histórico confiável.

**Indicadores possíveis, desde que existam dados reais:** consultas processadas; consultas em andamento; erros/revisões; oportunidades abertas.

**Obrigatório:**

- Indicar período e unidade de cada métrica.
- Não inventar comparativo com o mês anterior.
- Não misturar totais de diferentes períodos.
- Se houver atualização por polling ou eventos, exibir estado de atualização sem fingir tempo real.
- Cada card clicável deve abrir uma lista realmente filtrada; caso contrário, não deve aparentar ser clicável.

**Pronto quando:** os totais conferem com a origem de dados, as campanhas exibem progresso correto e nenhum indicador depende de dados fictícios.

### 5.2 Consultas individuais

**Objetivo:** consultar um CPF e entender o resultado imediatamente.

**Fluxo obrigatório (preservando regras existentes):**

1. Selecionar **Estado**.
2. Selecionar **Convênio** disponível no estado.
3. Selecionar o(s) **Serviço(s)** compatível(is) com o convênio.
4. Informar o **CPF**.
5. Clicar em **Consultar**.
6. Exibir o estado `Consultando…` e acompanhar a execução real.
7. Exibir **resultado, status, serviço, data/hora e origem** conforme dados disponíveis.

**Layout:** formulário compacto no topo/esquerda; resultado em painel bem delimitado abaixo ou à direita, dependendo da largura.

**Mensagens de situação:**

| Situação real | Mensagem na interface | Conduta |
|---|---|---|
| Processando | `Consultando…` | impedir clique duplicado |
| Sucesso | `Consulta finalizada` | mostrar retorno válido |
| Não é cliente | `Não é cliente` | não confundir com falha técnica |
| Tempo excedido | `Tempo de consulta excedido` | oferecer nova tentativa quando permitido |
| Falha externa | `Não foi possível concluir a consulta` | preservar tentativa e exibir orientação |
| Precisa análise | `Solicitar revisão` | destacar pendência, se este estado existir |

**Preservar:** fluxos dos convênios atuais, regras de seleção, parâmetros, chamadas de API, status e localização dos logs técnicos.

**Pronto quando:** todas as combinações válidas de estado/convênio/serviço funcionam e os estados de resultado não são confundidos.

### 5.3 Campanhas — listagem

**Objetivo:** acompanhar todas as higienizações sem abrir cada campanha.

**Colunas recomendadas, conforme dados disponíveis:**

| Campanha | Convênio | Serviço | Total | Processados | Erros | Progresso | Situação | Criada em | Ações |
|---|---|---|---:|---:|---:|---|---|---|---|

**Comportamento:**

- Botão **Nova campanha** sempre no topo da página.
- Busca pelo nome da campanha.
- Filtros por convênio, situação e período quando suportados.
- Ordenação por data, preferencialmente mais recente primeiro.
- Barra de progresso com contagem `X / Y`, não só cor.
- Clique na linha abre a tela de detalhes.
- Menu de ações contextuais para opções secundárias (evitar dezenas de botões por linha).

**Regra:** o percentual de progresso deve refletir os status verdadeiros do backend. Definir/documentar previamente quais status contam como processados; não calcular com uma fórmula arbitrária que distorça o total.

### 5.4 Campanhas — criação

**Objetivo:** tornar o fluxo de criação explícito e à prova de combinações inválidas.

**Etapas em ordem obrigatória:**

1. Informar nome da campanha.
2. Selecionar **Estado → Convênio → Serviço(s) compatível(is)**.
3. Enviar a base em um dos formatos já aceitos pelo sistema.
4. Validar a estrutura do arquivo e os campos obrigatórios.
5. Mostrar prévia: colunas identificadas, quantidade de linhas válidas e erros de validação.
6. Confirmar e criar/iniciar a campanha conforme o fluxo já implementado.

**Regras:**

- Não permitir selecionar um serviço incompatível com o convênio.
- Não iniciar com arquivo inválido sem indicar a causa.
- Não afirmar `Campanha criada` antes da confirmação real do servidor.
- Não alterar formatos suportados apenas por preferência de UI.
- Manter o arquivo-modelo para download, se disponível no sistema.

**Pronto quando:** é possível criar uma campanha válida, barrar uma inválida com mensagem específica e verificar a campanha na listagem.

### 5.5 Campanhas — detalhes e resultados

**Organização da página:**

1. Nome, convênio, serviços e situação.
2. Resumo: total, processados, pendentes e falhas.
3. Progresso geral visível.
4. Filtros por status e busca por CPF/nome quando a pesquisa for suportada.
5. Tabela de registros.
6. Ações válidas: visualizar resultado, exportar, **Nova tentativa**, excluir mediante permissão.

**A tabela precisa mostrar**, conforme retorno real: CPF, nome, serviço, resultado resumido, status, data/hora e ação para detalhe.

**Nova tentativa:**

- Habilitar apenas para estados elegíveis definidos na regra existente.
- Não reprocessar silenciosamente registros válidos.
- Mostrar os registros selecionados e pedir confirmação quando for operação em lote.
- Manter histórico e evitar duplicação indevida.

**Excluir:**

- Exigir confirmação para ação destrutiva.
- Respeitar permissões do perfil.
- Explicar consequência quando houver remoção de registros ou histórico.

**Pronto quando:** o operador acompanha cada CPF, identifica falhas, repete somente os elegíveis e exporta os dados corretamente.

### 5.6 Clientes — listagem

**Objetivo:** localizar rapidamente o cliente sem repetir consultas desnecessárias.

**Layout:** tabela compacta estilo Attio, com busca e filtros no topo.

**Colunas recomendadas, quando existirem:** nome, CPF, telefone, convênio, situação, última consulta, responsável e próxima atividade.

**Comportamento:**

- Clique na linha abre a ficha ou um painel lateral.
- Busca por nome e CPF, respeitando as permissões.
- Preservar filtros ao voltar da ficha.
- Não criar um novo cliente a cada consulta; respeitar a chave de identificação e a modelagem do banco.
- Quando o módulo ainda não estiver implementado, tratá-lo como etapa futura, não criar registros fictícios.

### 5.7 Clientes — ficha 360°

**Objetivo:** reunir histórico e contexto do relacionamento em uma única tela.

**Estrutura recomendada:**

```text
┌───────────────────────────────────────────────────────────────────┐
│ NOME DO CLIENTE                   CPF formatado   [Ação permitida] │
├──────────────────────┬────────────────────────────┬───────────────┤
│ Dados cadastrais     │ Aba ativa: Histórico       │ Próxima ação  │
│ Telefones e vínculos │ Consultas por data         │ Responsável   │
│ Status / convênio    │ Oportunidades vinculadas   │ Observações   │
│ Origem e atualização │ Documentos autorizados     │ Pendências    │
└──────────────────────┴────────────────────────────┴───────────────┘
```

**Abas recomendadas:** Visão geral, Consultas, Oportunidades, Atividades e Documentos **apenas quando os dados e permissões existirem**.

**Obrigatório:**

- Mostrar de onde veio a informação e quando ela foi atualizada.
- Histórico em ordem cronológica, com serviço, data/hora, resultado e status.
- Não misturar dados de consultas diferentes como se fossem um resultado atual.
- Não mostrar documentos ou informações pessoais sem autorização.
- Evitar duplicações visuais e duplicação de clientes no banco.

**Pronto quando:** a ficha mostra dados reais, permite consultar o histórico e vincula corretamente os registros já existentes.

### 5.8 Oportunidades e Kanban

**Objetivo:** acompanhar a evolução comercial após a consulta.

**Duas visões recomendadas:** `Kanban` e `Lista`, usando o mesmo conjunto de dados.

**Cartão Kanban compacto:** nome, convênio/produto, valor relevante quando existente, etapa, responsável e próxima ação.

**Obrigatório:**

- Usar **etapas comerciais do Plano Diretor**, não inventar etapas inspiradas em outro CRM.
- Mover cartão somente se houver persistência real e autorização.
- Confirmar visualmente uma mudança de etapa **após** sucesso da operação no servidor; reverter em erro.
- Rastrear alteração quando o sistema já oferecer histórico/auditoria.
- Valores de dívida, limite, troco e simulação devem vir da regra de cálculo existente, não de um cálculo improvisado no navegador.

**Pronto quando:** Kanban e Lista exibem os mesmos registros, mudanças são persistidas e reabrir a tela mantém a etapa correta.

### 5.9 Relatórios

**Objetivo:** permitir acompanhamento e auditoria sem poluição visual.

- Filtros por período, convênio, campanha, serviço e responsável, **onde disponíveis**.
- Indicadores devem coincidir com os registros e a definição de cada métrica.
- Exportações devem preservar as colunas e regras existentes.
- Mostrar estado vazio quando não houver dados.
- Priorizar informação operacional antes de gráficos sofisticados.

### 5.10 Configurações e monitoramento

**Agrupamentos recomendados:** credenciais e APIs, parâmetros por serviço, usuários/permissões, simulação/comissionamento quando implantados, e monitoramento.

- Segredos e senhas sempre ocultos.
- CPU/RAM, filas e status de robôs **somente se houver telemetria real**.
- Indicar se uma mudança foi salva, falhou ou precisa de validação.
- Logs técnicos devem ficar em área apropriada e acessível só para perfis autorizados.
- Não modificar permissões de backend para simplificar a interface.

---

## 6. Componentes reutilizáveis — padrão único para o front-end

Criar/adaptar componentes compartilhados **sem duplicar** os que já existirem:

| Componente | Obrigação objetiva |
|---|---|
| `AppShell` | sidebar, header e área principal consistentes |
| `PageHeader` | título, contexto e uma ação principal clara |
| `DataTable` | tabela com padrão de cabeçalho, estados e paginação/filtro quando suportados |
| `FilterBar` | filtros aplicados e ação de limpar filtros |
| `StatusBadge` | mesma cor e texto para cada status real em todo o sistema |
| `ProgressIndicator` | progresso baseado no processamento real e contagem textual |
| `DetailDrawer` | detalhe rápido, com fechar e retorno ao contexto |
| `ConfirmDialog` | confirmação antes de exclusão ou ação destrutiva |
| `LoadingState` | carregamento reconhecível |
| `EmptyState` | explicar ausência de dados e próxima ação disponível |
| `ErrorState` | explicar falha e oferecer recuperação válida |
| `Timeline` | histórico com data/hora, tipo, origem e resultado |

**Padronização obrigatória:** botões, bordas, espaçamento, ícones, rótulos, filtros e mensagens devem ter o mesmo comportamento em todas as páginas.

**Não recomendado:** adicionar nova biblioteca visual apenas porque uma tela usa um componente diferente.

---

## 7. Estados da interface — tratar explicitamente

Toda tela com dados assíncronos deve definir o que aparece em cada estado:

| Estado | O que o usuário deve ver |
|---|---|
| Carregando | indicador de progresso ou skeleton, sem sugerir conclusão |
| Concluído | resultado real e confirmação apropriada |
| Vazio | explicação curta; ação válida quando existir |
| Parcial | o que concluiu, o que falhou e o que está pendente |
| Erro externo | mensagem compreensível, sem dados técnicos sensíveis |
| Sem permissão | aviso claro, sem revelar conteúdo protegido |
| Tempo excedido | falha de comunicação explicitamente diferente de `Não é cliente` |
| Desatualizado | origem e data/hora da última informação conhecida |

**Regra de sucesso:** não exibir toast de sucesso antes de receber confirmação do servidor, exceto nos fluxos de processamento assíncrono em que `Solicitação recebida` seja o estado efetivamente confirmado.

---

## 8. Acessibilidade, privacidade e desempenho

### Acessibilidade — obrigatório

- Contraste de texto e componentes compatível com WCAG AA.
- Foco visível e navegação por teclado.
- Campos com rótulo; erros de validação associados ao campo.
- Ícones com rótulo ou tooltip quando a função não for óbvia.
- Status não comunicado apenas por cor.

### Privacidade e segurança — obrigatório

- Respeitar sessão, papéis e políticas de acesso atuais.
- Não exibir segredos, tokens ou respostas técnicas completas para usuários sem autorização.
- Evitar mostrar dados sensíveis em notificações, logs visíveis e capturas de erro.
- Não introduzir mudanças em tabelas, RLS, autenticação ou storage sem especificação técnica aprovada.

### Desempenho — obrigatório

- Consultas e campanhas longas não podem travar a interface.
- Estados parciais devem refletir o processamento real.
- Tabelas grandes devem usar paginação/virtualização **quando necessário e compatível com o backend**.
- Não disparar uma chamada de API a cada tecla sem controle; usar debounce e limites apropriados.
- Não recriar consultas ou reprocessar registros ao simples abrir/recarregar a tela.

---

## 9. Ordem exata de execução

> **Não desenvolver tudo simultaneamente.** Encerrar cada fase com teste e relatório antes de iniciar a próxima. Seguir outra ordem somente se o Plano Diretor atual exigir dependências diferentes.

### Fase 0 — Auditoria (antes de qualquer alteração visual)

**Executar:**

1. Localizar e ler Plano Diretor e Markdown de regras de negócio.
2. Listar rotas e telas atuais.
3. Mapear ações e chamadas de API de cada tela.
4. Identificar o que está pronto, parcial ou não implementado.
5. Levantar componentes existentes, biblioteca UI e temas.
6. Registrar comportamentos atuais que não podem regredir.

**Entregável:** tabela `Tela atual | Funcionalidade | Fonte de dados | Alteração proposta | Risco | Teste necessário`.

**Critério para avançar:** saber exatamente o que existe e o que não existe.

### Fase 1 — Design system e navegação

**Executar:**

1. Definir tokens e tipografia.
2. Padronizar botões, inputs, badges, tabelas e modais.
3. Implementar/ajustar sidebar recolhível.
4. Padronizar barra superior e cabeçalho de páginas.
5. Validar rotas, permissões e responsividade.

**Critério para avançar:** toda página existente abre corretamente, com navegação funcional e sem regressão operacional.

### Fase 2 — Consultas e campanhas

**Executar:**

1. Modernizar consulta individual.
2. Modernizar lista de campanhas.
3. Modernizar criação de campanha, preservando o fluxo estado → convênio → serviço → arquivo → confirmação.
4. Modernizar detalhe da campanha, tabela de CPFs, progresso e `Nova tentativa`.
5. Validar importação, processamento, reprocessamento, exportação e erros.

**Critério para avançar:** criar, executar, acompanhar e reprocessar uma campanha continua funcionando; consultas individuais retornam seus status corretos.

### Fase 3 — Clientes e ficha 360°

**Executar:**

1. Definir apresentação de listagem sem duplicação indevida.
2. Implementar ficha de cliente usando o modelo de dados aprovado.
3. Mostrar histórico de consultas e datas de atualização.
4. Adicionar painel lateral contextual quando útil.

**Condição:** se faltar suporte real do backend, registrar dependência. **Não fabricar cadastro ou histórico no front-end.**

**Critério para avançar:** cliente e histórico são recuperados de registros reais, com permissões corretas.

### Fase 4 — Oportunidades e operação comercial

**Executar:**

1. Aplicar padrão visual de funil e lista.
2. Exibir negócio, cliente, etapa, responsável e próxima ação conforme modelo disponível.
3. Validar atualização persistente de etapa e histórico.
4. Integrar visualmente os dados já disponíveis de consulta e simulação, sem modificar cálculos.

**Critério para avançar:** mudança de etapa salva e é recuperada corretamente; todas as visões permanecem sincronizadas.

### Fase 5 — Dashboard, relatórios e acabamento

**Executar:**

1. Montar indicadores com definições e fontes verificadas.
2. Padronizar relatórios, filtros e exportações.
3. Revisar tema escuro, se previsto e viável.
4. Fazer revisão desktop, tablet e mobile.
5. Testar acessibilidade, estados vazios, erros e desempenho.
6. Finalizar documentação, comparativo antes/depois e pendências.

**Critério de conclusão:** todas as funcionalidades abrangidas pelo redesenho foram testadas e nenhuma regressão conhecida permanece sem registro.

---

## 10. Testes mínimos que precisam ser executados

| Teste | Resultado esperado |
|---|---|
| Navegar entre módulos | rota correta, sessão e permissões mantidas |
| Consultar CPF válido | resultado real, com CPF exibido corretamente |
| Consultar CPF que não é cliente | status `Não é cliente`, sem falsa falha técnica |
| Simular timeout/falha externa em consulta | mensagem de erro técnico, nunca `Não é cliente` |
| Criar campanha válida | campanha realmente cadastrada e visível na lista |
| Enviar arquivo inválido | impedir execução e indicar erros específicos |
| Executar campanha com sucessos e falhas | progresso e contagens coerentes |
| Acionar `Nova tentativa` em erros elegíveis | reprocessar somente os selecionados/elegíveis |
| Reabrir campanha após sair da tela | estado recuperado do servidor, sem reiniciar processamento |
| Abrir ficha de cliente | histórico e dados corretos, sem duplicação visual |
| Mover oportunidade no Kanban, se disponível | alteração persistida e refletida na lista |
| Exportar resultados | manter conteúdo, campos e formatação contratada |
| Usar perfil sem permissão | ações e dados protegidos não são acessíveis |
| Testar em tela menor | navegação e ações essenciais continuam acessíveis |

**Observação:** executar os testes aplicáveis ao que realmente foi implementado. Se um módulo ainda não existir, classificá-lo como **não implementado**, e não como teste aprovado.

---

## 11. Modelo obrigatório do relatório de cada fase

Depois de cada fase, entregar um resumo com os seguintes campos:

```markdown
## Relatório — Fase X

**Status:** Concluída / Parcial / Bloqueada

### Arquivos alterados
- caminho/do/arquivo — descrição da alteração

### Funcionalidades preservadas e verificadas
- ...

### Testes executados
| Teste | Resultado | Evidência / observação |
|---|---|---|
| ... | Aprovado / Falhou / Não executado | ... |

### Dependências ou pendências
- ...

### Próximo passo
- ...
```

**Não usar “concluído” como sinônimo de “código escrito”.** Só é concluído quando foi testado e o comportamento esperado foi comprovado.

---

## 12. Critérios finais de aceite

Marcar cada item somente após validação:

- [ ] O Plano Diretor foi lido e as divergências foram tratadas.
- [ ] A sidebar e a navegação ficaram consistentes.
- [ ] O design system é compartilhado, sem estilos duplicados desnecessários.
- [ ] As consultas continuam usando integrações e regras reais.
- [ ] As campanhas preservam importação, processamento, resultado, exportação e novas tentativas.
- [ ] Os status de negócio e erros técnicos são mostrados corretamente.
- [ ] O CPF é formatado adequadamente sem quebrar contratos de API.
- [ ] Clientes e oportunidades mostram apenas dados existentes e autorizados.
- [ ] Indicadores e progresso são calculados a partir de fontes verificadas.
- [ ] A interface funciona em desktop e resoluções menores relevantes.
- [ ] Há tratamento para carregando, vazio, parcial, falha e sem permissão.
- [ ] Não houve alteração silenciosa de APIs, banco, autenticação ou cálculos financeiros.
- [ ] Os principais fluxos foram testados e registrados no relatório final.
- [ ] Funcionalidades futuras estão identificadas como futuras, sem aparência enganosa de prontas.

---

## 13. Prompt direto para o agente de desenvolvimento

Copie o bloco abaixo junto com este Markdown e o Plano Diretor:

> **TAREFA:** realizar o redesenho UX/UI do Sistema de Consultas / CRM ApoiarCred.
>
> **LEITURA OBRIGATÓRIA:** antes de qualquer edição, leia integralmente o Plano Diretor atualizado, os Markdown técnicos e este arquivo. Inspecione o repositório para confirmar rotas, stack, componentes, APIs, banco, permissões e funções realmente existentes.
>
> **ESTILO:** use Attio para acabamento e ficha de cliente; Linear para navegação; Clay para campanhas e tabelas; Close para contexto comercial. Aplique o design system desta especificação. Priorize uma interface moderna, discreta, compacta e em português brasileiro.
>
> **PRESERVAÇÃO:** não remova funções existentes, não altere cálculos, não modifique contratos de API nem reescreva o backend apenas para fins visuais. Não substitua timeout por `Não é cliente`. Não apresente dados falsos ou botões inoperantes como funcionalidades prontas. Mantenha estado/convênio/serviços, consultas, campanhas, importações, resultados, exportações, novas tentativas, autenticação e permissões.
>
> **EXECUÇÃO:** faça primeiro a auditoria (Fase 0), depois a base visual (Fase 1), depois consultas/campanhas (Fase 2), clientes (Fase 3), oportunidades (Fase 4) e dashboard/relatórios (Fase 5), salvo dependências documentadas do Plano Diretor. Em cada fase, altere os componentes necessários, execute testes e entregue o relatório exigido na Seção 11.
>
> **REGRA PARA FUNÇÃO AUSENTE:** não improvisar interface fictícia. Descrever dependência técnica e classificar como pendente.
>
> **DEFINIÇÃO DE PRONTO:** código integrado, fluxo funcional preservado, cenários de erro verificados, responsividade básica validada e evidência de teste registrada.

---

## 14. Definição do resultado esperado

No final, o sistema precisa parecer um **único CRM moderno**, não um conjunto de ferramentas independentes. O operador deve navegar com clareza entre consultas, campanhas, clientes e oportunidades, sem perder contexto ou interromper processamentos. O ganho esperado é de **usabilidade, organização visual e produtividade**, mantendo como fonte de verdade as regras, APIs, permissões e dados efetivamente existentes.

**Esta especificação trata de UX/UI. Novos módulos, novos endpoints, novas regras bancárias e mudanças de banco devem seguir o Plano Diretor e suas especificações técnicas próprias.**
