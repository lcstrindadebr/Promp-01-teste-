# ApoiarCred · Central de consultas

Painel para consulta individual, importação CSV (até 1.000 linhas), histórico, exportação e fila persistente no Supabase. Primeiro robô: saldo de liquidação Digi+.

## Estado da entrega
- Supabase próprio `apoiarcred-consultas` criado em São Paulo; tabelas e RLS por usuário aplicadas.
- Login e-mail/senha para usuários existentes no Supabase Auth; não há cadastro público no painel.
- Worker Docker consome a fila atomicamente e executa Playwright em uma sessão isolada por cliente.
- Robô programado a partir do roteiro demonstrado e dos seletores observados no chat.
- Cinco testes do parser aprovados (saldo, ausência de contrato, resposta incompleta e sessão encerrada).
- **Homologação completa com cliente autorizado na VPS ainda pendente.** Envio por Enter e formato final do saldo devem ser confirmados. O padrão é `ROBOT_MODE=disabled`.

## Instalar na VPS
Ubuntu x86-64, Docker Engine e Compose. Sugestão inicial: 4 vCPU, 8 GB RAM, 80 GB SSD.

```bash
# Após clonar o repositório:
cp .env.example .env
# Edite .env no servidor e preencha a chave secreta do Supabase.
docker compose up -d --build
```

Painel disponível em `127.0.0.1:8088`. Use Traefik com HTTPS ou túnel SSH para acessar. O worker não expõe portas. Para Traefik via rede Docker, conecte o serviço painel à rede do proxy, porta 80.

A chave `SUPABASE_SERVICE_ROLE_KEY` é obtida no dashboard Supabase, Project Settings → API Keys. Ela fica exclusivamente em `.env` na VPS. Nunca colocar no frontend, Git ou chat. O frontend usa somente a chave publishable protegida por RLS.

## Primeiro acesso
1. No projeto Supabase, crie seu usuário em Authentication → Users, com senha definida por você.
2. Abra o painel → Configurações → entre com esse usuário.
3. Selecione **Supabase · fila real** e salve.
4. Faça uma consulta individual ou envie CSV com `nome;cpf;telefone`. Preserve CPF como texto de 11 dígitos.
5. A fila continua na VPS com o navegador fechado. A demonstração local é separada e tem valores fictícios.

O painel apresenta até os 1.000 registros mais recentes do usuário; paginação histórica é melhoria posterior. Login de ponta a ponta depende de um usuário criado no Auth e ainda não foi homologado nesta entrega.

## Homologar o robô
1. No modo disabled, uma consulta recebida deve retornar Revisão, informando que não foi feita consulta bancária.
2. Com cliente autorizado para teste, configure `ROBOT_MODE=live` na VPS e execute `docker compose up -d --force-recreate worker`.
3. Confira uma consulta com contrato e uma sem contrato, comparando com o atendimento manual.
4. Valide falhas de rede, sessão encerrada e resposta inesperada antes de iniciar lotes.

Caminho: nome/telefone → Empréstimo consignado → Boleto → CPF → Saldo Liquidação. Não seleciona atendimento humano automaticamente. Verificações adicionais são marcadas para revisão, sem tentativa de contorno.

Concluída exige saldo e parcelas reconhecidos. Documento não localizado é resultado próprio, nunca saldo zero. Valores ausentes ficam nulos.

## Operação e segurança
RLS restringe cada usuário aos próprios lotes e consultas. Clientes autenticados podem inserir dados de entrada, mas não alterar resultados. Somente o worker pode assumir tarefas via `claim_consulta_job`, que usa `FOR UPDATE SKIP LOCKED`.

Se o worker cair no meio de uma consulta, o registro permanece processando para revisão. Não há reenvio automático sem reconciliação. Tentar novamente cria nova consulta, preservando a anterior. Defina retenção e backups antes de operar com dados reais. Não há administração multiempresa neste MVP.

## Verificar código
```bash
python -m unittest discover -s tests -v
node --check dist/app.js
node --check dist/supabase.js
```

A estrutura SQL já aplicada está em `supabase/schema.sql`. Não reaplicar no projeto atual. Em outro banco vazio, executar o SQL e substituir a URL/chave publishable em `dist/supabase-config.js`, além das variáveis do worker.
