# ApoiarCred API v1

Base: https://SEU_SUBDOMINIO/api/v1. Gere um token em Configurações → Integrações.
Authorization: Bearer SEU_TOKEN. Não use as chaves do Supabase nas integrações.

Permissões: read, campanhas:write, consultas:create. Token é mostrado uma vez,
guardado por SHA-256, expira na data configurada (ou sem expiração) e pode ser revogado.
Limite: 120 requisições/minuto por token; HTTP 429 inclui Retry-After: 60.
Nginx também limita 5 requisições/s por IP, com rajada de 20 (429).
Sem CORS: use integrações no servidor. OpenAPI: /openapi.json.

## Fluxo de campanhas
1. POST /campanhas cria pausada.
2. POST /campanhas/{id}/leads adiciona leads a uma campanha pausada. Parceiros podem enviar até 1.000 leads por requisição. Administradores podem enviar qualquer quantidade, respeitando o tamanho de 2 MB por requisição.
3. Confira accepted, duplicates e rejected; linhas inválidas não impedem as válidas.
4. POST /campanhas/{id}/iniciar libera a fila. Para adicionar novos leads, pause primeiro.
5. GET /campanhas/{id} consulta relatório; GET /campanhas/{id}/leads lista resultados.

POST /consultas responde 202 com id. Consulte GET /consultas/{id} até terminar.
A API usa a fila existente, sem prometer retorno imediato do banco. Pausa não
interrompe consultas já reservadas. Repetir revisões respeita a pausa atual.
Um registro de lead corresponde a uma consulta; CPF pode repetir em campanhas diferentes.
Use POST /leads/buscar para procurar por CPF e avaliar data e campanha do resultado.
Envie o CPF como texto, com ou sem pontuação. As respostas usam `000.000.000-00` e preservam zeros à esquerda. Os exemplos são fictícios.

Escritas exigem Idempotency-Key única por operação, vinculada ao token por 24h.
Reenvie a mesma chave, rota e JSON em caso de timeout; recebe a resposta original,
com Idempotency-Replayed: true. Outra operação/payload com a mesma chave dá 409.
Uma chave nova significa nova operação. Erros não são cacheados.

Listas: page >= 1 e page_size 1..100 (padrão 50), com pagination.total.
Campanhas: filtros servico e paused=true/false. Leads de campanha: filtro status.
Busca CPF: aceita campanha_id opcional, page e page_size no JSON.
Status: aguardando, processando, concluida, nao_cliente, nao_localizado,
nao_encontrado (ConsigX), erro, revisao e interrompida (Digi+). Campos não retornados permanecem null.
Digi+ só consulta parcela se o saldo identificar cliente. Resultado inclui saldo,
parcela e total de parcelas; ConsigX retorna margens, matrícula e situação.

## n8n
No HTTP Request, importe o cURL abaixo, substitua domínio/IDs e configure o token
em uma credencial Header Auth: nome Authorization, valor Bearer SEU_TOKEN.
Para POST, selecione JSON e gere uma chave de idempotência por operação. Preserve
a mesma chave nas tentativas da mesma operação. Não gere uma chave nova a cada retry.
Para acompanhar, use o id retornado e faça GET /consultas/{id} periodicamente.

## GET /servicos

Serviços disponíveis. Permissão: read.

```bash
curl --request GET 'https://SEU_SUBDOMINIO/api/v1/servicos' \
  --header 'Authorization: Bearer SEU_TOKEN'
```

Resposta 200:

```json
{
  "data": [
    {
      "id": "digimais_saldo_parcela",
      "campos_obrigatorios": [
        "nome",
        "cpf",
        "telefone"
      ]
    },
    {
      "id": "tjba_margem",
      "campos_obrigatorios": [
        "cpf"
      ],
      "convenios": [
        "tjba",
        "dpeba",
        "embasa",
        "saeb",
        "suprev"
      ]
    }
  ]
}
```

## GET /campanhas

Listar campanhas. Permissão: read.

```bash
curl --request GET 'https://SEU_SUBDOMINIO/api/v1/campanhas' \
  --header 'Authorization: Bearer SEU_TOKEN'
```

Resposta 200:

