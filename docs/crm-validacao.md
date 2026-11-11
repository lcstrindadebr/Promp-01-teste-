# Revisão CRM — 10/11/2026

## Escopo desta entrega

| Requisito | Implementação | Verificação |
| --- | --- | --- |
| Consultas unificadas | Item único no menu; Individual e Campanhas dentro da página; restrição de campanhas preservada | Teste de navegação/estrutura e suíte de permissões |
| Clientes: filtros e exportação | Nome/CPF, estado, convênio confirmado e serviço; cursor no servidor; exportação percorre todas as páginas | Teste com 1.201 registros; falha intermediária não baixa arquivo parcial |
| Importar clientes | Cadastro separado em Clientes, com estado, convênio e preferência de Digi+ | Teste de banco comprova ausência de lotes, atualização por CPF e isolamento |
| Zerar conta | Ação exclusiva do administrador ativo, restrita à própria conta | Teste em transação revertida com contas fictícias e verificação de confirmação e tarefas ativas |
| Kanban | Seis etapas existentes; paginação independente por coluna; arrastar ou usar seletor | Persistência no Supabase; tratamento de erro mantém etapa anterior |
| Cartões personalizados | Exibição, espaçamento, título comercial e campos texto/número/data/sim-não | Configuração e valores persistidos; tipos validados no banco |
| Valores financeiros protegidos | Somente leitura da última consulta compatível com produto/convênio; fonte/data visíveis | Grants somente SELECT na visão; campos desconhecidos e nomes reservados rejeitados |
| Isolamento | RLS por proprietário em configurações e oportunidades; consultas invoker | Teste com dois usuários em transação revertida |
| UX | Tokens semânticos, tabelas compactas, menu recolhível, rótulos, foco, dialogs nativos e mensagens de erro/vazio | Inspeção de código e testes de comportamento; validação visual pendente |

As consultas continuam executando nos trabalhadores ao navegar entre páginas. Esta entrega não altera status bancários, quotas, filas ou payloads dos portais.

## Evidências

- `node --test tests/*.cjs`: 15 arquivos de teste aprovados (incluindo CRM).
- Python: 152 testes sem dependência de root aprovados. A suíte completa executou 159; seis falharam nas rotinas de instalador/menu/atualização por exigir root. Esses fluxos não foram alterados nesta entrega.
- `tests/crm_kanban_database.sql`: executado no Supabase conectado com rollback. Verifica gravação/releitura, proteção financeira, filtro por proprietário e bloqueio de leitura/escrita cruzada.
- Migrações aplicadas: `crm_kanban_customization_and_filters`, `crm_card_presentation`, `crm_filter_service_scope`.
- `git diff --check`: sem problemas de whitespace.
- Chromium local não iniciou: o ambiente recusou criação de socket (`Operation not permitted`). Não há validação visual real nem homologação de navegador nesta entrega.
- A atualização na VPS depende de executar o instalador. Não há sessão SSH conectada neste ambiente.

## Contratos e limites explícitos

- Estado e convênio dos filtros vêm de vínculos confirmados. Clientes antigos sem classificação continuam em Todos; não são classificados por inferência.
- Digi+ não informa convênio no retorno legado. O filtro pode selecionar clientes com um vínculo confirmado e uma consulta Digi+, sem afirmar que aquela dívida pertence ao vínculo.
- A visão financeira usa um resultado por oportunidade, sem somar margens ou saldos. Saque Amigoz sem resultado persistido aparece como indisponível, nunca como zero ou valor estimado inventado.
- Os dados financeiros continuam dependendo dos resultados de consulta de origem. Exclusão do resultado remove sua disponibilidade no cartão.
- Exportação completa não é snapshot: dados atualizados durante a exportação podem refletir momentos diferentes. A ordenação por CPF evita repetir páginas por mudança da data de atividade.
- O tamanho de cada página protege a interface; não limita o total exportável.
- Personalizações pertencem à conta autenticada. Ocultar um campo não apaga os valores; trocar o tipo ou remover a definição de campo existente é rejeitado para preservar dados.

## Cobertura do plano diretor

Esta entrega implementa os ajustes solicitados de navegação, filtros/exportação e Kanban. **Não comprova conclusão integral do plano diretor.** Permanecem pontos maiores identificados anteriormente: catálogo único UF → convênio → serviços para todos os fluxos, importação com múltiplos serviços na mesma campanha, persistência de resultados Amigoz na ficha, listas dinâmicas salvas, responsáveis/atividades e simulações versionadas. Também falta substituir o carregamento global legado de resultados da conta por consultas paginadas no servidor nas telas antigas.

As referências estão em `docs/plano-diretor.md` e `docs/diretrizes/`. As instruções mais recentes do usuário prevalecem: Campanhas fica dentro de Consultas, embora o exemplo de menu da diretriz V2 mostre os dois itens.

## Avisos preexistentes do projeto

O advisor não apontou vulnerabilidades nas novas tabelas/visões. Apontou tabelas do esquema privado com RLS sem políticas (sem acesso público concedido) e proteção de senhas vazadas desabilitada no Auth. Referência: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . Não foram alteradas configurações globais de autenticação nesta entrega.
