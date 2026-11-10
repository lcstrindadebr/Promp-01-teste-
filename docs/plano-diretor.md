# ApoiarCred — Plano diretor de evolução para CRM

**Versão:** 1.0 — 09/11/2026  
**Status:** planejamento para revisão e aprovação; não constitui implementação.  
**Objetivo:** transformar a central de consultas em uma base comercial viva, preservando campanhas, consultas individuais, integrações, permissões e operação na VPS.

## 1. Como interpretar este documento

Este plano consolida as decisões desde o início da discussão sobre evolução para CRM e os requisitos anteriores que precisam continuar funcionando. Não atesta que todos estejam implementados no código atual. Antes de desenvolver, será feita uma auditoria do repositório, banco e instalador para distinguir o existente, o incompleto e o novo.

- **Definido:** requisito solicitado pelo usuário e que deve ser preservado.
- **Proposto:** recomendação incluída para aprovação neste plano.
- **Pendente:** decisão que precisa ser resolvida antes da parte dependente da implementação.

Exemplos de disponibilidade de serviços não são prova de homologação. O catálogo deve refletir contratos, IDs e respostas reais das integrações. Não são incluídos senhas, tokens ou dados reais de clientes neste documento.

## 2. Visão do produto

O sistema deve permitir importar uma base de um único convênio, executar automaticamente as consultas escolhidas, complementar os cadastros com as respostas e transformar os resultados em oportunidades comerciais.

O ciclo será: **importar → consultar → enriquecer cadastro → filtrar oportunidades → atender → registrar negociação → acompanhar resultado**.

A pessoa será o centro do CRM. Campanhas organizam o processamento; consultas produzem evidências datadas; oportunidades organizam o trabalho comercial. Esses registros devem permanecer relacionados, mas não se confundir.

### 2.1 Princípios definidos

1. Uma importação corresponde a um único estado e convênio. Importações mistas não serão oferecidas.
2. Escolher estado, depois convênio, depois as possibilidades de consulta.
3. Importar a base cadastral sem iniciar consultas. Confirmar uma campanha separadamente para iniciar o processamento autorizado.
4. Manter consulta individual e criação de campanhas específicas.
5. Atualizar o cadastro com informações obtidas nas consultas, incluindo matrícula.
6. Preservar histórico, resultados parciais e campanhas existentes.
7. Permitir filtros comerciais e movimentação de oportunidades entre etapas.
8. Respeitar permissões, cotas, trial e isolamento dos parceiros em todas as interfaces.
9. Manter instalação e atualização pela VPS, via instalador, sem Docker.
10. Evitar complexidade visual e operações manuais repetitivas.

## 3. Jornadas que o sistema deve atender

### 3.1 Importar uma base cadastral

Em Clientes, informar estado e convênio nessa ordem, selecionar as consultas previstas para o convênio, com Digi+ como opção adicional e importar a planilha. A importação registra clientes e classificações informadas, sem criar tarefas. Uma campanha é criada separadamente em Consultas, com os participantes e o serviço selecionados.

### 3.2 Consultar uma pessoa

Escolher estado, convênio e serviço; informar CPF e demais campos exigidos. Reutilizar os dados já cadastrados quando autorizado. Mostrar “Consultando…” e apresentar o resultado. A consulta também integra a ficha do cliente e consome a mesma cota aplicável às campanhas.

### 3.3 Encontrar oportunidades

Filtrar, por exemplo, São Paulo → Polícia Militar → saque complementar Amigoz disponível → sem oportunidade equivalente aberta. Selecionar clientes, atribuir responsáveis e criar oportunidades, sem copiar dados para outra base.

### 3.4 Complementar cadastro incompleto

Importar cliente sem matrícula. Ao retornar uma matrícula na consulta, associá-la ao vínculo correto, registrar fonte e data e disponibilizá-la na ficha, exportação e API autorizada. Se houver várias matrículas, não escolher ou sobrescrever uma arbitrariamente.

### 3.5 Retomar uma campanha

Pausar, atualizar o sistema ou reiniciar um trabalhador sem perder resultados. Retomar somente tarefas pendentes ou recuperáveis, sem repetir indiscriminadamente toda a campanha.

## 4. Arquitetura de navegação e proposta visual

**Proposta:** cinco áreas principais, reduzindo a fragmentação atual.

| Área | Conteúdo e ação principal |
| --- | --- |
| Visão geral | Campanhas ativas, pendências e oportunidades com próxima ação. |
| Clientes | Base central, filtros, listas salvas, importação e ficha. |
| Consultas | Abas Individual e Campanhas; acesso ao processamento. |
| Oportunidades | Funil comercial e visualização em tabela. |
| Configurações | Operação, acessos, robôs, comissões, integrações e usuários conforme permissão. |

**Importar base**, em Clientes, cadastra pessoas e registra o contexto da base. **Nova campanha**, em Consultas, configura a execução em lote. São ações independentes.

