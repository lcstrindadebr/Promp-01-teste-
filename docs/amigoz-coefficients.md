# Simulação Amigoz por coeficientes observados

O motor utiliza a tabela fornecida em 11/11/2026. Prazo de 96 meses, taxas de 3%, 3,25%, 3,50%, 3,75%, 3,98% e 4,50%. Os seis cenários de margem R$ 200 e quitação R$ 200 reproduzem os valores do documento. A fórmula de limite é base × multiplicador. O saque bruto usa 70% do limite, e o troco desconta o IOF do saque.

A tela permite parcela original, parcela original acrescida de margem elegível selecionada, margem consultada e parcela total manual. A identificação de margem inclui convênio, matrícula, instituição, produto e data. A configuração inicial cobre Governo de São Paulo (`amigoz_23`), produtos benefício e consignado da instituição Amigoz, conforme o catálogo do projeto. Outros convênios, instituições e produtos podem ser habilitados pelo administrador após confirmação de elegibilidade.

Para consultas Digi+ sem vínculo cadastrado, Governo de São Paulo é o convênio padrão configurado, identificado na tela para conferência. Havendo vínculos cadastrados, a escolha deve corresponder a um deles. Vários vínculos exigem seleção explícita. Extrapolações e o efeito de dívidas diferentes do cenário de referência exigem validação no banco.

## Configuração e histórico

Em Configurações → Comissões, o administrador carrega e edita o JSON técnico da configuração. Salvar cria nova versão imutável em `amigoz_model_versions`. A configuração contém os seis coeficientes, CET de referência, IOF histórico, parcelas de referência e elegibilidade por convênio. Cada simulação guarda a versão, base, parcela original, dívida, margem selecionada, fonte e data dos dados em `amigoz_coefficient_simulations`, com isolamento por usuário.

O IOF estimado usa a proporção histórica própria de cada taxa. O motor aceita opcionalmente `iof_banco`, um objeto com o IOF do saque informado para cada taxa, por exemplo `{"3":139.30}`. O resultado identifica a origem. Essa entrada deve vir de uma informação da instituição sobre a operação. Não existe integração automática de cálculo fiscal neste projeto. Para valores fora da referência, parcela da quitação, parcela do saque e comprometimento total ficam sem estimativa até haver regra validada. O IOF da quitação permanece sem valor quando não fornecido. A interface exibe somente limite, quitação e troco estimado, com taxa e prazo.

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

O teste SQL `tests/amigoz_coefficients_database.sql` termina com rollback e cobre os seis resultados, os componentes da referência, saque bruto de R$ 7.347,55 com base R$ 350, IOF informado, agregação, parcela manual, margens incompatíveis, prazo, histórico, exportação, desatualização e isolamento entre contas. O teste `tests/test_amigoz_coefficients.cjs` verifica o fluxo do painel e a montagem das colunas.

A homologação oficial deve variar saldo mantendo margem R$ 200, variar margens com dívida constante, testar R$ 100/R$ 250/R$ 500, dívida acima da capacidade, arredondamento, primeiro vencimento e composição do IOF. Essa etapa depende de acesso ao simulador da instituição e não é substituída pelos testes de software.
