# Runbook — Deploy da Central

> O `compose.yaml`, o `.env` e os `scripts/` moram na raiz, e `docker compose` acha tudo sozinho.
> A central publica **uma** porta, em `127.0.0.1`, e **nunca** é site público (AD-11).
> **Ingresso remoto decidido em 2026-09-03**: Cloudflare Tunnel + domínio novo, com a stack na máquina
> do escritório. Enquanto o domínio não chega, este runbook cobre o ciclo inteiro em localhost.
> Execução em `docs/runbook-cloudflare.md`.

> **Stories:** 1.1 (stack sobe com um comando) e 1.2 (banco isolado) · **FR-1** · **AD-8, AD-9, AD-10**
> Este runbook é a fonte de verdade operacional do deploy. Arquitetura em `docs/architecture.md`.

## O que sobe

| Serviço | Imagem (tag fixa — FR-2) | Papel | Porta no host |
|---|---|---|---|
| `postgres` | `pgvector/pgvector:0.8.5-pg16` | banco **exclusivo** da central (AD-9) | — |
| `redis` | `redis:7.4.9-alpine` | fila do Sidekiq | — |
| `chatwoot-init` | `chatwoot/chatwoot:v4.15.1-ce` | one-shot: `rails db:chatwoot_prepare` | — |
| `chatwoot-seed` | idem | one-shot: inboxes, locale, atributos, labels, respostas rápidas, `installation_configs`, conta de máquina do espelho | — |
| `chatwoot-web` | idem | UI e API da central | **`127.0.0.1:${CHATWOOT_HOST_PORT}`** |
| `chatwoot-sidekiq` | idem | jobs: webhooks, e-mail, automações | — |

**Só o `chatwoot-web` publica porta, e só em loopback.** Postgres e Redis ficam na rede `internal`
(`internal: true`: fechada, sem egress). Não há como alcançar nada de fora do host (AD-8, AD-10).

### A cadeia de boot, e por que ela é assim

```
postgres + redis (healthy)
  └─▶ chatwoot-init   (rails db:chatwoot_prepare)
        └─▶ chatwoot-seed   (rails runner scripts/seed/chatwoot_seed.rb)
              └─▶ chatwoot-web + chatwoot-sidekiq
```

Cada elo é `service_completed_successfully`, então `docker compose up -d --wait` só volta quando a
central está de fato utilizável.

