# Runbook — Canal E-mail (Gmail Workspace via OAuth)

**Épico:** EPIC-4 · **Stories:** 4.1 (inbox espelhada) e 4.2 (unificação de contato)
**FRs:** FR-9, FR-10 · **Comandos:** `bash scripts/conectar-gmail.sh` · `bash scripts/conectar-gmail.sh --status` · `bash scripts/conectar-gmail.sh --url` · `bash scripts/verificar-canal-email.sh`

A caixa Gmail de atendimento entra na central como a inbox `E-mail`. O Chatwoot **recebe** por IMAP
(`imap.gmail.com`) e **responde** por SMTP (`smtp.gmail.com:587`), os dois autenticando com **XOAUTH2**
— o mesmo token.

---

## ⚠️ Service account NÃO serve aqui (decidido, não re-discutir)

Se você tem uma service account com acesso à API do Gmail: **ela não pluga no Chatwoot.** Não é
preferência, é ausência de caminho de código.

| O que o Chatwoot faz | Onde |
|---|---|
| autentica IMAP com `XOAUTH2` pegando o token do refresher | `Imap::GoogleFetchEmailService` |
| renova com `grant_type=refresh_token` | `Google::RefreshOauthTokenService` |
| **falha explicitamente sem refresh token** | `BaseRefreshOauthTokenService#refresh_tokens` → `raise 'A refresh_token is not available' if provider_config[:refresh_token].blank?` |

Uma service account usa o grant **JWT-bearer** (domain-wide delegation) e **nunca emite
`refresh_token`**. Não existe campo onde pôr o JSON da SA. Injetar um access token de SA à força no
`provider_config` faria o canal funcionar por **1 hora** e depois morrer **dentro de um job do
Sidekiq**, sem erro na tela — exatamente o padrão de falha silenciosa que já custou caro neste projeto.

A SA continua útil para o domínio (EPIC-5, automações). Só não para este plugue.

---

## Passo 1 — Google Cloud (manual, uma vez)

Pode ser no **mesmo projeto** onde a service account já vive.

1. **Tela de consentimento OAuth** → tipo **Internal**.
   Por ser Workspace, "Internal" significa que o escopo restrito `https://mail.google.com/`
   **não passa por revisão do Google**. (Se fosse "External", precisaria de verificação — semanas.)
2. **Credentials → Create credentials → OAuth client ID** → tipo **Web application**.
3. **Authorized redirect URIs** → adicione exatamente:

   | Ambiente | Redirect URI |
   |---|---|
   | **dev** | `http://localhost:3001/google/callback` (a `CHATWOOT_HOST_PORT`) |
   | com ingresso | `https://<host-publico>/google/callback` |

   Pode registrar **os dois** no mesmo client — o Google aceita vários. E deixe o antigo
   `http://localhost:3000/google/callback` cadastrado: não custa nada e cobre quem ainda tiver
   um `.env` com a porta velha.

   > **Por que `http://localhost:3001` e não `https://inbox.localhost`:** as regras de validação do
   > Google exigem HTTPS **exceto para `localhost`**, que é isento. Mas a isenção vale para o
   > `localhost` **puro** — `inbox.localhost` é um **subdomínio** e é recusado. Como a central agora
   > publica direto em loopback, o `localhost` puro é o endereço real dela, e não mais um artifício.
4. Guarde o **Client ID** e o **Client secret**.

> **Escopo:** o Chatwoot pede `email profile https://mail.google.com/` (`GoogleConcern#scope`) —
> leitura **e** envio na caixa inteira. Não é ajustável sem forkar (proibido, AD-7).

---

## Passo 2 — Preencher o `.env` (manual)

No `.env` (nunca commitado, nunca ecoado):

| Chave | Valor |
|---|---|
| `GMAIL_CAIXA_ATENDIMENTO` | o endereço da caixa (ex.: `atendimento@flashcapital.com.br`) |
| `GOOGLE_OAUTH_CLIENT_ID` | do Passo 1 |
| `GOOGLE_OAUTH_CLIENT_SECRET` | do Passo 1 — **trate como senha** |

As três chaves `ACTIVE_RECORD_ENCRYPTION_*` já foram geradas. **Guarde-as junto do
`SECRET_KEY_BASE`** — perdê-las significa não conseguir mais decifrar o que já foi gravado.

Depois de editar, recarregue o ambiente dos containers:

```bash
docker compose up -d --wait      # o compose lê o .env via env_file; sem restart, as chaves novas não chegam
```

---

## Passo 3 — Criar a inbox

```bash
bash scripts/conectar-gmail.sh
```

Cria a inbox `E-mail` (`Channel::Email`) com o endereço da caixa e devolve a **URL de autorização**.