```json
{
  "data": [
    {
      "id": "00000000-0000-4000-8000-000000000001",
      "nome": "Campanha de exemplo",
      "servico": "digimais_saldo_parcela",
      "convenio": null,
      "paused": true
    }
  ],
  "pagination": {
    "page": 1,
    "page_size": 50,
    "total": 1
  }
}
```

## POST /campanhas

Criar campanha pausada. Permissão: campanhas:write.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/campanhas' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: operacao-123' \
  --data '{"nome": "Campanha de exemplo", "servico": "digimais_saldo_parcela"}'
```

Resposta 201:

```json
{
  "id": "00000000-0000-4000-8000-000000000001",
  "nome": "Campanha de exemplo",
  "servico": "digimais_saldo_parcela",
  "convenio": null,
  "paused": true
}
```

## GET /campanhas/{id}

Andamento e relatório. Permissão: read.

```bash
curl --request GET 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}' \
  --header 'Authorization: Bearer SEU_TOKEN'
```

Resposta 200:

```json
{
  "id": "00000000-0000-4000-8000-000000000001",
  "nome": "Campanha de exemplo",
  "servico": "digimais_saldo_parcela",
  "convenio": null,
  "paused": true,
  "relatorio": {
    "total": 1,
    "clientes": 0,
    "nao_clientes": 0,
    "erros": 0,
    "revisao": 0,
    "interrompidas": 0,
    "aguardando": 1,
    "processando": 0
  }
}
```

## GET /campanhas/{id}/leads

Leads da campanha. Permissão: read. Sem parâmetros, retorna 50 por página.
Para todos os leads, use `GET /campanhas/{id}/leads?all=true`. Pode combinar
`all=true&status=concluida`. Nesse modo a resposta é `{"data":[...],"total":N}`.
Use a listagem paginada em telas que carregam os resultados sob demanda.

```bash
curl --request GET 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}/leads' \
  --header 'Authorization: Bearer SEU_TOKEN'
```

Resposta 200:

```json
{
  "data": [
    {
      "id": "00000000-0000-4000-8000-000000000002",
      "campanha_id": "00000000-0000-4000-8000-000000000001",
      "cpf": "000.000.000-00",
      "status": "aguardando",
      "progress": 0,
      "resultado": {
        "saldo_liquidacao": null,
        "total_parcelas": null,
        "valor_parcela": null
      }
    }
  ],
  "pagination": {
    "page": 1,
    "page_size": 50,
    "total": 1
  }
}
```

## GET /campanhas/{id}/leads/status/{status}

Lista todos os leads com o status informado, em uma única resposta. Permissão
`read`. A campanha pode estar rodando. Para buscar clientes Digi+ com consulta
concluída, use `concluida`. Resultados parciais têm seu próprio status.

```bash
curl --request GET 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}/leads/status/concluida' \
  --header 'Authorization: Bearer SEU_TOKEN'
```

A resposta contém `data` com os leads e `total` com a quantidade retornada.
Sem correspondências, retorna `{"data":[],"total":0}`. Status inválido retorna
422. Use os códigos de status da API, como `erro`, `revisao` e `nao_cliente`.

## POST /campanhas/{id}/leads

Adicionar leads à campanha pausada. Permissão: campanhas:write.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}/leads' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: operacao-123' \
  --data '{"leads": [{"nome": "Cliente de exemplo", "cpf": "000.000.000-00", "telefone": "11999999999", "referencia_externa": "contato-123"}]}'
```

Resposta 200:

```json
{
  "accepted": [
    {
      "linha": 1,
      "id": "00000000-0000-4000-8000-000000000002",
      "cpf": "000.000.000-00"
    }
  ],
  "duplicates": [],
  "rejected": []
}
```

## POST /campanhas/{id}/iniciar

Iniciar ou retomar campanha. Permissão: campanhas:write.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}/iniciar' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: operacao-123' \
  --data '{}'
```

Resposta 200:

```json
{
  "id": "00000000-0000-4000-8000-000000000001",
  "paused": false
}
```

## POST /campanhas/{id}/pausar

Pausar novas consultas. Permissão: campanhas:write.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}/pausar' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: operacao-123' \
  --data '{}'
```

Resposta 200:

```json
{
  "id": "00000000-0000-4000-8000-000000000001",
  "paused": true
}
```