### 4.1 Diretrizes visuais

- Preservar logo e identidade ApoiarCred; extrair valores reais do código antes de definir tokens.
- Usar tabelas compactas para grandes volumes; cartões apenas para resumos úteis.
- Definir uma ação principal por tela e hierarquia clara entre ações secundárias.
- Mostrar os filtros mais utilizados e recolher opções avançadas.
- Adotar componentes únicos para campos, botões, tabelas, estados, abas e mensagens.
- Manter paginação no servidor, filtros persistentes na navegação e atualizações sem saltos de página.
- Diferenciar seleção da página atual de seleção de todos os resultados filtrados.
- Exibir estados vazios, carregando, erro, sem permissão e indisponibilidade com orientação concreta.
- Oferecer foco visível, teclado, rótulos associados aos campos e mensagens que não dependam apenas de cor.
- Evitar decoração sem função, excesso de cartões e grandes espaços vazios sem propósito.
- Adaptar ações e tabelas para telas menores sem esconder controles essenciais.

### 4.2 Campanhas

Lista única paginada, com abas **Em andamento, Pausadas e Concluídas**, busca e filtros por tipo de consulta, estado e convênio. Campanhas com vários serviços devem aparecer uma vez, com seus serviços identificados.

Colunas sugeridas: nome, convênio, serviços, situação, clientes processados/total, progresso, previsão e ações. As ações principais serão abrir, pausar/retomar e consultar pendências. Exclusão ficará em menu secundário com confirmação.

Dentro da campanha: resumo no topo, resultados por serviço, tabela paginada de clientes e ações de nova tentativa, exportação e webhook. Previsão sem amostra suficiente deve aparecer como “Calculando previsão”, sem inventar prazo.

### 4.3 Ficha do cliente

Painel lateral para inspeção rápida e página completa para atendimento. Abas propostas: **Resumo, Consultas, Negociações e Histórico**. O resumo deve responder quem é o cliente, seus vínculos, resultado mais recente, responsável e próxima ação.

### 4.4 Funil

Quadro por etapa comercial e alternativa em tabela. Cartões com cliente, produto, responsável, valor estimado e próxima ação. Não usar o funil comercial para representar falhas dos robôs.

## 5. Importação cadastral e criação de campanha

Em **Clientes**, selecione estado, escolha um convênio cadastrado e depois marque as consultas previstas. Envie a planilha e confirme **Importar clientes**. O cadastro não consome cota nem enfileira tarefas.

As etapas abaixo descrevem a criação de campanha em **Consultas**.

### Etapa 1 — Estado e convênio

- Primeiro selecionar estado; depois somente convênios associados a ele.
- Aplicar essa classificação à importação inteira.
- Todos os convênios ConsigX atualmente informados pertencem à Bahia: TJBA, DPEBA, EMBASA, SAEB e SUPREV.
- Não supor que todos os serviços de todos esses convênios estejam homologados.
- Se a planilha trouxer estado/convênio conflitante, bloquear a confirmação e apontar as linhas. Não importar parcialmente como se fosse uma base homogênea.
- A classificação escolhida pelo usuário não comprova, por si só, que cada CPF possui aquele vínculo. A consulta pode confirmar ausência ou divergência.

### Etapa 2 — Consultas disponíveis

Exibir somente combinações cadastradas, habilitadas e autorizadas. Nome comercial em destaque: Margem disponível, Saque complementar, Saldo devedor e parcela. Mostrar fornecedor como informação secundária quando necessário.

Permitir margem, saque complementar ou ambos no Amigoz, conforme operação disponível. Uma seleção combinada não deve provocar chamadas redundantes se a API já devolver os dois resultados em uma operação compatível.

### Etapa 3 — Modelo e arquivo

| Seleção | Modelo |
| --- | --- |
| ConsigX | CPF obrigatório; nome e telefone opcionais. |
| Digi+ | Preservar campos do modelo anterior necessários ao fluxo, incluindo nome e telefone. |
| Amigoz | Campos efetivamente exigidos pela documentação e operação selecionada. |
| Múltiplos serviços | União dos campos necessários, explicando quais são obrigatórios. |

Preservar CSV e outros formatos já suportados; inventariá-los no código e informar extensões reais na interface. Proposta de padrão: CSV e XLSX. Suporte a XLS legado depende da biblioteca e validação, sem anunciar suporte inexistente.

Validar cabeçalhos, CPF, zeros à esquerda, campos exigidos, linhas vazias, duplicidades e conflitos. Não corrigir CPF inválido inventando dígitos. Normalizar CPF internamente para comparação e apresentar no padrão brasileiro.

### Etapa 4 — Prévia e confirmação

Mostrar nome da campanha, estado/convênio, serviços, clientes novos/existentes, duplicidades, linhas inválidas, atualizações previstas e impacto na cota. Oferecer relatório das linhas a corrigir.

Botão: **Importar e iniciar consultas**. Evitar duplicação por duplo clique ou repetição da requisição. Importações grandes terão progresso de preparação antes de entrar na fila.