> **Por que pré-criamos a inbox:** deixado por conta própria, o `OauthCallbackController` criaria a
> inbox nomeada com o **perfil do Google** (`users_data['name']`), violando o nome fixo `E-mail` do
> glossário do PRD. Pré-criada com o endereço certo, o callback a **encontra**
> (`find_channel_by_email`) e só anexa os tokens.

---
## Passo 4 — Autorizar

Abra a URL devolvida, **logado na caixa de atendimento**, e conceda o acesso. O Google redireciona
para `<FRONTEND_URL>/google/callback`, o Chatwoot troca o `code` por tokens e grava tudo.

> ⏱️ O `state` da URL é um sgid assinado que **expira em 15 minutos**. Demorou? gere outra com
> `bash scripts/conectar-gmail.sh --url`.

### O redirect precisa estar cadastrado no Google Cloud

O redirect do OAuth é seguido pelo **seu navegador**, não pelo servidor do Google: ele só precisa ser
alcançável **da sua máquina**. A central nunca precisa estar exposta na internet para isto (AD-11).

O Google exige HTTPS **exceto para `localhost`**, que é isento — mas a isenção vale para o `localhost`
**puro**: `inbox.localhost` é subdomínio e é recusado.

| Ambiente | Authorized redirect URI |
|---|---|
| dev | `http://localhost:3001/google/callback` (= `CHATWOOT_HOST_PORT`) |
| com ingresso | `https://<host-publico>/google/callback` |

**Trocou `CHATWOOT_HOST_PORT`? Cadastre a porta nova antes de mexer na `FRONTEND_URL`** — senão o
consent falha com `redirect_uri_mismatch`.

---

## Passo 5 — Verificar

```bash
bash scripts/verificar-canal-email.sh          # invariantes do canal
bash scripts/conectar-gmail.sh --status   # o que está valendo (nunca imprime token)
```

O `bash scripts/verificar-canal-email.sh` recusa as três formas de o canal falhar **calado**:

| Invariante | Por que existe |
|---|---|
| `provider = google` | a inbox pode existir com OAuth pela metade: aparece na UI e **nunca busca e-mail** |
| `refresh_token` gravado | sem ele o canal vive **1h** e morre dentro de um job, sem erro na tela |
| job `trigger_imap_email_inboxes_job` registrado | é ele que busca o e-mail **e** mantém o token fresco (veja a armadilha abaixo) |
| zero campanhas na inbox | AD-6 — o motor de disparo é o monorepo |

---

## Armadilhas as-built (aprendidas lendo o código, não a documentação)

### 1. Agendador parado ⇒ a atendente também para de RESPONDER

O SMTP de saída autentica com o **access token cru**:

```ruby
# ConversationReplyMailerHelper#base_smtp_settings
password: @channel.provider_config['access_token']   # sem passar pelo refresh!
```

Quem mantém esse token fresco é o **job IMAP que roda a cada minuto** — ele chama o refresher, que
grava o token novo de volta no canal. Consequência não óbvia: **se o Sidekiq/agendador parar, em até
1 hora o envio quebra junto com o recebimento**, com falha de autenticação SMTP dentro de um job.

Sintoma: a atendente responde, a mensagem fica na conversa, e o cliente nunca recebe.
Diagnóstico: `bash scripts/verificar-canal-email.sh` (item do agendador) e `docker compose logs -f chatwoot-sidekiq`.

### 2. Re-autorizar sem revogar não devolve `refresh_token`

O Google só emite `refresh_token` com `access_type=offline` **e** `prompt=consent` (o Chatwoot manda
os dois). Mas se o consentimento **já foi dado antes**, uma nova autorização costuma voltar **sem**
`refresh_token` — e aí o canal nasce condenado a morrer em 1h.

**Antes de re-autorizar**, revogue o acesso em <https://myaccount.google.com/permissions>.

### 3. O `refresh_token` fica em texto puro no banco

O `Channel::Email` criptografa **só** `imap_password` e `smtp_password`. Com OAuth, a credencial real
vive no `provider_config` — **jsonb, e o Chatwoot não o criptografa**, mesmo com as chaves
`ACTIVE_RECORD_ENCRYPTION_*` ligadas.

Esse token dá **leitura e envio na caixa inteira** e **não expira**. Ele está no Postgres e dentro de
**todo backup** que o `bash scripts/backup.sh` gera. Corrigir exigiria forkar o Chatwoot (proibido, AD-7).

**Mitigação:** tratar o `BACKUP_DIR` como segredo (já é a política) e **revogar** o token em
<https://myaccount.google.com/permissions> ao menor sinal de vazamento. Registrado na dívida técnica.

### 4. A env var do OAuth sozinha NÃO basta — o controller lê o BANCO

O `omniauth.rb` lê `ENV['GOOGLE_OAUTH_CLIENT_ID']`. Mas quem monta a URL de consentimento e troca o
`code` **não é o omniauth** — é o `Api::V1::Accounts::Google::AuthorizationsController`, e ele lê:

