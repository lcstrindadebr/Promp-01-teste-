# Piloto Digi+ por HTTP — exclusivo do administrador

Em **Configurações → Robôs e monitoramento → Digi+ · API experimental**, cada administrador escolhe Robôs ou API para novas consultas da própria conta. O padrão continua Robôs. Parceiros não veem o controle e o banco recusa a configuração e a reserva de consultas API para usuários sem perfil administrador ativo.

O modo é gravado na inclusão da consulta, inclusive em importações, campanhas e solicitações pela API V1. Salvar a preferência atualiza os clientes aguardando nas campanhas Digi+ da conta, inclusive campanhas pausadas. Consultas iniciadas terminam pelo modo original. Pausar impede novas reservas, mantendo os trabalhos em andamento até a gravação final. Os controles de pausa de campanha também continuam válidos.

Há até 12 clientes simultâneos no conjunto do piloto (não 12 para cada conta). Cada cliente executa saldo e depois parcela, com sessões e cookies separados. O administrador pode reduzir seu limite entre 1 e 12. A capacidade da VPS começa em 12; o monitor reduz uma vaga a cada amostra de RAM insuficiente ou três amostras de CPU ≥95%, e recupera uma vaga após seis amostras saudáveis. Amostras a cada cinco segundos; falha de leitura reduz a uma vaga. Os robôs continuam com o controle existente, observando os mesmos recursos globais. Reduções não abortam consultas ativas.

## Fluxos preservados

Mesmos menus, esperas 8/5/6/8 segundos, paginação 20/20/30 e critérios de `sucesso` dos JSON enviados. Cada fluxo faz oito chamadas HTTP. Não há correção do falso sucesso, espera adaptativa ou nova paginação. Sessões, nomes, CPFs e telefones vêm do trabalho reservado. Limite de transporte: 45 segundos por chamada. Erros de transporte não são repetidos automaticamente. A gravação final pode ser repetida sem consultar o cliente novamente.

Os objetos `resultado_saldo` e `resultado_parcela` preservam o retorno, incluindo `sucesso`, valores originais e mensagens. O saldo é salvo antes da parcela; falha nessa gravação interrompe a segunda etapa. Ausência de menu/retorno segue para Revisão. A mensagem de encaminhamento para assessoria é exibida no resultado, sem presumir ausência de cliente e sem modificar a lógica de extração. O piloto não emite boletos nem realiza negociações.

## Métricas

Painel exclusivo de administrador: capacidade global, clientes em execução, finalizados por hora, tempo médio, resultados com ambos os valores, resultados sem ambos, revisões e consultas que receberam HTTP 429. Janela móvel de uma hora, reiniciada com o worker. As métricas são agregadas entre administradores; nenhum dado de cliente aparece no monitor. `Concluída` segue o critério original; use a contagem **saldo e parcela preenchidos** para avaliar utilidade real. Aguardar 12 vagas não representa garantia de throughput do provedor.

## Instalação

Aplicar `supabase/upgrade_digimais_api_pilot.sql` em bancos existentes; instalações novas já incluem as definições em `schema.sql`. Configuração do fornecedor fica em `apoiarcred_private.digimais_api_config`, acessível apenas pelo serviço. Preencher `config` com `baseUrl`, `accountUid` e `code` do nó Config dos fluxos autorizados. Não colocar dados de clientes, cookies ou esses parâmetros no frontend ou no repositório. Este projeto já foi configurado no banco conectado.

Atualize a VPS pelo instalador existente e reinicie o worker/monitor pelo processo normal de atualização. O novo módulo usa apenas a biblioteca padrão Python; nenhuma dependência adicional. A escolha de API permanece desativada até o administrador salvá-la. Sem configuração, o supervisor aguarda e os robôs continuam funcionando. Os RPCs de reserva e de leitura da configuração são exclusivos de `service_role`; não são rotas públicas da API V1.

## Validação

Testes locais usam respostas simuladas e verificam as 16 requisições, sessões separadas, esperas originais, falso sucesso preservado, encaminhamento à assessoria, checkpoint, 12 execuções simultâneas e retentativa apenas da gravação. O teste SQL transacional valida privilégios, captura do modo, pausa, limite global, limite por conta e bloqueio após retirada do perfil administrador; termina com rollback.

A validação da carga real de 12 consultas e do consumo de CPU/RAM deve ocorrer após a atualização da VPS. O teste anterior de quatro clientes confirmou dois retornos completos, um retorno indeterminado e um encaminhamento à assessoria; não determina custos nem capacidade sustentada.