Usuários com limite visualizam o saldo e o comportamento aplicável ao excedente. Usuários ilimitados não recebem um teto comercial artificial de 10 mil. Limites técnicos de tamanho de arquivo devem ser diferenciados de cota e tratados por processamento em blocos.

## 6. Clientes, vínculos e enriquecimento

### 6.1 Separação dos dados

| Entidade | Conteúdo |
| --- | --- |
| Pessoa/cliente | CPF, nome, data de nascimento, contatos e observações. |
| Vínculo | Estado, convênio, órgão, matrícula, situação funcional e tipo de servidor. |
| Resultado | Serviço, fonte, valores, vínculo, data e conclusão. |
| Campanha | Lista importada, escolhas, participantes e processamento. |
| Oportunidade | Produto, etapa, responsável, simulações e atividades comerciais. |

CPF único por conta/operação autorizada, não uma base global compartilhada entre parceiros. Uma pessoa pode ter vários vínculos e um vínculo pode demandar múltiplas matrículas. O desenho final depende dos identificadores fornecidos pelos portais.

### 6.2 Regras de atualização

| Ocorrência | Regra |
| --- | --- |
| Campo vazio e resposta válida | Preencher automaticamente. |
| Mesmo valor | Registrar nova confirmação e origem. |
| Valor diferente | Aplicar prioridade por campo/fonte e guardar histórico. |
| Dado protegido manualmente | Preservar; apresentar divergência para conferência. |
| Resposta vazia ou falha | Não apagar informação válida. |
| Zero explícito | Registrar zero, distinguindo de dado ausente. |
| Várias matrículas | Registrar separadamente; não sobrescrever vínculo arbitrariamente. |
| Respostas concorrentes | Comparar data da coleta e versão para impedir sobrescrita por resposta antiga. |

**Proposta:** matriz de prioridade por campo. Portal pode ser referência para matrícula e situação; contato confirmado pelo vendedor pode prevalecer sobre telefone de planilha. Não haverá uma regra genérica “a última resposta sempre vence”.

Cada mudança registra campo, valor anterior/novo, fonte, consulta/campanha, responsável quando manual e data. Resultados financeiros são históricos datados; o resumo aponta o mais recente válido e sinaliza tentativa posterior com falha.

### 6.3 Reimportação e exclusão

Associar clientes existentes à nova campanha sem duplicar cadastro ou apagar histórico. Não substituir campos preenchidos por células vazias. Novos vínculos precisam ser mantidos separadamente.

**Proposta:** excluir campanha remove sua organização e participação conforme política, mas não apaga automaticamente cliente ou oportunidade. Excluir uma consulta exige definir o efeito sobre o resultado atual e a auditoria. Exclusão de cliente será ação própria, com confirmação e tratamento de dependências. Política final de exclusão/retenção é pendente.

## 7. Catálogo de serviços e integrações

Cadastro central: estado → convênio → serviço → integração → IDs externos → campos exigidos → permissão → habilitação/homologação.

Registrar separadamente IDs de convênio e de tipo de margem da API Amigoz. Não inferir IDs a partir do nome. Validar lista original, documentação e exemplos reais antes de ativar combinações.

### 7.1 Digi+

- Consultar saldo devedor e parcela e manter respostas vinculadas ao mesmo cliente e execução.
- Priorizar Central de cobrança, por ser a rota mais curta observada.
- Quando uma rota falhar, tentar Empréstimo consignado, com tentativas limitadas e registro da rota.
- Se a primeira resposta confirmar que não é cliente, não executar a segunda de parcela.
- Se houver saldo válido antes de interrupção, preservá-lo e marcar a pendência da parcela.
- Não transformar encerramento sem resposta em “Não é cliente”.

### 7.2 ConsigX

- Seleção de estado e convênio, com o catálogo atual na Bahia.
- Fluxo homologado deve preencher CPF sem exigir alteração desnecessária do tipo de cartão e reutilizar “Voltar” quando a sessão permitir.
- Manter todo o contexto de navegação usando o proxy configurado, sem trocar saída no meio do login.
- Tratar a confirmação “Usuário já logado, deseja desconectar seu usuário dos outros terminais?” de forma específica.
- Detectar somente mensagens e formulários relevantes/visíveis, evitando falsos erros por elementos ocultos.
- Tentativas de login limitadas; não repetir indiscriminadamente bloqueios, CAPTCHA ou mensagens desconhecidas.
- Credenciais distintas por robô; nenhum fallback silencioso para acesso principal compartilhado.
- Sem credencial, o robô fica inelegível para ConsigX e continua elegível para Digi+.

### 7.3 Amigoz

