# ApoiarCred · Central de consultas

Guia de instalação em uma VPS Ubuntu com Docker, Nginx no servidor e HTTPS no subdomínio `consultas.apoiarcred.com.br`.

## 1. O que está pronto e o que falta

O MVP contém consulta individual, importação CSV, resultados, exportação, login Supabase e fila persistente. O primeiro robô foi programado para: nome/telefone → Empréstimo consignado → Boleto → CPF → Saldo Liquidação.

**O robô ainda precisa de homologação completa com cliente autorizado na VPS.** Os testes automatizados cobrem a interpretação das respostas, não comprovam execução completa no banco. Por isso, `ROBOT_MODE=disabled` é o padrão. Publicar o painel não ativa consultas bancárias.

O projeto Supabase `apoiarcred-consultas`, em São Paulo, já possui as tabelas e políticas instaladas. Não reaplique `supabase/schema.sql` nesse projeto.

## 2. Estrutura e requisitos

| Componente | Local |
|---|---|
| DNS do subdomínio | Provedor DNS do domínio |
| Nginx e certificado | VPS, portas 80 e 443 |
| Painel em container | VPS, somente 127.0.0.1:8088 |
| Worker Playwright | VPS, sem porta pública |
| Auth, lotes e resultados | Supabase |

Para uso interno e uma consulta por vez, comece com **2 vCPU, 4 GB RAM, 40 GB SSD, Ubuntu Server 24.04 LTS x86-64 e IPv4 público**. Meça o consumo antes de aumentar concorrência. Não precisa Windows, GPU ou cPanel.

Este guia assume VPS nova, usuário com `sudo`, porta SSH padrão 22 e domínio sob seu controle. Se já houver Traefik, Apache, Nginx ou outros sites, inspecione as portas antes: não execute dois proxies disputando 80/443 e não remova configurações existentes. Os comandos abaixo instalam serviços; não foram executados na sua VPS por este projeto.

## 3. Criar o DNS

No provedor que administra os nameservers do domínio, adicione:

| Tipo | Nome | Destino | TTL |
|---|---|---|---|
| A | consultas | IPv4 público da VPS | Automático |

Mantenha o domínio principal e seus registros de e-mail como estão. Não crie AAAA sem IPv6 configurado. Se houver AAAA antigo para esse subdomínio, corrija-o para não levar parte dos acessos ao servidor errado.

Se usar Cloudflare, comece com **Somente DNS**, emita o certificado e só depois, se desejar, habilite o proxy com SSL/TLS **Full (strict)**. Não use Flexible.

O endereço utilizado neste guia é um exemplo de configuração, não significa que o DNS já foi alterado.

### Encontrar o painel DNS correto

A empresa onde você comprou a VPS pode ser diferente da empresa que administra o DNS. Antes de alterar registros, consulte os nameservers:

```bash
dig +short NS apoiarcred.com.br
```

No Windows, antes de instalar qualquer ferramenta, você também pode executar no PowerShell:

```powershell
nslookup -type=NS apoiarcred.com.br
```

Faça a alteração no provedor indicado pelos nameservers. Não é necessário trocar os nameservers do domínio inteiro para criar esse subdomínio.

### Criar na Hostinger

1. Entre no hPanel → Domínios → Portfólio/Meus domínios.
2. Selecione `apoiarcred.com.br` → Gerenciar → DNS/Nameservers → registros DNS.
3. Adicione tipo **A**, nome **consultas**, destino **IP público da VPS** e TTL automático/padrão.
4. Salve. Se já existir A ou CNAME para o nome consultas, confira se está em uso antes de substituir; não mantenha um CNAME junto ao A no mesmo nome.

### Criar na Cloudflare

1. Abra a conta e selecione o domínio `apoiarcred.com.br`.
2. Entre em DNS → Records/Registros → Add record/Adicionar registro.
3. Tipo **A**, nome **consultas**, IPv4 **IP público da VPS**, TTL Auto.
4. Selecione **DNS only/Somente DNS** inicialmente e salve.

### Se o DNS estiver no Registro.br

Entre no domínio e localize a seção DNS → Configurar zona DNS. Essa edição só se aplica se os nameservers ativos forem os do Registro.br. No editor avançado, crie uma entrada A para consultas apontando ao IPv4 da VPS. Se aparecer somente o modo básico, revise a zona e as instruções do provedor antes de migrar para o modo avançado, preservando os registros existentes. Não troque de provedor DNS só para adicionar uma entrada.

### Exemplo de preenchimento e conferência

Se o IPv4 da VPS fosse `203.0.113.10` (endereço fictício), a entrada seria:

