# Runbook — Deploy da Central

> O `compose.yaml`, o `.env` e os `scripts/` moram na raiz, e `docker compose` acha tudo sozinho.
> A central publica **uma** porta, em `127.0.0.1`, e **nunca** é site público (AD-11).
> **Ingresso remoto está em aberto** — decisão de diretoria; até lá este runbook cobre o ciclo
> inteiro em localhost.

> **Stories:** 1.1 (stack sobe com um comando) e 1.2 (banco isolado) · **FR-1** · **AD-8, AD-9, AD-10**
> Este runbook é a fonte de verdade operacional do deploy. Arquitetura em `docs/architecture.md`.

## O que sobe

| Serviço | Imagem (tag fixa — FR-2) | Papel | Porta no host |
|---|---|---|---|
| `postgres` | `pgvector/pgvector:0.8.5-pg16` | banco **exclusivo** da central (AD-9) | — |
| `redis` | `redis:7.4.9-alpine` | fila do Sidekiq | — |
| `chatwoot-init` | `chatwoot/chatwoot:v4.15.1-ce` | one-shot: `rails db:chatwoot_prepare` | — |
| `chatwoot-seed` | idem | one-shot: inboxes + `installation_configs` | — |
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
- **`chatwoot-seed`** cria as duas inboxes e grava as credenciais OAuth. Também idempotente. Se ele
  falhar, web e sidekiq **não sobem** — e é assim que se quer: um Chatwoot sem as inboxes aceitaria o
  espelho do monorepo e o jogaria fora, em silêncio (AD-12).

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

O seed cria as **inboxes**; o que resta é o que depende de terceiro:

```bash
bash scripts/conectar-twilio.sh --templates   # sincroniza os Content Templates (precisa da Twilio no ar)
bash scripts/conectar-gmail.sh --url          # imprime a URL de consent do Google (clique humano)
bash scripts/verificar-canal-oficial.sh
bash scripts/verificar-canal-email.sh
```

O redirect URI do Google precisa estar cadastrado com a porta certa —
`http://localhost:3001/google/callback`. Detalhe em `docs/runbook-canal-email.md`.

### 4. SMTP (opcional em dev, necessário em produção)

`SMTP_*` no `.env` é o e-mail **transacional** — convite de agente, reset de senha. Não confundir com
a inbox `E-mail` de atendimento (EPIC-4). Sem SMTP, o convite de agente não sai.

---

## Operação do dia a dia

| Comando | O quê |
|---|---|
| `docker compose up -d --wait` | sobe tudo e espera ficar saudável |
| `docker compose ps` | estado e health dos containers |
| `docker compose logs -f chatwoot-web` | logs de um serviço |
| `docker compose down` | para a stack (**mantém** os volumes/dados) |
| `docker compose restart` | reinicia (os dados persistem — é o critério da 1.1) |
| `docker compose run --rm chatwoot-seed` | re-semeia canais e configs (idempotente) |
| `bash scripts/verificar-invariantes.sh` | AD-7/8/9/10 não violados |
| `bash scripts/backup.sh` | banco + anexos (STORY-1.4) |

`docker compose down` **não** apaga dados. O que apaga é `docker compose down -v` — nunca rode isso
sem um backup verificado na mão (`bash scripts/restore.sh --verificar`).

> ⚠️ **`smoke-test.sh` semeia e apaga uma conta no banco.** Ele exige o opt-in explícito
> `SMOKE_EU_SEI_O_QUE_ESTOU_FAZENDO=1`, e não deve rodar em paralelo com
> `verificar-invariantes.sh` — enquanto o smoke corre existem **duas** contas, e a invariante exige
> uma.

---

## Antes de expor (Fase 4 — ainda não decidida)

**Nada disto vira código.** O Chatwoot é imagem oficial sem fork (AD-7), e as três primeiras
lacunas abaixo são de coisas que ele não faz — não que ele faça errado. Quem as cobre é o
**ingresso**, seja ele qual for. Esta seção é a especificação que o ingresso escolhido tem de
satisfazer.

O `deploy/ngrok-policy.yml` é a implementação de dev dessa especificação. A sintaxe é do ngrok e
não vai para produção; **as regras vão**.

| # | Requisito | Por que o Chatwoot não resolve | Verificado |
|---|---|---|---|
| 1 | **Negar `/twilio/callback` de fora** | O `Twilio::CallbackController` **não valida assinatura nenhuma**. Exposto sem gate, qualquer um forja um inbound na conversa de um cliente | ngrok policy → **403** (2026-09-02) |
| 2 | **Deixar `/twilio/delivery_status` aberto** | É a própria Twilio que o chama, sem identidade. E o **21609** exige que ele seja alcançável, senão a central não consegue responder | ngrok → 404 (rota existe só em POST) |
| 3 | **Headers de segurança** | O Chatwoot não emite `nosniff`, `Referrer-Policy` nem `X-Frame-Options` | ngrok `add-headers` |
| 4 | **Teto de tamanho de corpo** | O Puma não impõe limite próprio | ⬜ não coberto hoje |
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