- Credenciais administrativas em Configurações, fora do navegador público e dos logs.
- Modos: margem, saque complementar ou ambos, conforme capacidade real da API.
- Estados, convênios e margens ligados aos respectivos IDs externos.
- Execução por API com controle próprio de concorrência, tempo limite e tratamento de respostas.
- Validar respostas de sucesso, ausência de disponibilidade, erro e dados parciais.
- Campanhas Amigoz fazem parte do objetivo, mas sua ativação depende da homologação em lote; não presumir que a consulta individual já valida todos os cenários de campanha.

## 8. Orquestração e desempenho

### 8.1 Execução paralela

Preservar quatro trabalhadores de navegador com distribuição por elegibilidade. Dois podem executar ConsigX e outro Digi+ simultaneamente. Não reservar um robô para uma fila que ele não pode atender enquanto existe trabalho elegível.

Ordenar retirada pela sequência da fila. A ordem de conclusão pode ser diferente, pois tarefas têm durações distintas. A tabela mantém ordenação estável definida pelo usuário.

### 8.2 Reserva de tarefas e recuperação

**Proposta técnica:** reserva atômica, identificador de execução, prazo de posse e heartbeat. Somente o trabalhador com reserva válida pode concluir a tarefa. Após queda, recuperar tarefas abandonadas, preservando resultados parciais. O identificador da execução também evita que uma resposta atrasada sobrescreva uma execução nova.

Aplicar idempotência à importação, criação de tarefas, consumo de cota, gravação de resultados e emissão de eventos. Não prometer execução exatamente uma vez no portal: uma queda depois da chamada externa pode exigir reconciliação. O sistema deve impedir duplicação interna e limitar reconsultas nesses casos.

### 8.3 Sessões eficientes

Reutilizar sessões apenas enquanto válidas e isoladas por robô, credencial, proxy e operação. Medir duração antes/depois: a otimização de sessões anterior teve relato de lentidão e precisa ser revisada, não simplesmente mantida por suposição.

Evitar esperas fixas longas; aguardar elementos ou respostas esperadas com limites claros. Renovar sessão por expiração, credencial alterada ou falha recuperável. Nunca misturar contexto de um cliente com o seguinte.

### 8.4 Proteção de recursos

Monitorar CPU, RAM, processos e capacidade. Reduzir concorrência por pressão sustentada, preferindo deixar concluir tarefa em andamento e suspender novas reservas. Em emergência, recuperar com segurança a tarefa interrompida. Reativar gradualmente após recuperação estável, evitando ligar/desligar repetidamente.

Limiares serão calibrados na VPS real; quatro robôs cadastrados não significam quatro navegadores sempre ativos em uma máquina de 2 GB.

### 8.5 Pausa, retomada e estimativa

Pausa manual impede novas reservas; informar tarefas ainda finalizando. Retomada usa pendências existentes. Nova tentativa cria execução ligada à anterior apenas para serviços selecionados, sem apagar resultados válidos.

Previsão por serviço baseada em duração recente, tamanho da fila, trabalhadores elegíveis e falhas. Pausas, cotas e serviços indisponíveis devem aparecer como impedimentos, não como contagem regressiva falsa.

## 9. Taxonomia de estados

Separar três eixos, com mapeamento compatível para os estados legados.

| Eixo | Exemplos |
| --- | --- |
| Processamento | Aguardando, em execução, finalizado, aguardando cota, bloqueado por dependência. |
| Resultado | Disponível, sem disponibilidade confirmada, não é cliente confirmado, parcial, consulta interrompida, falha técnica, revisão necessária. |
| Comercial | Novo, em contato, simulação enviada, negociação, ganho, perdido. |

“Concluída” significa que o processamento terminou, não que existe oferta ou aprovação. Valor zero confirmado não é erro. Disponibilidade em um serviço não implica disponibilidade nos demais.

### 9.1 Interrupção e falhas

- Mensagem visível: **Consulta interrompida**. Não mencionar chat.
- Sem resposta conclusiva após rotas/tentativas: não classificar como não cliente.
- Com saldo/parcela já obtido: resultado parcial, preservando valores e identificando o serviço pendente.
- Consulta interrompida isoladamente não provoca pausa automática da campanha.
- Proposta de pausa: dez falhas técnicas consecutivas qualificadas, após tentativas limitadas. Definir o contador por serviço/campanha e não misturar ausência de oferta com falhas.
- Em campanha multisserviço, propor pausa do serviço afetado e continuidade dos serviços independentes; a campanha mostra bloqueio parcial.
- Falha conclusiva de credencial pode desabilitar aquele acesso imediatamente, sem testar dez clientes.

### 9.2 Diagnóstico e autorrecuperação

Classificar acesso ao portal, DNS/conexão/TLS, proxy, login, sessão expirada, alteração de tela, limite externo, resposta inválida e erro interno. Quando a causa não for comprovada, registrar “causa não determinada”, com evidências.

Ações permitidas conforme diagnóstico: recriar página/contexto, renovar sessão, reiniciar trabalhador, repetir com espera controlada ou trocar rota Digi+. Registrar ação e resultado; nunca criar ciclo infinito. CAPTCHA e etapas humanas ficam pendentes de intervenção.