| Campo | Valor |
|---|---|
| Tipo | A |
| Nome/Host | consultas |
| IPv4/Destino | 203.0.113.10 — substituir pelo IP real |
| TTL | Auto ou padrão do provedor |

No campo Nome, normalmente se escreve apenas consultas; o painel completa o domínio. Confirme que o resultado é `consultas.apoiarcred.com.br`, sem duplicar o domínio. Não coloque `https://`, barras, porta 8088 ou caminhos no campo de destino do registro A.

Criar essa entrada cria o nome do subdomínio no DNS; o Nginx configurado na seção 9 define qual aplicação será exibida. Não precisa criar um site de hospedagem compartilhada na Hostinger. DNS não faz redirecionamento para URL e não libera porta de firewall.

Depois de salvar, confira de dois resolvedores:

```bash
dig @1.1.1.1 +short A consultas.apoiarcred.com.br
dig @8.8.8.8 +short A consultas.apoiarcred.com.br
```

No PowerShell:

```powershell
nslookup consultas.apoiarcred.com.br 1.1.1.1
```

Enquanto estiver Somente DNS, a resposta deve ser o IPv4 real da VPS. Pode haver cache até o TTL anterior expirar; não há prazo exato garantido. Com proxy Cloudflare ativo, a consulta mostrará IPs da Cloudflare, o que é esperado. Só prossiga com o certificado quando o DNS e o acesso HTTP estiverem corretos.

## 4. Entrar na VPS e instalar os utilitários

No terminal do seu computador (no Windows, PowerShell):

```bash
ssh SEU_USUARIO@IP_DA_VPS
```

Na VPS:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y ca-certificates curl git nginx ufw dnsutils nano snapd
sudo ss -lntp
```

Se a atualização pedir reinício, reinicie em uma janela adequada e conecte novamente. O comando `ss` mostra os serviços existentes; confirme quem usa 80, 443 e 8088.

### Firewall

Primeiro autorize sua porta SSH real. Se ela não for 22, adapte o primeiro comando **antes** de habilitar o firewall. Mantenha a sessão atual aberta e confirme acesso em uma segunda sessão.

```bash
sudo ufw allow 22/tcp
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status
```

No firewall do provedor, libere TCP 80 e 443 para acesso web, além da porta SSH para administração. Não libere 8088 nem portas de banco. O worker precisa de saída HTTPS/443 para Supabase e para o chat Digi+; a instalação também precisa de acesso aos repositórios de pacotes.

## 5. Instalar Docker e Compose

Em Ubuntu 24.04 limpo, use o repositório oficial:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
```

Essas instruções são específicas para Ubuntu 24.04 amd64. Em outra versão/arquitetura, use o guia oficial listado ao final. Se já houver Docker, verifique sua instalação em vez de misturar pacotes oficiais e `docker.io`.

## 6. Baixar a branch correta do GitHub

O código está na branch **apoiarcred-consultas-mvp**, não na main. O repositório é privado.

O clone é feito **na VPS, dentro da sessão SSH**, e baixa o projeto direto do GitHub, sem precisar baixar ZIP no computador. O comando completo está abaixo, após configurar a deploy key. A deploy key dá acesso somente de leitura ao repositório, suficiente para instalar e atualizar.

Não clone somente a main: ela não contém esta versão do sistema. A pasta de destino usada em todos os passos é `/opt/apoiarcred/consultas`.

Para clonar por SSH, configure na VPS uma chave dedicada ao repositório:

```bash
ssh-keygen -t ed25519 -C "apoiarcred-vps" -f ~/.ssh/apoiarcred_github
cat ~/.ssh/apoiarcred_github.pub
```

Cadastre **apenas a chave pública** em GitHub → repositório → Settings → Deploy keys → Add deploy key. Deixe escrita desabilitada. A chave privada permanece na VPS. No primeiro contato SSH, confira a impressão digital do GitHub na documentação oficial antes de aceitar.

```bash
sudo install -d -m 0755 -o "$(id -un)" -g "$(id -gn)" /opt/apoiarcred
GIT_SSH_COMMAND='ssh -i ~/.ssh/apoiarcred_github -o IdentitiesOnly=yes' git clone --branch apoiarcred-consultas-mvp --single-branch git@github.com:lcstrindadebr/Promp-01-teste-.git /opt/apoiarcred/consultas
cd /opt/apoiarcred/consultas
git config core.sshCommand 'ssh -i ~/.ssh/apoiarcred_github -o IdentitiesOnly=yes'
git branch --show-current
```

