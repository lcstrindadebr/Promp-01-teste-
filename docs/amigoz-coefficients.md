# Simulação Amigoz por coeficientes observados

O motor utiliza a tabela fornecida em 11/11/2026. Prazo de 96 meses, taxas de 3%, 3,25%, 3,50%, 3,75%, 3,98% e 4,50%. A regra operacional confirmada pelo usuário substitui a interpretação anterior do documento: limite = base × multiplicador; limite restante = máximo(limite − quitação, 0); saque bruto = 70% do limite restante; troco = saque bruto − IOF estimado, desde que o saque bruto atinja R$ 315,00. Não se desconta a quitação novamente do troco. O mínimo é aplicado ao saque bruto, antes do IOF.

A tela permite parcela original, parcela original acrescida de margem elegível selecionada, margem consultada e parcela total manual. A identificação de margem inclui convênio, matrícula, instituição, produto e data. A configuração inicial cobre Governo de São Paulo (`amigoz_23`), produtos benefício e consignado da instituição Amigoz, conforme o catálogo do projeto. Outros convênios, instituições e produtos podem ser habilitados pelo administrador após confirmação de elegibilidade.

Para consultas Digi+ sem vínculo cadastrado, Governo de São Paulo é o convênio padrão configurado, identificado na tela para conferência. Havendo vínculos cadastrados, a escolha deve corresponder a um deles. Vários vínculos exigem seleção explícita. As condições continuam preliminares e dependem de confirmação no banco. Limite abaixo da dívida é insuficiente, com troco zero. Limite que cobre a dívida mas não gera saque bruto mínimo aparece como pré-aprovada sem troco. Sem saldo de quitação, o troco fica pendente, nunca um valor presumido.

## Configuração e histórico

Em Configurações → Comissões, o administrador carrega e edita o JSON técnico da configuração. Salvar cria nova versão imutável em `amigoz_model_versions`. A configuração contém os seis coeficientes, CET de referência, IOF histórico, parcelas de referência e elegibilidade por convênio. Cada simulação guarda a versão, base, parcela original, dívida, margem selecionada, fonte e data dos dados em `amigoz_coefficient_simulations`, com isolamento por usuário.

O IOF estimado usa a proporção histórica própria de cada taxa. O motor aceita opcionalmente `iof_banco`, um objeto com o IOF do saque informado para cada taxa, por exemplo `{"3":139.30}`. O resultado identifica a origem. Essa entrada deve vir de uma informação da instituição sobre a operação. Não existe integração automática de cálculo fiscal neste projeto. Como o saque passa a usar o limite residual, parcela da quitação, parcela do saque e comprometimento total ficam sem estimativa até haver regra validada para essa composição. O IOF da quitação permanece sem valor quando não fornecido. A interface exibe situação, limite, quitação, limite restante e troco estimado, com taxa e prazo.

## Consulta de margem durante a comparação

No simulador, expanda **Consultar ou atualizar margem pela API Amigoz** e clique
em **Consultar margem do cliente**. O CPF e o convênio selecionados são reutilizados;
matrícula e senha do servidor são opcionais. A consulta usa a integração já
configurada, com a mesma autorização, cota e persistência em histórico/CRM.
A senha não fica no formulário após o envio nem entra na simulação salva.

Após retorno salvo, o contexto de margens é recarregado. Selecione a base
**Parcela atual + margem consultada** ou **Margem consultada**, escolha o vínculo
e recalcule. Nenhuma margem de outro produto ou vínculo é agregada automaticamente.
Se o provedor responder sem margem elegível, a tela informa isso. Falha de gravação
orienta conferir o diagnóstico sem repetir a consulta externa.

## Atualizar uma instalação existente

1. Execute `supabase/upgrade_amigoz_debt_cash.sql` no SQL Editor do projeto
   Supabase já utilizado pelo sistema. Requer o motor de coeficientes instalado;
   não reaplique o schema completo. A migração substitui apenas a função de cálculo
   e preserva permissões e dados; pode ser repetida.
2. Atualize o código pelo comando habitual da VPS e recarregue o painel.

Sem essa migração, o painel e as exportações bloqueiam resultados do motor antigo.
As simulações salvas antigas permanecem no histórico; novas simulações e exportações
recalculam usando a regra residual (`limite_residual_v1`).

## Exportações

Consultas individuais, resultados de campanhas, oportunidades do CRM e downloads de clientes em CSV ou XLSX recebem seis colunas de saque líquido estimado, além de base, margem agregada, prazo, situação e versão. Arquivos de histórico já baixados mantêm seu conteúdo original. O relatório agregado de quantidade de consultas continua sendo um resumo de campanha.

A exportação usa uma simulação salva compatível com cliente, convênio e vínculo quando ela continua atual. Mudança da fonte, da margem ou da versão deixa os valores em branco com orientação para recalcular. Sem simulação salva, usa a parcela Digi+ disponível ou a única margem elegível do vínculo da linha. Ambiguidade ou falta de dados gera uma explicação em vez de valor zero. Valores monetários de CSV usam vírgula decimal e XLSX usa células numéricas. Os lotes de cálculo têm até 100 linhas, sem criar históricos durante a exportação.

## RPCs do painel

Estas chamadas usam JWT do usuário autenticado no Supabase, com RLS. Os tokens externos da API V1 não são credenciais desses RPCs.

- `amigoz_simulation_context(p_cpf, p_convenio, p_job_id)` carrega fonte, margens e configuração.
- `amigoz_simular_coeficientes(p_input, p_save)` calcula e opcionalmente registra a simulação. `p_input` contém `cpf`, `convenio`, `job_id` opcional, `mode` (`original`, `aggregate`, `margin`, `manual`), `margin_key` quando pertinente, `manual` para valor total e `prazo:96`.
- `amigoz_exportar_estimativas(p_items)` calcula o lote com reaproveitamento de simulações atuais e sem gravar novos históricos.
- `amigoz_save_model(p_config)` cria uma versão, exclusivamente para administrador ativo.
- `simular_amigoz_price` e `simular_amigoz` encaminham as chamadas legadas ao novo motor.

## Verificação e homologação pendente

O teste SQL `tests/amigoz_coefficients_database.sql` termina com rollback e cobre os seis resultados atualizados, saque bruto de R$ 347,55 com base R$ 350 e dívida R$ 10.000, IOF informado, agregação, parcela manual, margens incompatíveis, prazo, histórico, exportação, desatualização e isolamento entre contas. O teste `tests/test_amigoz_coefficients.cjs` verifica os cartões, bloqueio do cálculo antigo, consulta de margem e montagem das colunas. `tests/amigoz_debt_cash_database.sql` cobre as seis taxas do caso de limite insuficiente, dívida igual ao limite, compra sem troco, mínimo de R$ 315, dívida pendente, dívida zero e precedência do IOF bancário. Esse teste financeiro foi executado em PostgreSQL embarcado (PGlite), incluindo repetição da migração. Os testes com RLS e fonte/CRM exigem um banco completo de teste; não foram executados no projeto de produção.

A homologação oficial deve variar saldo mantendo margem R$ 200, variar margens com dívida constante, testar R$ 100/R$ 250/R$ 500, dívida acima da capacidade, arredondamento, primeiro vencimento e composição do IOF. Essa etapa depende de acesso ao simulador da instituição e não é substituída pelos testes de software.