## POST /campanhas/{id}/repetir-revisoes

Reenfileirar erros e revisões. Permissão: campanhas:write.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}/repetir-revisoes' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: operacao-123' \
  --data '{}'
```

Resposta 202:

```json
{
  "reenfileirados": 1,
  "paused": true
}
```

## GET /leads/{id}

Registro individual e resultado. Permissão: read.

```bash
curl --request GET 'https://SEU_SUBDOMINIO/api/v1/leads/{id}' \
  --header 'Authorization: Bearer SEU_TOKEN'
```

Resposta 200:

```json
{
  "id": "00000000-0000-4000-8000-000000000002",
  "campanha_id": "00000000-0000-4000-8000-000000000001",
  "cpf": "000.000.000-00",
  "status": "aguardando",
  "progress": 0,
  "resultado": {
    "saldo_liquidacao": null,
    "total_parcelas": null,
    "valor_parcela": null
  }
}
```

## POST /leads/buscar

Buscar registros por CPF. Permissão: read.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/leads/buscar' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{"cpf": "000.000.000-00"}'
```

Resposta 200:

```json
{
  "data": [
    {
      "id": "00000000-0000-4000-8000-000000000002",
      "campanha_id": "00000000-0000-4000-8000-000000000001",
      "cpf": "000.000.000-00",
      "status": "aguardando",
      "progress": 0,
      "resultado": {
        "saldo_liquidacao": null,
        "total_parcelas": null,
        "valor_parcela": null
      }
    }
  ],
  "pagination": {
    "page": 1,
    "page_size": 50,
    "total": 1
  }
}
```

## POST /consultas

Solicitar consulta individual. Permissão: consultas:create.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/consultas' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: operacao-123' \
  --data '{"servico": "tjba_margem", "convenio": "tjba", "cpf": "000.000.000-00", "referencia_externa": "contato-123"}'
```

Resposta 202:

```json
{
  "id": "00000000-0000-4000-8000-000000000002",
  "campanha_id": "00000000-0000-4000-8000-000000000001",
  "status": "aguardando"
}
```

## GET /consultas/{id}

Acompanhar consulta individual. Permissão: read.

```bash
curl --request GET 'https://SEU_SUBDOMINIO/api/v1/consultas/{id}' \
  --header 'Authorization: Bearer SEU_TOKEN'