Se a pasta já existir, confira o conteúdo e use o checkout existente. Não apague uma instalação anterior. Não coloque tokens do GitHub na URL do clone.

## 7. Configurar o Supabase e o arquivo .env

No dashboard do projeto `apoiarcred-consultas`, obtenha a chave de servidor em **Project Settings → API Keys**. Use uma chave secret ou a legacy service_role apenas no worker.

```bash
cd /opt/apoiarcred/consultas
cp -n .env.example .env
chmod 600 .env
nano .env
```

Preencha:

```dotenv
SUPABASE_URL=https://yypwsxrlyvzvrbnwccmv.supabase.co
SUPABASE_SERVICE_ROLE_KEY=COLE_A_CHAVE_SECRETA_SOMENTE_NA_VPS
ROBOT_MODE=disabled
PANEL_BIND=127.0.0.1
PANEL_PORT=8088
```

Salve no Nano com Ctrl+O, Enter e Ctrl+X. Não use a chave publishable no lugar da chave do worker. Não envie a chave secreta por chat, não coloque em `dist` e não faça commit de `.env`.

`dist/supabase-config.js` já aponta para o projeto criado e contém somente a chave publishable, adequada ao navegador com RLS. Para outro projeto, configure a URL e a chave publishable nesse arquivo e instale o schema somente no banco novo e vazio.

Em Supabase → Authentication → Users, crie um usuário com e-mail e senha definidos por você. Não existe cadastro aberto no painel. Para acessos da equipe, crie um usuário por pessoa. No modelo atual, cada usuário vê apenas os próprios lotes e consultas; não há visão compartilhada de equipe.

Em Authentication → URL Configuration, configure Site URL como `https://consultas.apoiarcred.com.br`. Se futuramente habilitar confirmação ou recuperação por e-mail, adicione somente os callbacks efetivamente implementados. O MVP atual tem login por senha, mas não uma tela de recuperação de senha.

## 8. Subir os containers

```bash
cd /opt/apoiarcred/consultas
sudo docker compose config --quiet
sudo docker compose up -d --build
sudo docker compose ps
curl -I http://127.0.0.1:8088/
sudo docker compose logs --tail=50 worker
```

O primeiro build instala Chromium e bibliotecas, podendo levar alguns minutos. O painel deve responder HTTP 200. Use `config --quiet`: o comando sem essa opção pode imprimir os segredos interpolados.

O worker fica sem porta pública. O Compose mantém a porta do painel em loopback. **Não mude PANEL_BIND para 0.0.0.0**: a entrada pública será exclusivamente o Nginx do host. Portas publicadas pelo Docker podem contornar regras do UFW.

## 9. Configurar Nginx para o subdomínio

Esta configuração faz o Nginx do host encaminhar o tráfego para o Nginx do container, em `127.0.0.1:8088`. É intencional: o container serve o painel; o host cuida do domínio e TLS.

Se for usar outro subdomínio, substitua todas as ocorrências abaixo, inclusive no Certbot. Confirme antes que o arquivo escolhido não contém configuração de outro site.

```bash
sudo nano /etc/nginx/sites-available/apoiarcred-consultas
```

Cole:

```nginx
server {
    listen 80;
    server_name consultas.apoiarcred.com.br;

    server_tokens off;
    client_max_body_size 2m;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Cache-Control "no-store" always;

    access_log /var/log/nginx/apoiarcred-consultas.access.log;
    error_log /var/log/nginx/apoiarcred-consultas.error.log;

    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
    }
}
```

Ative uma vez:

```bash
sudo ln -s /etc/nginx/sites-available/apoiarcred-consultas /etc/nginx/sites-enabled/apoiarcred-consultas
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

Se o link já existir, confira o destino e siga sem recriá-lo. Só recarregue após `nginx -t` passar. Não é necessário apagar o site default nem outros virtual hosts.

Teste localmente o virtual host e depois o DNS:

```bash
curl -I -H 'Host: consultas.apoiarcred.com.br' http://127.0.0.1/
dig +short A consultas.apoiarcred.com.br
dig +short AAAA consultas.apoiarcred.com.br
curl -I http://consultas.apoiarcred.com.br/
```

O registro A deve apontar para a VPS. Antes de emitir o certificado, o subdomínio precisa abrir via HTTP na internet. Não faça login nem envie dados reais por HTTP.

## 10. Instalar HTTPS com Certbot

Em VPS nova, sem outra instalação de Certbot:

```bash
sudo snap install --classic certbot
sudo /snap/bin/certbot --nginx -d consultas.apoiarcred.com.br --redirect
```

Informe seu e-mail, leia e aceite os termos se estiver de acordo. O Certbot altera o virtual host para HTTPS e redireciona HTTP. Certbot via Snap gerencia a renovação automática.

```bash
sudo nginx -t
sudo /snap/bin/certbot certificates
sudo /snap/bin/certbot renew --dry-run
sudo snap services certbot
curl -I https://consultas.apoiarcred.com.br/
curl -I http://consultas.apoiarcred.com.br/
```

Esperado: HTTPS com certificado válido; HTTP redirecionando para HTTPS; teste de renovação aprovado. Mantenha 80/443 acessíveis para renovação HTTP. Se houver Cloudflare, mantenha Full (strict) após ativar o proxy. Não ignore erros de certificado.

## 11. Primeiro teste do sistema

1. Abra `https://consultas.apoiarcred.com.br`.
2. Em Configurações, entre com o usuário criado no Supabase Auth.
3. Selecione **Supabase · fila real** e salve.
4. Envie um registro fictício com CPF de 11 dígitos e telefone com DDD.
5. Com worker em `disabled`, o resultado deve ser **Revisão**, dizendo que o robô está desativado. Nenhum atendimento bancário é iniciado nesse modo.
6. Confira o registro no Supabase → Table Editor → consulta_jobs e o lote em consulta_lotes.

O modo Demonstração local é separado, usa valores fictícios e salva histórico apenas no navegador. Ele não comprova a integração com o worker.

A sessão Auth é mantida na aba. O painel consulta os resultados periodicamente e mostra até os 1.000 registros mais recentes do usuário. O arquivo CSV deve ter cabeçalho `nome;cpf;telefone`; preserve CPFs como texto para manter zeros à esquerda. O painel aceita vírgula ou ponto e vírgula, até 1.000 registros e 2 MB.

## 12. Homologar e ativar o primeiro robô

Apenas após o teste da fila, com cliente autorizado para homologação:

```bash
cd /opt/apoiarcred/consultas
nano .env
```

Mude `ROBOT_MODE=disabled` para `ROBOT_MODE=live`, salve e execute:

```bash
sudo docker compose up -d --force-recreate worker
sudo docker compose logs --tail=100 -f worker
```

Ctrl+C encerra somente o acompanhamento dos logs. Faça primeiro uma consulta individual e compare com o atendimento manual. Valide pessoa com contrato, documento não localizado, sessão encerrada, timeout e resposta inesperada antes de subir lotes. O envio do CPF por Enter e o formato final da resposta ainda precisam dessa confirmação real.

| Status | Significado |
|---|---|
| aguardando | Gravado na fila |
| processando | Assumido pelo worker |
| concluida | Saldo e parcelas reconhecidos |
| nao_localizado | Resposta explícita de documento não localizado; não é saldo zero |
| erro | Falha operacional |
| revisao | Robô desativado, validação adicional ou resposta não reconhecida |

Para desativar novas consultas reais, altere para disabled e recrie o worker. Para interromper imediatamente o processo, use `sudo docker compose stop worker`; a tarefa em andamento pode ficar em processando e precisará de revisão.

A fila usa uma função atômica com `FOR UPDATE SKIP LOCKED`, disponível somente para o worker. Uma queda durante a consulta deixa a tarefa em processando; não há recuperação automática sem reconciliação. Verifique o ocorrido antes de reenfileirar. A opção Tentar novamente cria outro registro e preserva o anterior. Não aumente o número de workers antes de medir recursos e validar os limites do chat.

## 13. Atualizar, reiniciar e acompanhar

Atualizar sem trocar de branch:

```bash
cd /opt/apoiarcred/consultas
git status --short
git rev-parse HEAD
```

Anote o commit para eventual retorno. Se houver alterações locais, revise antes de continuar; não use reset destrutivo.

```bash
git pull --ff-only origin apoiarcred-consultas-mvp
sudo docker compose up -d --build
sudo docker compose ps
```

Como `dist` é montado diretamente, mudanças no painel aparecem assim que os arquivos são atualizados; faça atualizações em uma janela adequada. Para mudanças no .env, use `up -d --force-recreate worker`; apenas restart não atualiza variáveis de ambiente.

Comandos úteis, sempre na pasta do projeto:

```bash
sudo docker compose logs --tail=100 worker
sudo docker compose restart painel
sudo docker stats --no-stream
free -h
df -h
sudo systemctl status nginx
sudo tail -n 50 /var/log/nginx/apoiarcred-consultas.error.log
```

O Compose reinicia os containers com `unless-stopped` quando o Docker voltar. Containers parados manualmente precisam ser iniciados manualmente. O banco está no Supabase; não está dentro dos containers da VPS.