Logs individuais por robô/execução, com horários, etapa, duração, rota, classificação e tentativas, sem senhas ou tokens. Interface de consulta mostra apenas “Consultando…” e resultado; detalhe técnico fica recolhido em Configurações.

## 10. Permissões, cotas e trial

- Administrador cria usuários/parceiros e define serviços permitidos, inclusive Amigoz.
- Permissões independentes para consulta individual, campanhas e integrações.
- Restrição aplicada no servidor e banco, além de ocultar opções na interface.
- Trial com início/expiração; aviso dispensável de dias restantes e saldo diário.
- Cota diária compartilhada entre campanha e individual: consumir 50 de 100 em campanha deixa 50 para individual, conforme unidade definida.
- Preservar possibilidade de limites por tipo; definir relação entre teto global e limites específicos.
- Reservar cota atomicamente para evitar que quatro robôs ou chamadas simultâneas ultrapassem o permitido.
- Tentativas internas automáticas não devem consumir uma nova unidade repetidamente.
- Administrador e perfis ilimitados sem teto comercial artificial; limites técnicos de proteção não podem ser apresentados como plano comercial.
- Parceiro não vê instruções administrativas de troca de chaves/URL Supabase.

**Pendências:** unidade de consumo ao selecionar vários serviços para o mesmo CPF; tratamento de falhas e resultados reutilizados; horário de renovação; excedente de importação; comportamento no vencimento do trial. Recomendação inicial de horário: America/Sao_Paulo. Recomenda-se impedir novos trabalhos no vencimento e preservar dados, com política de leitura a aprovar.

## 11. Filtros, listas e oportunidades

### 11.1 Clientes e listas dinâmicas — proposta

Filtros por estado, convênio, campanha, responsável, matrícula ausente, margem, saque, saldo, parcela, data do resultado e situação comercial. Cada valor deve vir do serviço/vínculo escolhido, evitando combinar margem de um vínculo com dívida de outro.

Salvar combinações como listas dinâmicas: “PM-SP com saque disponível”, “Sem matrícula”, “Margem acima de R$ 250”, “Resultado desatualizado”. A lista se atualiza conforme os dados; a campanha preserva a composição histórica importada.

Ações em lote: atribuir responsável, criar oportunidades, consultar novamente e exportar. Mostrar claramente se a ação vale para a página ou todos os resultados filtrados.

### 11.2 Funil — objetivo aprovado, detalhamento proposto

Etapas iniciais sugeridas: Novo → Em contato → Simulação enviada → Em negociação → Ganho/Perdido. Etapas finais e nomes serão aprovados no protótipo.

Oportunidade associada ao cliente, vínculo e produto, com responsável, valor estimado, próxima ação e motivo de perda. Permitir oportunidades distintas para produtos distintos e prevenir duplicação de negociação equivalente aberta.

Primeira versão: criação manual em lote a partir de filtros. Evolução opcional: regras automáticas por resultado e valor mínimo, com registro da regra aplicada. Resultado de consulta representa potencial, não aprovação bancária.

### 11.3 Atendimento — proposta

“Meus clientes”, último contato, lembretes, aviso de atendimento em andamento e distribuição manual. Distribuição automática entre vendedores e reconsultas programadas ficam para etapa posterior. Um responsável padrão no cliente não impede responsáveis específicos por oportunidade, caso essa regra seja aprovada.

## 12. Simulador Amigoz

Preservar o simulador no contexto do resultado Digi+ e permitir salvar sua versão na oportunidade.

- Entradas: saldo de quitação e parcela; opção de agregar margem disponível e ajustar parcela.
- Apresentar todas as tabelas configuradas de uma vez.
- Usar taxa mensal contratual e prazo na fórmula Price, conforme última orientação; sem campos ou deduções de encargos/CET/IOF/teto pré-aprovado retirados do simulador.
- Para taxa decimal i > 0 e prazo n: valor estimado = parcela × (1 − (1 + i)^(-n)) / i. Para i = 0: parcela × n.
- Troco estimado = valor estimado − saldo de quitação. Se negativo, mostrar insuficiência, não troco disponível.
- Validar entradas, preservar precisão e exibir BRL com duas casas; resultados identificados como estimativas sem confirmação bancária.
- Exibir limite estimado, quitação e troco, sem painel de detalhes financeiros desnecessário.
- Comissão por tabela, configurada em Configurações, sobre dívida + troco; só mostrar quando houver percentual configurado e base aplicável.
- Conferir no código o cadastro das taxas já discutidas: 3%, 3,25%, 3,50%, 3,75%, 3,98%, 4,50% e 4,80%, com prazo principal de 96 meses. Não substituir parâmetros existentes sem conciliação.
- Ao agregar margem, distinguir parcela atual, margem adicional e nova parcela. Não somar valores de vínculos incompatíveis.

## 13. APIs, webhooks e exportações

