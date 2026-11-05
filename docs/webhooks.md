# Webhooks de resultados

Em **Configurações → Integrações → Webhooks**, crie uma integração com nome e URL HTTPS pública (porta 443). Também há um botão **Configurar webhook** no detalhe de cada campanha.

1. Escolha todas as origens, somente individuais ou uma campanha específica.
2. Escolha Digi+ ou ConsigX; a campanha fixa automaticamente o serviço. ConsigX abrange o convênio da campanha; não há filtro separado de convênio para origens gerais.
3. Marque os eventos desejados e combine status + identificação do cliente + resultados parciais.
4. Salve, copie o segredo de assinatura (exibido uma única vez) e configure a validação no destino.
5. Use **Enviar teste** e acompanhe a entrega. O teste envia dados fictícios, sem consultar o banco nem o portal do banco.

É possível manter vários webhooks. Limites do MVP: 20 por conta; 10 testes/reenvios manuais por hora por webhook. Cada usuário gerencia somente seus webhooks e resultados. Administradores não recebem automaticamente resultados dos parceiros.

## Eventos e filtros

| Evento | Quando | Filtros |
| --- | --- | --- |
| `consulta.finalizada` | Resultado final salvo após processamento | Origem, campanha, serviço, status, cliente e parcial |
| `campanha.finalizada` | Todos os leads da campanha estão em status final | Origem, campanha e serviço; ignora filtros de resultado |
| `webhook.teste` | Teste manual | Ignora filtros; exige webhook ativo |

Status enviados: `concluida`, `nao_cliente`, `nao_localizado`, `nao_encontrado`, `erro`, `revisao`. O webhook não envia progresso nem checkpoints intermediários. No Digi+, aguarda saldo e parcela terminarem; se a segunda consulta falhar, envia o saldo já salvo com status de revisão/erro e `resultado_parcial: true`.

Identificação possui três possibilidades:

- `true`: consulta concluída ou existe saldo/parcela, margem ou matrícula que identifique o cliente.
- `false`: portal retornou não cliente/não localizado/não encontrado.
- `null`: resultado inconclusivo, sem informação que confirme cliente.

Os filtros são cumulativos. Exemplo: para receber somente clientes identificados, escolha **Cliente identificado** e os status desejados. Para receber erros sem dados confirmados, escolha **Erro** + **Indeterminado**. Um cliente identificado pode ter status Revisão por uma falha parcial; excluir parciais impede esse disparo.

Somente resultados futuros geram eventos. Ativar/configurar um webhook não reenvia o histórico anterior. Uma nova rodada de tentativas ou novos leads pode gerar outro `campanha.finalizada` quando terminar. Campanhas vazias não disparam conclusão. O relatório conta os registros da campanha, incluindo resultados anteriores à criação do webhook, mas só é gerado por mudanças futuras no processamento. Os números de erro/revisão podem se sobrepor aos clientes quando existe resultado parcial.

## Payload: consulta Digi+

```json
{
  "event_id": "uuid-estavel-do-evento",
  "event": "consulta.finalizada",
  "occurred_at": "2026-11-05T12:00:00Z",
  "campanha": {"id": "uuid-da-campanha", "nome": "Campanha exemplo"},
  "consulta": {
    "id": "uuid-do-lead",
    "referencia_externa": "crm-123",
    "servico": "digimais_saldo_parcela",
    "convenio": null,
    "cpf": "00000000000",
    "nome": "Cliente fictício",
    "telefone": "00000000000",
    "status": "concluida",
    "cliente_identificado": true,
    "resultado_parcial": false,
    "mensagem": null,
    "resultado": {"saldo_liquidacao": 1000, "valor_parcela": 100, "total_parcelas": 96}
  }
}
```

Dados acima são fictícios. CPF e telefone são texto; CPF tem 11 dígitos sem pontuação, preservando zeros. Valores monetários são números em reais; informação ausente é `null`. Em consulta individual, `campanha` é `null`.

Para ConsigX, `servico` é `tjba_margem`, `convenio` identifica TJBA/DPEBA/EMBASA/SAEB/SUPREV, e `resultado` contém `emprestimo_disponivel`, `cartao_disponivel`, `matricula`, `tipo_servidor`, `situacao_atual`. Os valores não retornados são `null`. O teste usa valores fictícios do serviço selecionado (Digi+ quando a integração aceita todos os serviços).

## Payload: campanha

```json
{
  "event_id": "uuid-estavel-do-evento",
  "event": "campanha.finalizada",
  "occurred_at": "2026-11-05T12:00:00Z",
  "campanha": {"id": "uuid-da-campanha", "nome": "Exemplo", "servico": "digimais_saldo_parcela", "convenio": null},
  "relatorio": {"total": 10, "clientes": 6, "nao_clientes": 2, "indeterminados": 2, "erros": 1, "revisao": 1}
}
```

## Recebimento e autenticação