## 14. Backup e recuperação

- Código: GitHub, branch indicada neste guia.
- Configuração: guarde cópia criptografada e restrita de `.env`, configurações Nginx e acesso administrativo.
- Dados: configure e teste backups/exportações no Supabase conforme o plano contratado; backup da VPS não substitui backup do Supabase.
- Certificados: ficam em `/etc/letsencrypt`; precisam de permissão restrita. Em outra VPS, você também pode reemitir após ajustar o DNS.
- Antes de migrar ou reinstalar, pare o worker e confira tarefas em andamento para evitar consultas duplicadas.

Para voltar a uma versão do código, confirme que não há alterações locais e use `git switch --detach SHA_DO_COMMIT_ANTERIOR`, depois `sudo docker compose up -d --build`. Isso não desfaz mudanças de banco. Para retomar atualizações: `git switch apoiarcred-consultas-mvp`. Não restaure o banco por cima de resultados novos sem um plano de recuperação.

## 15. Resolver problemas

| Problema | Verificação e correção |
|---|---|
| Permission denied (publickey) | Confira deploy key pública, chave usada no clone e acesso ao repositório privado |
| Painel antigo ou sem arquivos | Confira branch e pasta: main não contém o MVP; confira `dist` e recarregue sem cache |
| Nginx não inicia | Use `sudo nginx -t` e `sudo ss -lntp`; verifique conflito em 80/443 |
| 502 Bad Gateway | Teste `curl -I http://127.0.0.1:8088/` e `sudo docker compose ps`; confirme PANEL_PORT e proxy_pass |
| Subdomínio não abre | Confira A/AAAA, propagação DNS e firewall do provedor e UFW |
| Certbot falha | Confirme HTTP público na porta 80, DNS correto, ausência de AAAA incorreto e eventuais restrições CAA |
| Invalid login credentials | Use conta do Auth deste projeto, confira senha e confirmação do e-mail; não é o login do dashboard Supabase |
| Permission denied na tabela | Confira projeto, grants e RLS; não desabilite RLS para corrigir acesso |
| Fila permanece aguardando | Confira se worker está ativo, chave secreta correta e saída HTTPS disponível |
| Tudo retorna Revisão | Em disabled isso é esperado; em live leia a mensagem do resultado |
| Processando após reinício | Revise consulta interrompida; recuperação automática não está implementada |
| Falha interna no robô | Verifique build do Chromium, conectividade e memória; execute a homologação e revise seletores |
| Página muda ou pede verificação | Pause o lote e revise o conector; não contorne verificações do site |
| Processo morto por memória | Consulte `free -h`, `docker stats` e logs do kernel; mantenha um worker e aumente RAM se necessário |

Nunca exponha chave service_role no navegador ou remova RLS. O HTML do painel é público no subdomínio, mas os dados exigem autenticação e autorização por usuário. O Nginx não substitui essas permissões. Esta versão ainda não oferece painel de gestão de usuários ou compartilhamento de dados entre colaboradores.

## 16. Verificações finais

- [ ] DNS aponta para a VPS e o subdomínio abre com HTTPS válido.
- [ ] HTTP redireciona para HTTPS e renovação em dry-run passa.
- [ ] 8088 está somente em loopback; worker não expõe portas.
- [ ] Login Supabase funciona e registro de teste chega ao banco.
- [ ] Conta de outro usuário não vê as consultas do primeiro.
- [ ] Teste em disabled retorna Revisão, sem iniciar consulta bancária.
- [ ] Consulta real individual foi conferida manualmente antes de lotes.
- [ ] Backups, retenção e acesso à VPS estão definidos.

Testes de código (Python 3 e Node.js no ambiente de desenvolvimento):

```bash
python3 -m unittest discover -s tests -v
node --check dist/app.js
node --check dist/supabase.js
```

## Referências oficiais

- [DNS da Hostinger](https://www.hostinger.com/support/1583249-how-to-manage-dns-records-at-hostinger/)
- [Registros DNS na Cloudflare](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/)
- [DNS no Registro.br](https://registro.br/tecnologia/caracteristicas-tecnicas/)
- [Docker no Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Nginx como proxy reverso](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [Certbot com Nginx via Snap](https://certbot.eff.org/instructions?ws=nginx&os=snap)
- [GitHub: impressões digitais SSH](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
- [Supabase: autenticação por senha](https://supabase.com/docs/guides/auth/passwords)
- [Supabase: RLS](https://supabase.com/docs/guides/database/postgres/row-level-security)
