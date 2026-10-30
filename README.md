# ApoiarCred · Instalação automática do MVP

VPS **Ubuntu Server 24.04 x86-64**, com **2 vCPU e 4 GB RAM**. Sem Docker e sem instalar Git.

## 1. DNS

Crie este registro antes de instalar:

| Tipo | Nome | Valor |
|---|---|---|
| **A** | **consultas** | **IP público da VPS** |

Isso cria `consultas.apoiarcred.com.br`. É A, não CNAME, porque o destino é um IP. Se usar outro nome, informe esse endereço ao instalador. Se usar Cloudflare, deixe Somente DNS inicialmente. As portas 80 e 443 precisam estar livres e liberadas no firewall do provedor.

## 2. Baixar e executar

No [repositório, branch do MVP](https://github.com/lcstrindadebr/Promp-01-teste-/tree/apoiarcred-consultas-mvp), clique em **Code → Download ZIP**. Renomeie para `apoiarcred.zip`.

Como o repositório é privado, baixe conectado à sua conta. Envie o ZIP para a VPS por SFTP ou pelo PowerShell, na pasta onde baixou:

```powershell
scp apoiarcred.zip root@IP_DA_VPS:/tmp/apoiarcred.zip
ssh root@IP_DA_VPS
```

Na VPS, como root:

```bash
apt update && apt install -y unzip
unzip /tmp/apoiarcred.zip -d /tmp/apoiarcred-instalacao
cd /tmp/apoiarcred-instalacao/Promp-01-teste--apoiarcred-consultas-mvp
bash instalar.sh
```

Se o nome da pasta extraída for diferente, entre na pasta que contém `instalar.sh`.

O instalador pergunta:

1. Subdomínio, por exemplo `consultas.apoiarcred.com.br`.
2. E-mail para o certificado SSL.
3. Chave secret/service_role do **projeto Supabase deste MVP**. A digitação fica oculta.
4. Confirmação para iniciar e aceitar os termos do certificado Let's Encrypt.

A chave está no Supabase → Project Settings → API Keys. Não é a chave publishable. Ela é necessária para o robô acessar a fila e fica somente na VPS, em `.env` protegido.

O instalador configura Python, Chromium, Nginx, HTTPS com renovação automática e serviço do robô que inicia com a VPS. O painel abre no subdomínio informado. Se o DNS não chegar à VPS ou outra aplicação ocupar as portas, ele para com a orientação do erro. Depois de corrigir, execute `bash instalar.sh` novamente.

**Use em VPS nova ou com Nginx sem conflito nesse subdomínio.** O instalador não substitui Traefik/Apache. Ao executar novamente, ele para o worker durante a atualização e redefine o modo para disabled. Se houver falha, pode ser necessário reiniciar o worker depois da correção. Backups locais ficam em `/var/tmp/apoiarcred-install.*`, restritos a root; podem conter configuração secreta anterior.

## 3. Primeiro acesso

Crie seu usuário em Supabase → Authentication → Users, com e-mail e senha definidos por você. O projeto e suas tabelas já estão configurados; não reaplique o SQL.

Abra o subdomínio → **Configurações** → entre com esse usuário → selecione **Supabase · fila real**.

O robô inicia em **disabled**: os registros retornam Revisão, sem consulta bancária. A execução completa do robô Digi+ ainda precisa de homologação na VPS. Para uma consulta real autorizada de teste:

```bash
nano /opt/apoiarcred/.env
# Troque ROBOT_MODE=disabled por ROBOT_MODE=live, salve e execute:
systemctl restart apoiarcred-robo
```

Confira uma consulta individual antes de enviar lotes. CSV: `nome;cpf;telefone`, até 1.000 linhas. Cada usuário vê apenas suas próprias consultas.

## Comandos úteis

```bash
# Logs (Ctrl+C fecha apenas o acompanhamento)
journalctl -u apoiarcred-robo -n 50 -f

# Reiniciar ou parar
systemctl restart apoiarcred-robo
systemctl stop apoiarcred-robo

# Testar renovação do certificado
certbot renew --dry-run
```

Se a VPS interromper uma consulta, ela pode ficar processando e precisa de revisão antes de reenviar. O banco fica no Supabase: configure os backups e a retenção dos dados nele.

Instalação automática preparada e verificada com testes simulados; instalação real e emissão do certificado dependem da sua VPS e do DNS.
