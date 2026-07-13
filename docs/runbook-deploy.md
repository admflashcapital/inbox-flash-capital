# Runbook — Deploy da Central

> **Stories:** 1.1 (stack sobe com um comando) e 1.2 (banco isolado) · **FR-1** · **AD-8, AD-9**
> Este runbook é a fonte de verdade operacional do deploy. Arquitetura em `docs/architecture.md`.

## O que sobe

| Serviço | Imagem (tag fixa — FR-2) | Papel | Porta no host |
|---|---|---|---|
| `caddy` | `caddy:2.11.4` | TLS + única porta de entrada | **80, 443** |
| `chatwoot-web` | `chatwoot/chatwoot:v4.15.1-ce` | UI e API da central | — (rede interna) |
| `chatwoot-sidekiq` | idem | jobs: webhooks, e-mail, automações | — |
| `chatwoot-init` | idem | one-shot: `rails db:chatwoot_prepare` | — |
| `postgres` | `pgvector/pgvector:0.8.5-pg16` | banco **exclusivo** da central (AD-9) | — |
| `redis` | `redis:7.4.9-alpine` | fila do Sidekiq | — |

**Só o Caddy publica porta.** Postgres, Redis e o Rails ficam na rede Docker interna — não há como
alcançá-los de fora do host (AD-8). A rede `internal` é `internal: true`: fechada, sem egress.

### Por que existe o `chatwoot-init`

O compose oficial do Chatwoot manda rodar `rails db:chatwoot_prepare` **à mão** antes do `up`. Isso
violaria o critério da STORY-1.1 ("um comando"). Aqui ele virou um serviço one-shot de que `web` e
`sidekiq` dependem (`service_completed_successfully`). É idempotente: cria o schema num banco novo,
aplica migrações num banco existente. É também o passo de migração do upgrade (`make migrate`).

---

## Subir em desenvolvimento (localhost)

```bash
cp deploy/.env.example deploy/.env      # e preencha (ver abaixo)
make up                                 # docker compose up -d --wait
make smoke                              # prova: dados sobrevivem ao restart
make check                              # prova: AD-7/8/9 não foram violados
```

A UI fica em **https://inbox.localhost** — cert da CA interna do Caddy (o navegador vai avisar que é
self-signed; é o esperado em dev).

## Passos manuais — o que o Claude Code **não** pode fazer por você

### 1. Preencher `deploy/.env` (nunca versionado, nunca colado no chat)

```bash
openssl rand -hex 64                              # → SECRET_KEY_BASE
openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32   # → cada senha
```

Chaves obrigatórias: `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, `POSTGRES_SUPERUSER_PASSWORD`,
`REDIS_PASSWORD` (a **mesma** senha também dentro de `REDIS_URL`), `DOMAIN`, `ADMIN_EMAIL`.
Staging e produção têm segredos **diferentes**. Trocar `SECRET_KEY_BASE` depois de subir invalida
todas as sessões dos agentes.

### 2. DNS (só produção)

Aponte um registro **A/AAAA de `inbox.<DOMAIN>`** para o IP do host **antes** de subir com
`DOMAIN=flashcapital.com.br`. O Caddy pede o certificado ao Let's Encrypt no primeiro boot; sem DNS
resolvendo, o desafio ACME falha e a UI não sobe em HTTPS.

Libere 80 e 443 no firewall — o Let's Encrypt precisa da 80 para o desafio HTTP.

### 3. Criar o primeiro admin

Signup público está **fechado** (`ENABLE_ACCOUNT_SIGNUP=false`) — a central é interna. O primeiro
administrador nasce na tela de onboarding da instalação, que só aparece enquanto não existe nenhuma
conta:

**https://inbox.\<DOMAIN\>/installation/onboarding**

Crie ali a conta da Flash e o seu usuário admin. Os demais agentes entram por convite (STORY-6.1).

### 4. SMTP (opcional em dev, necessário em produção)

`SMTP_*` no `.env` é o e-mail **transacional** — convite de agente, reset de senha. Não confundir com
a inbox `E-mail` de atendimento (EPIC-4). Sem SMTP, o convite de agente não sai.

---

## Produção

```bash
# no host de produção, com DOMAIN=flashcapital.com.br e DNS já apontando
make up
make check                       # invariantes de arquitetura
curl -sI https://inbox.flashcapital.com.br/app/login   # 200/302 + cert válido
```

Depois: configure o cron de backup (`docs/runbook-backup.md`) — a central passa a acumular PII já no
primeiro dia de atendimento.

> ⚠️ **Não rode `make smoke` em produção.** Ele semeia dados de teste; o script aborta sozinho se
> `DOMAIN` não for `localhost`.

---

## Operação do dia a dia

| Comando | O quê |
|---|---|
| `make up` | sobe tudo e espera ficar saudável |
| `make ps` | estado e health dos containers |
| `make logs s=chatwoot-web` | logs de um serviço |
| `make down` | para a stack (**mantém** os volumes/dados) |
| `make restart` | reinicia (os dados persistem — é o critério da 1.1) |
| `make check` | AD-7/8/9 não violados |
| `make backup` | banco + anexos (STORY-1.4) |

`make down` **não** apaga dados. O que apaga é `docker compose down -v` — nunca rode isso em
produção sem um backup verificado na mão.

---

## Diagnóstico

**A UI não responde / 502 no Caddy.** `make logs s=chatwoot-web`. Se o `chatwoot-init` falhou, web e
sidekiq nem sobem (dependem do sucesso dele): `docker compose -f deploy/docker-compose.yml logs chatwoot-init`.

**Cert inválido em produção.** Quase sempre é DNS: o `inbox.<DOMAIN>` precisa resolver para o host
**antes** do primeiro boot. Confira `make logs s=caddy` — o erro do ACME é explícito. Cuidado com o
rate limit do Let's Encrypt (5 falhas/hora): corrija o DNS antes de ficar reiniciando.

**Sidekiq não processa job.** Confira se `REDIS_PASSWORD` e a senha embutida em `REDIS_URL` são a
mesma. Divergiram = o Sidekiq não autentica e a fila para em silêncio.