O serviço envia POST JSON UTF-8 com os cabeçalhos:

| Cabeçalho | Conteúdo |
| --- | --- |
| `X-ApoiarCred-Event-Id` | Mesmo `event_id` do corpo; deduplicar por ele |
| `X-ApoiarCred-Delivery-Id` | Identificador da entrega para esse webhook |
| `X-ApoiarCred-Timestamp` | Unix timestamp em segundos da tentativa |
| `X-ApoiarCred-Signature` | `v1=` seguido do HMAC-SHA256 hexadecimal |

Assinatura: HMAC-SHA256 usando o segredo como texto UTF-8 (incluindo `whsec_`), sobre `timestamp + "." + corpo HTTP original`. Não reconstrua o JSON antes de validar. Valide timestamp com tolerância de 5 minutos e compare assinaturas em tempo constante. Mantenha os relógios sincronizados.

Exemplo de validador Node.js (módulo nativo; `rawBody` é Buffer capturado antes de qualquer parser JSON):

```js
import {createHmac, timingSafeEqual} from 'node:crypto';

export function validarWebhook(headers, rawBody, secret) {
  const timestamp = headers['x-apoiarcred-timestamp'];
  const signature = headers['x-apoiarcred-signature'];
  if (!/^\d+$/.test(timestamp || '') ||
      Math.abs(Date.now() / 1000 - Number(timestamp)) > 300 ||
      !/^v1=[a-f0-9]{64}$/.test(signature || '')) return false;
  const expected = createHmac('sha256', secret)
    .update(timestamp + '.').update(rawBody).digest();
  return timingSafeEqual(expected, Buffer.from(signature.slice(3), 'hex'));
}
```

Depois de validar, registre o evento em uma fila/tabela com chave única `event_id` e devolva HTTP 200/202/204 rapidamente. Se o evento já existir, devolva 2xx sem processar novamente. Entrega é **pelo menos uma vez**: falhas após receber a requisição podem causar repetição, inclusive em reenvio manual. Se o mesmo receptor receber por mais de um webhook, inclua a identificação da integração na estratégia de deduplicação quando precisar de processamentos independentes.

Os segredos ficam cifrados no Supabase Vault; a lista e o histórico não devolvem o segredo. Trocar segredo invalida a assinatura antiga para próximos envios. Nenhuma credencial do portal ou chave do Supabase vai no payload.

## Fila, tentativas e histórico

O robô salva o resultado e um trigger grava evento + entrega na mesma transação. O serviço independente `apoiarcred-webhooks` busca a fila a cada 5 segundos e faz até dois envios simultâneos. Ele não executa navegação bancária. Relatórios são agregados nesse serviço, fora da gravação do resultado.

HTTP 2xx confirma entrega. Falhas de rede, 408, 425, 429 e 5xx permitem até 8 tentativas totais, com intervalos de 30 segundos, 2 minutos, 10 minutos, 30 minutos, 2 horas, 6 horas e 12 horas. Outros códigos, certificado TLS inválido ou destino proibido encerram a entrega como falha. Não seguimos redirecionamentos e não armazenamos o corpo de resposta do destino. Somente HTTPS público porta 443, com resolução de DNS validada e IP fixado por tentativa; endereços internos/locais são bloqueados.

O histórico mostra as últimas 50 entregas, HTTP, tentativas, erro e próximo horário. **Reenviar** está disponível para entregas concluídas ou falhas. Mantém o evento original e reinicia o limite de 8 tentativas. Não reenvia enquanto o item já estiver aguardando ou sendo enviado.

Editar URL ou trocar segredo afeta as próximas retiradas da fila, incluindo eventos antigos ainda pendentes e reenvios. Pausar impede novos eventos para essa integração e bloqueia a retirada dos pendentes; um envio já iniciado pode terminar. Retomar mantém pendentes. Resultados ocorridos durante a pausa não são recuperados automaticamente. O MVP não apaga automaticamente o histórico.

## Instalação e atualização na VPS

A opção **1** do auto instalador copia o painel e o despachante, instala/atualiza o serviço e o inicia automaticamente, sem Docker e sem uma nova porta pública. Usa `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` já existentes em `/opt/apoiarcred/.env`.

Para o projeto Supabase já conectado, a migração de webhooks foi aplicada. Outro projeto existente precisa executar uma única vez `supabase/upgrade_webhooks.sql` no SQL Editor; instalação do banco do zero usa `supabase/schema.sql`, que já inclui essa estrutura. O auto instalador não aplica migrações SQL em outros projetos.

Diagnóstico na VPS:

```bash
systemctl status apoiarcred-webhooks --no-pager
journalctl -u apoiarcred-webhooks -n 50 --no-pager
```

Se o histórico permanecer “Na fila”, verifique o serviço e as credenciais do servidor. Segredos, URLs e conteúdos de CPF não são impressos pelo despachante. Após atualizar a VPS, recarregue a página com Ctrl+F5.