- **`chatwoot-init`** existe porque o compose oficial do Chatwoot manda rodar
  `rails db:chatwoot_prepare` **à mão** antes do `up` — o que violaria o critério da STORY-1.1 ("um
  comando"). É idempotente: cria o schema num banco novo, migra num existente. É também o passo de
  migração do upgrade (`docker compose run --rm chatwoot-init`).
- **`chatwoot-seed`** deixa a central **pronta para uso**: as duas inboxes, o locale pt_BR, os 8
  atributos de conversa, as 7 labels, as 5 respostas rápidas, a atribuição manual, o white-label, as
  credenciais OAuth e a conta de máquina do espelho. Na instalação nova ainda sincroniza os Content
  Templates da Twilio, uma única vez. Tudo idempotente. Se ele falhar, web e sidekiq **não sobem** —
  e é assim que se quer: um Chatwoot sem as inboxes aceitaria o espelho do monorepo e o jogaria fora,
  em silêncio (AD-12).

---

## Subir

```bash
cp .env.example .env      # e preencha (ver abaixo)
docker compose up -d --wait
bash scripts/verificar-invariantes.sh    # prova: AD-7/8/9/10 não foram violados
```

A UI fica em **http://localhost:3001** (a porta é `CHATWOOT_HOST_PORT`).

## Passos manuais — o que o Claude Code **não** pode fazer por você

### 1. Preencher `.env` (nunca versionado, nunca colado no chat)

```bash
openssl rand -hex 64                                        # → SECRET_KEY_BASE
openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32    # → cada senha
```

Chaves obrigatórias: `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, `POSTGRES_SUPERUSER_PASSWORD`,
`REDIS_PASSWORD` (a **mesma** senha também dentro de `REDIS_URL`). Ambientes diferentes têm segredos
diferentes. Trocar `SECRET_KEY_BASE` depois de subir invalida todas as sessões dos agentes.

**`CENTRAL_ACCESS_TOKEN` você INVENTA, não busca.** É o token com que o espelho do monorepo fala com
a central. Gere um valor, ponha o **mesmo** no `.env` dos dois repos, e o seed o materializa numa
conta de máquina (`espelho@flashcapital.com.br`) no primeiro boot:

```bash
openssl rand -hex 32                                         # → CENTRAL_ACCESS_TOKEN (nos DOIS .env)
```

> Não pegue esse token na UI do Chatwoot. Um token da tela pertence a **uma pessoa**: revogar o
> acesso da máquina derrubaria o acesso dela, e mexer no usuário dela quebraria o espelho em silêncio
> (AD-12 — cada minuto mudo é buraco permanente no painel, não atraso). Foi assim que esta instalação
> nasceu, e o seed avisa quando detecta esse caso.

`bash scripts/verificar-invariantes.sh` compara `.env` e `.env.example` **nos dois sentidos**: chave
a mais ou a menos derruba o check. É de propósito — chave não documentada é chave que ninguém sabe
preencher no próximo ambiente.

### 2. Criar o primeiro admin (uma vez por ambiente)

Signup público está **fechado** (`ENABLE_ACCOUNT_SIGNUP=false`) — a central é interna. O primeiro
administrador nasce na tela de onboarding, que só aparece enquanto não existe nenhuma conta:

**http://localhost:3001/installation/onboarding**

Crie ali a conta da Flash e o seu usuário admin. Os demais agentes entram por convite (STORY-6.1).

> **Por que o seed não faz isso por você.** No Chatwoot, conta e admin nascem **juntos**, pelo
> `AccountBuilder`. Pré-criar a conta no seed faria o onboarding criar uma **segunda** conta — e
> "existe exatamente uma conta" é invariante verificada. Além disso o admin tem senha: é escolha
> humana, não valor de arquivo. O seed detecta a ausência de conta, imprime este passo e sai com 0.
>
> Depois do onboarding: confira que `CENTRAL_ACCOUNT_ID` no `.env` bate com o id da conta criada e
> rode `docker compose up -d` de novo — o seed liga os canais. Deste ponto em diante a stack sobe
> inteira sozinha.

### 3. Ligar os canais

O seed cria as **inboxes** e, na instalação nova, **sincroniza os Content Templates sozinho** (só na
primeira vez, quando o canal ainda não tem template nenhum — um seed de boot não pode depender da
Twilio em toda subida). Sobra um passo, e ele é humano por natureza: o **consent do Google**.

```bash
bash scripts/conectar-gmail.sh --url          # imprime a URL de consent do Google (clique humano)
bash scripts/verificar-canal-oficial.sh
bash scripts/verificar-canal-email.sh
```

O redirect URI do Google precisa estar cadastrado com a porta certa —
`http://localhost:3001/google/callback`. Detalhe em `docs/runbook-canal-email.md`.

⚠️ **Rode o `conectar-gmail.sh`, não clique direto na tela.** As linhas 168-225 dele conferem o
redirect URI **antes** de você queimar o consent. Pela UI você só descobre o `redirect_uri_mismatch`
depois — e ainda ganha uma inbox duplicada, porque o `OauthCallbackController` nomeia a inbox pelo
perfil do Google quando não encontra uma com o e-mail certo.

### 4. SMTP (opcional em dev, necessário em produção)

`SMTP_*` no `.env` é o e-mail **transacional** — convite de agente, reset de senha. Não confundir com
a inbox `E-mail` de atendimento (EPIC-4). Sem SMTP, o convite de agente não sai.

**Configure em produção.** Com SMTP, `criar-agente.sh` deixa de ser necessário: Configurações →
Agentes → Adicionar agente convida por e-mail, e a pessoa escolhe a própria senha. Sem SMTP, o
convite não chega e o agente nasce inutilizável — que é a razão de o script existir.

---

## Instalação numa máquina nova — a sequência inteira

Onde cada passo acontece. Só três exigem uma pessoa, e são os três que não cabem num arquivo:
uma senha, um clique de consentimento e a criação da conta.

| # | Passo | Onde |
|---|---|---|
| 1 | `git clone` e preencher o `.env` (incl. `CENTRAL_ACCESS_TOKEN` inventado) | shell |
| 2 | `docker compose up -d --wait` | shell |
| 3 | o seed não acha conta, imprime o passo 4 e **sai com 0** (não é erro) | automático |
| 4 | criar conta + admin em `/installation/onboarding` | **navegador** |
| 5 | pôr `CENTRAL_ACCOUNT_ID` no `.env` | shell |
| 6 | `docker compose up -d` de novo → o seed monta **tudo**: inboxes, locale, templates, atributos, labels, respostas rápidas, atribuição manual, white-label, conta de máquina do espelho | automático |
| 7 | `bash scripts/conectar-gmail.sh` e clicar no consent | shell + **navegador** |
| 8 | `bash scripts/criar-agente.sh …` (ou o convite pela tela, se houver SMTP) | shell **interativo** |
| 9 | `bash scripts/backfill-email.sh 90` (opcional, uma vez) | shell |
| 10 | instalar as 4 linhas de cron (§ runbook-operacao) | shell |
| 11 | os quatro `verificar-*.sh` verdes | shell |

**Você não precisa abrir um shell NA VPS para isso.** O Compose fala com daemon remoto: exporte o
contexto na sua máquina e os scripts rodam localmente, agindo lá.

```bash
docker context create flash-vps --docker "host=ssh://flash@vps"
docker context use flash-vps
bash scripts/conectar-gmail.sh --status     # script local, exec remoto
```

Vale para tudo que é `docker compose exec`: `conectar-*`, `criar-agente`, os quatro `verificar-*`,
retenção e monitor. **Não vale limpo para `backup.sh`/`restore.sh`**: o `-v ${BACKUP_DIR}:/backup`
resolveria caminho na VPS, não no seu disco — esses dois seguem sendo do cron do host.

`criar-agente.sh` continua exigindo **TTY** (ele lê a senha sem ecoar). `ssh vps "bash scripts/…"`
não tem terminal: a senha sai vazia ou o comando pendura. Use sessão interativa ou `ssh -t`.

---

## Plano B — configurar pela tela, sem script

Para o dia em que um script falhar na VPS e você precisar destravar pela interface. **Não é o
caminho recomendado**: o seed é versionado, idempotente e sempre igual; a tela depende de alguém
lembrar de vinte campos. Três deles falham **em silêncio** quando digitados errado — estão marcados
com ⚠️ abaixo.

| O que | Onde na tela |
|---|---|
| Inbox do WhatsApp | Configurações → Caixas de entrada → Adicionar → **WhatsApp** → provedor **Twilio** |
| ⚠️ nome da inbox | tem de ser **exatamente** `WhatsApp Oficial`. O seed procura por nome: um typo cria inbox duplicada e o espelho do monorepo passa a alimentar a errada |
| ⚠️ tipo do canal | tem de ser **WhatsApp**, não SMS. É o `medium` que liga a janela de 24h; como `sms`, a atendente escreve texto livre depois das 24h e a Meta **rejeita** — sem erro na tela |
| Content Templates | aba **Configuração** da inbox → botão *Sync Templates* (só aparece em canal Twilio + WhatsApp) |
| Inbox de e-mail | Adicionar → **E-mail** → *Continue with Google*. Renomeie para `E-mail` depois: o callback nomeia pelo perfil do Google |
| Credenciais OAuth do Google | `/super_admin/app_config?config=google` → `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` |
| ⚠️ 8 atributos de conversa | Configurações → Atributos personalizados → *Conversa*. Os nomes têm de bater **byte a byte** com `atributos.py::CHAVES` do monorepo: errou um, o valor é gravado e **a barra lateral não mostra nada**, sem erro (AD-13) |
| 7 labels | Configurações → Etiquetas. Marque *mostrar na barra lateral* — o campo é nullable sem default, e sem ele a label existe, é aplicável e **fica invisível** |
| 5 respostas rápidas | Configurações → Respostas rápidas |
| Atribuição automática **desligada** | Configurações da inbox → Colaboradores → toggle |
| Agente | Configurações → Agentes → Adicionar (**exige SMTP**, o convite vai por e-mail) |

### O que NÃO tem tela, em nenhuma versão do CE

- **`INSTALLATION_NAME` / `BRAND_NAME`.** O `SuperAdmin::AppConfigsController` (`allowed_configs`) não
  os expõe em nenhum grupo editável, e a linha nasce no banco valendo `'Chatwoot'` — então nem env var
  resolve, porque o `GlobalConfigService` lê o banco antes do ENV. Só o seed ou um `rails console`.
  Sem isso, a central se apresenta como "Chatwoot" para quem atende e no rodapé do que ela manda.
- **`account.locale`.** Nasce `en`, e é o que o `ApplicationMailer` usa para escolher o idioma de
  **todo e-mail que a central envia** — inclusive a resposta da atendente para o cliente. Nenhuma tela
  do CE oferece a troca.
- **Backfill do histórico da caixa.** O Chatwoot só busca `SINCE (hoje − 1 dia)`; importar o passado é
  `scripts/backfill-email.sh`, sem equivalente na interface.

Por isso o plano B é plano B: pela tela sozinha a instalação **não fecha**.

---

## Operação do dia a dia

| Comando | O quê |
|---|---|
| `docker compose up -d --wait` | sobe tudo e espera ficar saudável |
| `docker compose ps` | estado e health dos containers |
| `docker compose logs -f chatwoot-web` | logs de um serviço |
| `docker compose down` | para a stack (**mantém** os volumes/dados) |
| `docker compose restart` | reinicia (os dados persistem — é o critério da 1.1) |
| `docker compose run --rm chatwoot-seed` | re-semeia canais, locale, configs e a conta de máquina do espelho (idempotente) |
| `bash scripts/verificar-invariantes.sh` | AD-7/8/9/10 não violados |
| `bash scripts/backup.sh` | banco + anexos (STORY-1.4) |

`docker compose down` **não** apaga dados. O que apaga é `docker compose down -v` — nunca rode isso
sem um backup verificado na mão (`bash scripts/restore.sh --verificar`).

> ⚠️ **`smoke-test.sh` semeia e apaga uma conta no banco.** Ele exige o opt-in explícito
> `SMOKE_EU_SEI_O_QUE_ESTOU_FAZENDO=1`, e não deve rodar em paralelo com
> `verificar-invariantes.sh` — enquanto o smoke corre existem **duas** contas, e a invariante exige
> uma.

---

## Antes de expor (Fase 4 — **decidida em 2026-09-03**: Cloudflare Tunnel + domínio novo)

> Esta seção continua sendo a **especificação**. O passo a passo de execução vive em
> `docs/runbook-cloudflare.md`; o porquê e o rastreio, em `docs/fase-4-premissas.md`.

**Nada disto vira código.** O Chatwoot é imagem oficial sem fork (AD-7), e as três primeiras
lacunas abaixo são de coisas que ele não faz — não que ele faça errado. Quem as cobre é o
**ingresso**, seja ele qual for. Esta seção é a especificação que o ingresso escolhido tem de
satisfazer.

O `deploy/ngrok-policy.yml` é a implementação de dev dessa especificação. A sintaxe é do ngrok e
não vai para produção; **as regras vão**.

| # | Requisito | Por que o Chatwoot não resolve | Verificado |
|---|---|---|---|
| 1 | **Só o espelho entra no `/twilio/callback`** — deixou de ser "negar de fora" | O `Twilio::CallbackController` **não valida assinatura nenhuma**. Exposto sem gate, qualquer um forja um inbound na conversa de um cliente. ⚠️ Com o monorepo no Railway, **o relay legítimo passou a vir de fora**: negar incondicionalmente mataria o espelho | ngrok policy → **403** (2026-09-02, quando o relay era interno) · na Fase 4: Access **Service Auth** |
| 2 | **Deixar `/twilio/delivery_status` aberto** | É a própria Twilio que o chama, sem identidade. E o **21609** exige que ele seja alcançável, senão a central não consegue responder | ngrok → 404 (rota existe só em POST) |
| 3 | **Headers de segurança** | O Chatwoot não emite `nosniff`, `Referrer-Policy` nem `X-Frame-Options` | ngrok `add-headers` |
| 4 | **Teto de tamanho de corpo** | O Puma não impõe limite próprio | ⬜ não coberto hoje · vem de graça no plano da Cloudflare |
| 5 | Autenticação e anti-força-bruta | **Isto o Chatwoot JÁ FAZ**: login obrigatório, signup fechado, e o Rack::Attack bloqueia na 6ª tentativa (medido através do túnel: `401 ×5` → `429`) | ✅ nativo |

**O que cada candidato cobre:**

- **Railway sozinho: não basta.** Ele entrega TLS e hostname — é plataforma de execução, não borda.
  Não faz bloqueio por path, não injeta header, não autentica. Os itens 1–4 continuariam abertos.
- **Cloudflare na frente: cobre 1–4.** Access resolve identidade (e é o único jeito de o time de
  atendimento entrar sem expor o login do Chatwoot ao mundo); Custom Rules negam o path; Transform
  Rules injetam os headers. **Confirmar os limites do plano gratuito na hora de decidir** — número
  de regras e de usuários do Access mudam com o tempo, e não vale planejar em cima de memória.
- **Código: nunca.** Fork é proibido (AD-7), e mesmo que não fosse, gate de borda em código de
  aplicação é a duplicação que o AD-10 existe para evitar.

**Duas armadilhas já registradas:**

1. **Access mal configurado devolve a página de login em HTML com status 200** — o
   `raise_for_status()` do espelho passa e ele acha que deu certo. Se a central for para trás do
   Access, o espelho precisa de asserção de `content-type` ou de header `cf-access-*`.
2. **A máquina precisa de uma política própria.** `/twilio/delivery_status` não tem identidade
   humana; no Cloudflare isso é `Bypass` ou **Service Auth** com service token, avaliado ANTES das
   políticas de `Allow`/`Block`.

---

## Diagnóstico

**A UI não responde.** `docker compose logs -f chatwoot-web`. Se o `chatwoot-init` ou o
`chatwoot-seed` falharam, web e sidekiq nem sobem (dependem do sucesso deles):
`docker compose logs chatwoot-init chatwoot-seed`.

**Um container do monorepo não alcança a central.** Confira que os dois estão na `flash-espelho`:
`docker network inspect flash-espelho --format '{{range .Containers}}{{.Name}} {{end}}'` — precisa
listar `fastapi_api` e `inbox-flash-capital-chatwoot-web-1`. **Não tente
`host.docker.internal:3001`**: a porta é um bind de loopback e recusa pacote vindo da bridge do
Docker. Como o espelho falha em silêncio (AD-12), esse erro não aparece nos logs do monorepo — só
some do painel.

**Sidekiq não processa job.** Confira se `REDIS_PASSWORD` e a senha embutida em `REDIS_URL` são a
mesma. Divergiram = o Sidekiq não autentica e a fila para em silêncio.

**A porta 3001 já está em uso.** É disputada com o front de dev do monorepo
(`api/common/origins.py` a lista como origem confiável). Mude `CHATWOOT_HOST_PORT` no `.env`,
atualize a `FRONTEND_URL` junto, e cadastre o novo redirect URI no Google Cloud.