```ruby
client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)   # tabela installation_configs
```

O `GlobalConfigService.load` até *tenta* cair para o ENV, mas tem um furo:

```ruby
config = GlobalConfig.get(k)[k]
return config if config.present?                                  # linha existe, VAZIA → segue
config_value = ENV.fetch(k) { default_value }                      # pega do ENV… ok
i = InstallationConfig.where(name: k).first_or_create(value: config_value, locked: false)
return i.value                                                    # ← ACHA a linha vazia, devolve VAZIO
```

E o `config/installation_config.yml` do Chatwoot **semeia** `GOOGLE_OAUTH_CLIENT_ID` com valor vazio
no deploy. Logo o `first_or_create` **encontra** a linha, não cria nada, não atualiza nada — e o ENV
é ignorado **para sempre**.

**Sintoma:** a URL de consentimento sai com `client_id` **em branco** (`...&client_id&prompt=consent`)
e o Google responde um erro genérico. Nada no `.env` está errado, e você caça fantasma por horas.

**Solução (já automatizada):** o `bash scripts/conectar-gmail.sh` grava os dois valores no `installation_configs` e limpa
o cache do `GlobalConfig`. O `bash scripts/verificar-canal-email.sh` **reprova** se eles estiverem vazios lá.

### 5. A busca IMAP tolera queda, mas só por ~24h

`Imap::BaseFetchEmailService#since` busca `SINCE (hoje − 1 dia)` e deduplica por `message_id`
(`email_already_present?`). Traduzindo: o Sidekiq pode ficar fora do ar por horas sem perder e-mail —
mas **acima de ~24h, o que chegou no buraco não é mais buscado**. Teto de 500 mensagens por sync.

---

## Gate do EPIC-4 — checklist

| Critério | Como provar |
|---|---|
| e-mail que chega vira conversa na inbox `E-mail` | mande um e-mail para a caixa; espere ≤1 min; a conversa aparece |
| resposta pela central volta ao remetente **na mesma thread** | responda pela central; confira no cliente de e-mail que caiu **na thread**, não numa nova |
| e-mail e WhatsApp do mesmo cliente sob o **mesmo Contato** | **STORY-4.2 — depende do EPIC-5** (ver abaixo) |

O threading da resposta é **nativo**: o mailer monta `In-Reply-To` e `References` a partir do
`message_id` da última mensagem recebida (`ConversationReplyMailerHelper`), e o `Reply-To` aponta
para a própria caixa. Nada foi construído para isso.

---

## O que a STORY-4.2 ainda NÃO fecha (e por quê)

A unificação de e-mail + WhatsApp sob um único Contato exige a resolução de identidade por
**telefone E documento** (AD-3) — que, por decisão de arquitetura, vive **num lugar só**: o Serviço
de Sync (EPIC-5), que ainda não existe.

O que o Chatwoot faz **sozinho** hoje: se um contato já tem o `email` preenchido e chega um e-mail
daquele endereço, ele **casa no mesmo Contato** (busca por e-mail dentro da conta). O que ele **não**
faz: descobrir que `+5531988887777` e `fulano@empresa.com.br` são a mesma pessoa. Isso é o EPIC-5.

Por isso o gate do EPIC-4 **só fecha junto com o EPIC-5** — está assim no `docs/epics-and-stories.md`
desde o planejamento ("depende de Epic 5"), não é desvio.

---

## Diagnóstico

| Sintoma | Causa provável |
|---|---|
| a URL de consentimento sai com **`client_id` vazio** (`...&client_id&prompt=`) | a env var não chegou ao `installation_configs` (armadilha 4) → `bash scripts/conectar-gmail.sh` grava e limpa o cache |
| `redirect_uri_mismatch` no Google | a `FRONTEND_URL` do `.env` não bate com o Authorized redirect URI registrado. Lembre do `/google/callback` no fim, e de `docker compose up -d --wait` depois de mudar |
| `Invalid or expired state` | o sgid expirou (15 min). `bash scripts/conectar-gmail.sh --url` |
| inbox existe mas nunca chega e-mail | OAuth pela metade (`provider` vazio) ou agendador morto → `bash scripts/verificar-canal-email.sh` diz qual |
| chegou e-mail, mas a resposta não sai | token vencido porque o agendador parou (armadilha 1) → `docker compose logs -f chatwoot-sidekiq` |
| canal funcionou 1h e parou | nasceu **sem `refresh_token`** (armadilha 2) → revogue em myaccount.google.com/permissions e re-autorize |
| resposta cria thread nova no cliente | o `In-Reply-To` não foi montado — a conversa não tem mensagem inbound com `message_id` (ex.: conversa criada à mão) |