### 13.1 Compatibilidade

Inventariar rotas e payloads atuais antes de alterar. Manter consumidores existentes; mudanças incompatíveis exigem versão ou migração documentada. IDs legados precisam permanecer rastreáveis.

Capacidades necessárias: listar/criar campanhas, adicionar clientes, consultar campanha, buscar cliente individual, obter consultas e filtrar resultados. Novas entidades CRM devem ser adicionadas sem renomear silenciosamente os significados das rotas antigas.

### 13.2 Todos os resultados, sem truncamento

Permitir obter todos os clientes correspondentes ao filtro, inclusive resultados já concluídos em campanhas ainda ativas. Não limitar silenciosamente a 50, 1.000 ou 5.000.

Proposta técnica: paginação por cursor para integrações e exportação completa assíncrona para conjuntos grandes. A interface/documentação deve oferecer caminho explícito para obter o conjunto inteiro, não apenas “a primeira página”. Se uma resposta única completa for necessária ao consumidor, avaliar streaming/exportação sem sacrificar a VPS.

Usar ordenação estável e opção de fotografia do conjunto para evitar saltos/duplicações enquanto a campanha recebe resultados. Filtros devem distinguir concluído de resultado positivo e serviço específico.

CPF formatado no padrão XXX.XXX.XXX-XX na UI, exportações e campos públicos já definidos, inclusive campanhas antigas. Normalização interna não pode quebrar deduplicação. Registros legados inválidos precisam ser identificados, não preenchidos artificialmente.

### 13.3 Webhooks

Configuração geral ou por campanha, com filtros por serviço e resultado: positivo, não cliente confirmado, falha, revisão, interrupção ou conclusão, conforme seleção.

Definir eventos por serviço concluído e por conjunto de consultas do cliente concluído, evitando disparos ambíguos. Enviar identificador do evento, campanha, cliente, serviço, execução, resultado e datas, respeitando campos permitidos.

Proposta: assinatura, fila persistente de entrega, tentativas com intervalo crescente, histórico de resposta e reenvio manual. Entrega pode repetir; consumidor usa ID do evento para deduplicar. Reconsulta gera execução/evento distinto. Evento deve representar o resultado daquela execução, não dados mutáveis de uma consulta futura.

Permissão de integrações controla acesso de parceiros a tokens, documentação e webhooks. Tokens com escopo e revogação; segredos não aparecem em logs. Credenciais e URLs de destino devem ser validadas no backend.

## 14. Configurações reorganizadas

| Seção | Conteúdo |
| --- | --- |
| Operação | Catálogo habilitado, regras operacionais e parâmetros autorizados. |
| Acessos | ConsigX por robô, proxy e credenciais Amigoz para administradores autorizados. |
| Robôs e monitoramento | Disponibilidade, serviço atual, desempenho, CPU/RAM e logs individuais. |
| Comissões | Percentuais por tabela do simulador. |
| Integrações | API, tokens, documentação, payloads, webhooks e entregas. |
| Usuários e parceiros | Perfis, serviços, campanhas, integrações, trial e cotas. |

Uma única área de credenciais ConsigX, com seletor Robô 1–4, status e data/versão de alteração. Senha em branco preserva a existente. Oferecer teste de acesso e confirmação de alteração sem expor senha em banco público ou log. A antiga duplicidade “acesso principal + acesso por robô” deve ser eliminada com migração explícita.

O sistema permanece integrado ao banco; não reintroduzir escolha de modo de operação. Troca de URL/chaves Supabase continua no instalador administrativo, preservando a divisão entre chave pública de autenticação e segredos do servidor.

## 15. Modelo técnico conceitual

Nomes abaixo são conceituais, não migrações prontas. Reutilizar estruturas existentes sempre que adequadas.

| Grupo | Entidades/responsabilidades |
| --- | --- |
| Acesso | Conta, usuário, perfil, permissões, trial, reservas e consumo de cota. |
| Catálogo | Estado, convênio, serviço, integração e disponibilidade/IDs. |
| CRM | Cliente, contatos, vínculos, alterações cadastrais e responsáveis. |
| Campanhas | Importação, campanha, participantes e serviços selecionados. |
| Execução | Tarefa, dependência, reserva, tentativa, resultado e diagnóstico. |
| Comercial | Oportunidade, etapa, atividade e simulação versionada. |
| Operação | Robô, credencial, sessão e métricas. |
| Integrações | Token, webhook, evento e tentativas de entrega. |

Definir transações para cadastro/participação, reserva de trabalho, cota e conclusão. Salvar resultado, atualização cadastral e evento de forma consistente, preferencialmente com fila transacional de eventos. Consultas paginadas e índices serão projetados pelos filtros reais após inspecionar o esquema.

## 16. Migração e atualização na VPS

