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
CPF é string para preservar zeros; aceita pontuação. Os exemplos são fictícios.

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

Leads da campanha. Permissão: read.

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
      "cpf": "00000000000",
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

## POST /campanhas/{id}/leads

Adicionar leads à campanha pausada. Permissão: campanhas:write.

```bash
curl --request POST 'https://SEU_SUBDOMINIO/api/v1/campanhas/{id}/leads' \
  --header 'Authorization: Bearer SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: operacao-123' \
  --data '{"leads": [{"nome": "Cliente de exemplo", "cpf": "00000000000", "telefone": "11999999999", "referencia_externa": "contato-123"}]}'
```

Resposta 200:

```json
{
  "accepted": [
    {
      "linha": 1,
      "id": "00000000-0000-4000-8000-000000000002",
      "cpf": "00000000000"
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
  "cpf": "00000000000",
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
  --data '{"cpf": "00000000000"}'
```

Resposta 200:

```json
{
  "data": [
    {
      "id": "00000000-0000-4000-8000-000000000002",
      "campanha_id": "00000000-0000-4000-8000-000000000001",
      "cpf": "00000000000",
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
  --data '{"servico": "tjba_margem", "convenio": "tjba", "cpf": "00000000000", "referencia_externa": "contato-123"}'
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
  "cpf": "00000000000",
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

Projeto Supabase original já atualizado. Em outro projeto, aplique supabase/upgrade_api.sql após as migrações anteriores. Atualize a VPS pela opção 1 do instalador. Serviço apoiarcred-api escuta somente em 127.0.0.1:8877, publicado pelo Nginx em /api/. Sem porta pública adicional e sem Docker. Logs: journalctl -u apoiarcred-api -n 50. GET /api/health verifica processo; autenticação/dados exigem token. Nenhum token é gerado automaticamente.

## Parceiros e cotas

As permissões do token não ampliam as permissões da conta parceira. Novos pedidos
individuais respeitam o limite diário de cada serviço (Digi+ ou ConsigX), com
renovação à meia-noite em America/Sao_Paulo. HTTP 429 com error.code=daily_limit
indica cota esgotada; 403 partner_permission indica serviço/modalidade bloqueado.
Campanhas também precisam de permissão no perfil. Idempotência evita cobrança
repetida da mesma operação. Retentativa com chave nova é nova solicitação.
A administração de parceiros exige sessão de administrador em /api/admin/parceiros;
não pode ser feita por um token de integração.