```

Resposta 200:

```json
{
  "id": "00000000-0000-4000-8000-000000000002",
  "campanha_id": "00000000-0000-4000-8000-000000000001",
  "cpf": "000.000.000-00",
  "status": "aguardando",
  "progress": 0,
  "resultado": {
    "saldo_liquidacao": null,
    "total_parcelas": null,
    "valor_parcela": null
  }
}
```

## Instalação

Projeto Supabase original já atualizado. Em outro projeto, aplique as migrações da API em ordem, incluindo `supabase/upgrade_api_campaign_leads.sql` para a listagem completa. Atualize a VPS pela opção 1 do instalador. Serviço apoiarcred-api escuta somente em 127.0.0.1:8877, publicado pelo Nginx em /api/. Sem porta pública adicional e sem Docker. Logs: journalctl -u apoiarcred-api -n 50. GET /api/health verifica processo; autenticação/dados exigem token. Nenhum token é gerado automaticamente.

## Parceiros e cotas

As permissões do token não ampliam as permissões da conta parceira. Novos pedidos
individuais respeitam o limite diário de cada serviço (Digi+ ou ConsigX), com
renovação à meia-noite em America/Sao_Paulo. HTTP 429 com error.code=daily_limit
indica cota esgotada; 403 partner_permission indica serviço/modalidade bloqueado.
Campanhas também precisam de permissão no perfil. Idempotência evita cobrança
repetida da mesma operação. Retentativa com chave nova é nova solicitação.
A administração de parceiros exige sessão de administrador em /api/admin/parceiros;
não pode ser feita por um token de integração.

## Oportunidades

Abra `/swagger.html` para navegar pela especificação Swagger ou importe `/openapi.json` no Postman. Os exemplos no Swagger são somente para consulta. Execute chamadas no seu cliente de API usando o token da sua conta.

| Método | Rota sob `/api/v1` | Permissão |
| --- | --- | --- |
| GET | `/oportunidades` | `read` |
| GET | `/oportunidades/{id}` | `read` |
| POST | `/oportunidades/{id}/etapa` | `campanhas:write` |
| POST | `/oportunidades/exportacao` | `campanhas:write` |

Para exportar, liste as páginas com `GET /oportunidades?exportaveis=true&tipos=margem,recompra&page_size=100`. Os tipos são `margem` (contrato novo), `recompra` (Digi+) e `saque` (Amigoz). Use `etapa` para restringir a seleção. Cada linha deve corresponder a um ID de oportunidade. Um CPF pode ter várias oportunidades.

Gere o arquivo com os dados lidos. Em seguida envie os IDs efetivamente incluídos e a etapa original de cada um para `POST /oportunidades/exportacao`. O servidor move para `exportada` apenas os registros da sua conta que continuam na etapa aberta informada. O retorno contém `movidas` e `ids`. A rota recebe até 500 itens por chamada. Use uma `Idempotency-Key` por lote e reutilize a mesma chave se precisar repetir o mesmo envio.

Para uma movimentação individual, envie `{"etapa_original":"novo","etapa":"contato"}` com `Idempotency-Key`. Se a etapa já mudou, a API devolve 409.

## Importação da base de clientes

`GET /api/v1/clientes/convenios?uf=BA` lista os IDs, os campos e os serviços liberados para cada convênio. O filtro `uf` é opcional. Use um token com escopo `read`. Na interface, os mesmos dados ficam em **Clientes → Importar base → Lista de convênios e IDs**.

`POST /api/v1/clientes/importacoes` aceita de 1 a 10.000 clientes de um mesmo convênio por envio, com até 2 MB de JSON. Envie `Authorization: Bearer SEU_TOKEN` com escopo `campanhas:write`, `Content-Type: application/json` e uma `Idempotency-Key` de 1 a 128 caracteres por importação. A chave fica registrada por 24 horas após o sucesso. Repita a mesma chave e o mesmo conteúdo se precisar reenviar.

### Bahia — SAEB

Use `servicos: []` para cadastrar margens já conhecidas ou `["consigx_margem"]` para enfileirar a consulta de margem. O SAEB oferece margem de empréstimo e de cartão pelo ConsigX.

```json
{
  "uf": "BA",
  "convenio": "saeb",
  "servicos": [],
  "clientes": [
    {
      "cpf": "000.000.008-92",
      "nome": "Pessoa Exemplo",
      "numero_matricula": "000123",
      "data_nascimento": "1985-04-23",
      "margem_emprestimo": 120.5,
      "margem_cartao": 45.25
    }
  ]
}
```

### Governo de São Paulo

Neste exemplo, o catálogo retorna `amigoz_23` e oferece Digi+. Nome e telefone com DDD são obrigatórios quando `digimais_saldo` é selecionado. Consulte o catálogo para ver os demais serviços do convênio.

```json
{
  "uf": "SP",
  "convenio": "amigoz_23",
  "servicos": [
    "digimais_saldo"
  ],
  "clientes": [
    {
      "cpf": "000.000.008-92",
      "nome": "Pessoa Exemplo",
      "telefone": "11900000000"
    }
  ]
}
```

Envie CPF, telefone e matrícula como texto para preservar zeros à esquerda. Use `AAAA-MM-DD` para data de nascimento e números em reais para `margem_emprestimo`, `margem_cartao` e `saque_amigoz_valor`. `margem_livre` é um alias legado da margem de empréstimo. O valor zero é um valor informado. Campos cadastrais e margens omitidos são preservados. Para atualizar um saque coletado por consulta, envie a elegibilidade e o valor juntos.

A resposta `201` traz `data.clientes`, `data.consultas` e `data.campanhas`. O contador de consultas representa itens enfileirados. Uma lista de serviços vazia retorna zero consultas. Cada lote é atômico. Qualquer linha inválida, CPF duplicado ou serviço não permitido cancela o lote inteiro. Serviços incompatíveis e dados inválidos geram `422`. Uma chave repetida com outro conteúdo gera `409`. Consulte o [Swagger](../dist/openapi.json) para os campos e exemplos completos.