1. Inventariar banco, código, versão implantada, serviços, integrações e campanhas em andamento.
2. Fazer backup verificável e ensaiar restauração em ambiente isolado.
3. Criar alterações aditivas e compatíveis; evitar remover colunas usadas pela versão ativa.
4. Preencher clientes/vínculos a partir de dados existentes em lotes idempotentes, sem inferir convênio ausente sem evidência.
5. Preservar IDs de campanhas/consultas e mapear legados para novas entidades.
6. Migrar credenciais e permissões mantendo isolamento; acessos antigos não serão copiados para todos os robôs silenciosamente.
7. Validar contagens, relações, CPFs, resultados e cotas antes/depois.
8. Publicar código compatível e ativar módulos progressivamente.
9. No instalador, impedir novas reservas, permitir drenagem controlada e reiniciar serviços com recuperação de tarefas.
10. Preservar .env, SSL, configuração, credenciais e campanhas. Registrar versão de código e banco.
11. Incluir verificação pós-atualização e procedimento de reversão compatível; não restaurar banco antigo cegamente sobre resultados novos.

O instalador continua com menu visual, identificação de instalação existente, atualização pelo GitHub via HTTPS, configuração de subdomínio/SSL e opções administrativas. Migrações devem passar a ter execução versionada e explícita no processo, sem presumir que o instalador atual já as executa.

README deve explicar instalação simples sem Docker, DNS, Nginx, SSL, atualização, backup, migração e recuperação. Não alterar serviços externos ou produção na etapa de planejamento.

## 17. Documentos pilares de design

Os sete Markdown fornecidos pelo usuário são referências do projeto. Ao implementar, preservá-los na documentação versionada e criar um índice de aplicação, sem depender apenas da memória da conversa.

| Documento | Aplicação |
| --- | --- |
| system-prompt(1).md | Processo de design intencional, contexto, hierarquia, interação e verificação. |
| discovery-questions(1).md | Esclarecer ambiguidades reais sem repetir perguntas respondidas. |
| design-system-extract(1).md | Extrair componentes/tokens da identidade e do código existente. |
| frontend-aesthetic-direction(1).md | Definir o que faltar na linguagem visual; não inventar outra marca. |
| wireframe(1).md | Explorar alternativas de estrutura antes de alta fidelidade. |
| accessibility-audit(1).md | Revisar contraste, semântica, teclado, movimento e formulários. |
| ai-slop-check(1).md | Remover padrões genéricos, excesso decorativo e inconsistências. |

Aplicar as recomendações conforme o contexto. Decisões específicas do usuário prevalecem. Variantes e controles de experimentação pertencem ao protótipo, não precisam aparecer para o usuário final do CRM.

## 18. Etapas de entrega e critérios de aprovação

### Fase 0 — Auditoria e fechamento do escopo

Entregas: matriz existente/incompleto/novo, inventário de integrações e catálogo, estados legados e decisões pendentes. Critério: cada requisito deste plano tem destino e dependência identificados.

### Fase 1 — UX e protótipo

Extrair design system; apresentar três alternativas de organização para os fluxos centrais, mantendo as regras definidas. Aprovar uma direção ou combinação e desenvolver protótipo navegável de importação, clientes, campanha e ficha, com estados de erro/vazio/carregamento.

Critério: usuário entende a próxima ação, identifica estado/convênio/serviços e consegue simular o fluxo completo. Nenhuma mudança de produção nessa fase.

### Fase 2 — Fundação e migração

Cliente/vínculos, catálogo, permissões, histórico e compatibilidade. Ensaiar migração em cópia isolada. Critério: contagens e dados preservados, isolamento validado e reversão ensaiada.

### Fase 3 — Importação e execução integrada

Fluxo único, modelos adaptáveis, deduplicação, enriquecimento, campanhas com vários serviços e controle de cota. Homologar os serviços antes de ativá-los em lote. Critério: uma importação confirmada gera e conclui o trabalho autorizado, atualizando os cadastros corretamente.

### Fase 4 — Eficiência e observabilidade

Filas, quatro trabalhadores elegíveis, recuperação, sessões, diagnóstico, pausa técnica e previsão. Critério: paralelismo sem duplicação interna, reinício recuperável e capacidade controlada.

### Fase 5 — CRM comercial

Filtros, listas salvas, ficha completa, oportunidades, responsáveis, atividades e simulações. Critério: resultado positivo pode virar negociação rastreável sem exportar/reimportar dados.

### Fase 6 — Integrações e lançamento gradual

Compatibilizar APIs/webhooks durante as fases anteriores e concluir contratos/documentação aqui. Validar consumidor existente, exportação completa, instalador, acessibilidade e desempenho. Liberar progressivamente por perfil/serviço.

Automações comerciais avançadas, distribuição automática e reconsultas agendadas ficam em evolução posterior, salvo aprovação específica. Não incluem construir omnichannel, WhatsApp, telefonia, financeiro ou propostas bancárias completas neste escopo.

## 19. Matriz mínima de testes de aceite

| Cenário | Resultado esperado |
| --- | --- |
| Importação com convênios conflitantes | Bloqueio e indicação das linhas. |
| Seleção ConsigX | Modelo exige somente CPF e apresenta convênios BA válidos. |
| Seleção Digi+ e outros serviços | Modelo exige a união correta dos campos. |
| Reenvio da mesma confirmação | Não duplica campanha/tarefas. |
| CPF com zero inicial | Preservação interna e formatação BR na saída. |
| Cliente existente em nova campanha | Reutiliza cadastro sem perder histórico. |
| Consulta retorna matrícula | Atualiza vínculo correto com origem/data. |
| Duas matrículas ou resposta antiga atrasada | Não sobrescreve vínculo/valor novo incorretamente. |
| Falha ou campo vazio | Não apaga resultado anterior. |
| Saldo obtido e parcela interrompida | Resultado parcial e saldo preservado. |
| Rota curta Digi+ falha | Tenta rota alternativa com limite e log. |
| Interrupção sem resposta | Não vira não cliente e não pausa campanha isoladamente. |
| Dez falhas técnicas qualificadas | Pausa escopo afetado e informa motivo. |
| Dois acessos ConsigX entre quatro robôs | Só dois executam ConsigX; demais atendem trabalho elegível. |
| Reinício/atualização durante campanha | Retoma pendências sem perder resultados ou duplicar consumo. |
| Pressão de recursos | Reduz concorrência e recupera gradualmente. |
| Uso simultâneo campanha/individual | Respeita cota compartilhada de forma atômica. |
| Parceiro sem permissão | UI e backend impedem operação/acesso. |
| Parceiro importa CPF de outra conta | Não acessa dados de outro parceiro. |
| Campanha com milhares de clientes | Front carrega apenas página e resumos. |
| API filtra positivos em campanha ativa | Retorna todo o conjunto navegável/exportável, sem teto oculto. |
| Campanha antiga na API | CPF formatado e IDs compatíveis. |
| Webhook falha ou repete | Tentativas rastreadas e evento deduplicável. |
| Exclusão de campanha | Efeito explícito, sem apagar cadastro indevidamente. |
| Simulação com margem agregada | Valores coerentes, tabelas e comissão conforme configuração. |
| Teclado e tela menor | Fluxos essenciais utilizáveis com feedback e foco. |

Medir tempo por serviço (mediana e percentil 95), falhas por causa, tempo de fila, recuperações, memória por trabalhador e latência das telas/API. Definir metas depois da medição inicial; não prometer duração externa que o portal não garante.

## 20. Decisões pendentes antes da implementação dependente

| ID | Decisão | Recomendação inicial |
| --- | --- | --- |
| D01 | Cota para vários serviços no mesmo CPF | Definir explicitamente unidade e relação global/por tipo; não assumir cobrança por serviço. |
| D02 | Reutilização, falhas e reconsultas na cota | Retry interno sem consumo extra; demais regras visíveis antes de executar. |
| D03 | Excedente diário na importação | Permitir preparar campanha e aguardar renovação, se aprovado; nunca iniciar excedente silenciosamente. |
| D04 | Trial vencido | Parar novos trabalhos, preservar dados; definir leitura e tarefas em andamento. |
| D05 | Consultas simultâneas ou condicionais | Primeiro todas as selecionadas; sequência por resultado como opção explícita. |
| D06 | Prazo de validade para reutilizar resultado | Configurável por serviço; 24h foi sugestão, não regra aprovada. |
| D07 | Prioridade de atualização cadastral | Matriz por campo/fonte, com proteção manual. |
| D08 | Funil e automações comerciais | Aprovar etapas; começar por criação manual em lote. |
| D09 | Exclusão e retenção | Distinguir campanha, consulta, cliente e oportunidade. |
| D10 | Catálogo homologado | Conferir lista de convênios, IDs e serviços reais; não ativar por exemplo ilustrativo. |
| D11 | Política de pausa técnica | Dez falhas como ponto inicial; aprovar escopo/contador e tratamento multisserviço. |
| D12 | API de conjunto completo | Validar experiência do consumidor: cursor, exportação integral ou streaming. |

Essas pendências não impedem auditoria e wireframes. Impedem assumir silenciosamente regras de negócio em código.

## 21. Condições para iniciar e para concluir

Antes de desenvolver: aprovar o escopo consolidado, fechar decisões que afetem a primeira entrega, revisar implementação atual e aprovar a direção visual. A autorização para produzir este documento não equivale à autorização para migrar produção.

Uma entrega só será considerada concluída após testes pertinentes, validação visual, atualização das instruções de instalação e identificação clara do que foi homologado de verdade. Limitações de acesso a portais ou ausência de respostas reais devem ser informadas; não serão apresentadas como funcionamento garantido.

**Resultado esperado:** uma base de clientes continuamente enriquecida, organizada por estado e convênio, com consultas individuais e em lote, processamento recuperável, integrações compatíveis e oportunidades comerciais rastreáveis — sem perder o que já foi construído.
