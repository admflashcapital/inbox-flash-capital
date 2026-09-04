# Inbox Flash Capital

Central de atendimento da **Flash Capital** (FLASH SECURITIZADORA S.A, CNPJ 52.297.978/0001-60).
Consolida numa **única tela** os canais de conversa da Flash — o WhatsApp oficial e a caixa de
e-mail — usando **Chatwoot self-hosted** (Community Edition, imagem oficial, **sem fork**).

O princípio inegociável: **o Chatwoot é espelho e cockpit, não fonte da verdade.** As conversas são
dele; os dados de negócio continuam na plataforma interna (Supabase/monorepo). O contexto chega ao
operador **mastigado** — `titulo_id`, CNPJ, valor e dias de atraso carimbados nos
`custom_attributes` da conversa **no instante do disparo** — sem que a central consulte banco de
domínio nenhum.

## As 2 inboxes do MVP

| Inbox | Número/caixa | Provider | Uso |
|---|---|---|---|
| `WhatsApp Oficial` | número Meta/Twilio | Twilio (roda no monorepo) | cobrança e transacional |
| `E-mail` | caixa Gmail | IMAP/SMTP com OAuth | atendimento por e-mail |

Os nomes são **fixos**: é por eles que o `chatwoot-seed` decide se cria ou reaproveita. Renomear
pela UI faz o seed criar uma inbox duplicada.

**Prospecção fria sai por e-mail, nunca por WhatsApp.** Um número queimado por cold outreach levaria
o canal de cobrança junto — por isso **a central só tem o número oficial**.

## Arquitetura em uma tela

**Hub-and-spoke com enriquecimento unidirecional.** Ninguém alcança a central de fora.

```
   Canais (spokes)                  Central (hub)            Domínio (verdade)
   ┌──────────────┐              ┌────────────────┐        ┌──────────────────┐
   │ Twilio       │              │                │        │ Supabase/monorepo│
   │ (nº oficial) │──┐           │    Chatwoot    │        │ (cedentes,       │
   └──────────────┘  │           │  espelho +     │        │  cobrança)       │
                     │           │    cockpit     │        └────────┬─────────┘
   ┌──────────────┐  │           │                │                 │
   │ Gmail (IMAP) │──┼──polling─▶│  127.0.0.1:3001│◀────────────────┘
   └──────────────┘  │  DE SAÍDA └───────▲────────┘   push do espelho
                     │                   │            (rede flash-espelho,
                     └──▶ MONOREPO ──────┘             2 membros, nada publicado)
                         valida a assinatura
                         e faz o fan-out

              A central NUNCA consulta o domínio. O domínio empurra. ✗───▶
        A Twilio não ENTREGA inbound na central. Entrega no monorepo. ✗───▶
```

- **Hub** — Chatwoot: conversa, contato, labels, atribuição, relatório.
- **Adapters** — Twilio e Gmail. Trocar provider não muda o modelo de conversa.
- **Domínio** — Supabase/monorepo: fonte da verdade. Empurra; nunca é consultado em runtime.

Quem escreve conversa na central são **dois**: o navegador do colaborador (autenticado) e o
monorepo (máquina-a-máquina, pela rede `flash-espelho`). Consequência prática: **domínio fora do ar
não derruba o atendimento** — só deixa o enriquecimento desatualizado.

Há um terceiro toque, e ele é obrigatório: a Twilio chama `/twilio/delivery_status` das mensagens
que a **própria central** envia. Sem alcançá-lo ela recusa o envio com **21609** e a atendente não
consegue responder (AD-11.1). Por isso a central tem uma URL pública (`CENTRAL_URL_PUBLICA`) com o
`/twilio/callback` **negado na borda** — o inbound legítimo nunca passa por ali.

E a recíproca, que é a decisão cara (AD-12): **o espelho não tem retry, fila nem backfill**. Cada
minuto com a central inalcançável é um **buraco permanente** no painel, não um atraso.

> **Este painel é amostral por construção, e é para ficar escrito.** Enquanto a central rodar numa
> máquina sem uptime garantido, "100% das conversas visíveis" (SM-1) é uma meta que a arquitetura
> impede de atingir. Quem ler um relatório daqui precisa saber disso. O teto só sobe quando a Fase 4
> decidir onde a central roda.

**Quem atende, atende por inbox.** O Community Edition tem dois papéis e nada além, e o CPF/CNPJ é
atributo da conversa: **quem abre a conversa vê o documento** (AD-14). O que restringe um agente é a
lista de inboxes de que ele participa — por isso `criar-agente.sh` pede `--inbox`.

Detalhe completo (AD-1..AD-14, diagramas, ERD, convenções) em **`docs/architecture.md`**.

## Subir o ambiente

O compose, o `.env` e os `scripts/` estão na raiz, então `docker compose` acha tudo sozinho — sem
`-f`, sem `--env-file`.

```bash
cp .env.example .env                       # preencha os segredos (nunca commite o .env)
docker compose up -d --wait                # sobe a central inteira e espera ficar saudável
bash scripts/verificar-invariantes.sh      # tag fixa, banco isolado, nada fora de 127.0.0.1
```

A cadeia de boot é: `postgres`+`redis` healthy → **`chatwoot-init`** (migrações) →
**`chatwoot-seed`** (canais e configs, idempotente) → `chatwoot-web` + `chatwoot-sidekiq`.

UI em **http://localhost:3001** (a porta é `CHATWOOT_HOST_PORT`). **Primeiro boot de um ambiente
novo:** o admin nasce em `/installation/onboarding` — conta e admin são criados juntos pelo
Chatwoot, e a senha é escolha humana; o seed detecta e imprime o passo. Deste ponto em diante a
stack sobe inteira sozinha. Signup público fica fechado.

Stack: Chatwoot CE `v4.15.1-ce` (web + Sidekiq) · PostgreSQL 16 + pgvector · Redis 7 · Docker
Compose v2. **Só isso.** Imagem do Chatwoot **sempre com tag fixa** — `latest` é proibido.

| Runbook | Para quê |
|---|---|
| `docs/runbook-deploy.md` | subir em dev; passos manuais (`.env`, 1º admin) |
| `docs/runbook-upgrade.md` | subir de versão do Chatwoot (staging antes de produção) |
| `docs/runbook-backup.md` | backup do par banco+anexos, ensaio de restore, retenção LGPD |
| `docs/runbook-canal-oficial.md` | WhatsApp oficial (Twilio), janela de 24h, templates, espelho |
| `docs/runbook-canal-email.md` | caixa Gmail (OAuth), redirect URI, armadilhas do token |
| `docs/runbook-lgpd.md` | retenção, direito de exclusão do titular, o teto do CE |
| `docs/runbook-operacao.md` | agentes, labels, respostas rápidas, os 4 jobs do host |
| `docs/fase-4-premissas.md` | **previsão** da fronteira pública: decisões tomadas, topologia Railway × escritório, rastreio |
| `docs/runbook-cloudflare.md` | passo a passo da Cloudflare, primeira vez — executar quando o domínio chegar |
| `docs/plano-resiliencia.md` | queda de luz/internet/máquina: o que se perde, o que volta sozinho, o que falta construir |

## Operar

| Comando | O quê |
|---|---|
| `docker compose up -d --wait` · `down` · `ps` · `logs -f <svc>` | ciclo de vida |
| `bash scripts/verificar-invariantes.sh` | invariantes AD-7/8/9/10 — **antes de commitar** |
| `bash scripts/verificar-canal-oficial.sh` · `-canal-email.sh` | invariantes de cada canal |
| `bash scripts/conectar-twilio.sh [--status\|--templates]` | canal oficial |
| `bash scripts/conectar-gmail.sh [--status\|--url]` | canal de e-mail (o consent é clique humano) |
| `bash scripts/backup.sh` · `bash scripts/restore.sh --verificar` | backup e ensaio de restore — **os dois no cron** (05:10 diário / sáb 05:40) |
| `docker compose run --rm chatwoot-seed` | re-semeia canais, locale, atributos, labels, respostas rápidas e a conta de máquina do espelho (idempotente) |
| `bash scripts/verificar-operacao.sh` | invariantes da operação (EPIC-6) |
| `bash scripts/criar-agente.sh --nome N --email E --inbox "E-mail"` · `--listar` | põe alguém para atender |
| `bash scripts/monitorar-canais.sh --simular` | sonda de saúde dos canais (no cron, avisa no sino do Nexus) |
| `bash scripts/retencao-conversas.sh --simular` | expurgo LGPD (simulado) |
| `SMOKE_EU_SEI_O_QUE_ESTOU_FAZENDO=1 bash scripts/smoke-test.sh` | (dev) semeia, reinicia, prova persistência |

## Documentação

| Doc | Para quê |
|---|---|
| `docs/product-brief.md` | Contexto de negócio, problema, usuários, escopo |
| `docs/prd.md` | Requisitos funcionais, glossário fechado, jornadas, NFRs |
| `docs/architecture.md` | Arquitetura: paradigma, decisões (AD-1..AD-13), stack, árvore |
| `docs/epics-and-stories.md` | Epics · stories com critérios de aceite Given/When/Then |
| `CLAUDE.md` | Instruções de desenvolvimento (regra de ouro, convenções, regras invioláveis) |
| `PROGRESS.md` | **Fonte da verdade do estado** — story a story, com gate e dívida técnica |

## Desenvolvimento

**EPIC-1 bloqueia tudo**; os canais podem correr em paralelo depois dele; a Operação (EPIC-6) fecha
o MVP — **e fechou em 2026-09-03**. Não há código de aplicação neste repo — o Chatwoot é imagem oficial sem fork (AD-7). O que
existe é infra, scripts de operação e um seed em Ruby.

Comandos do Claude Code (em `.claude/commands/`):

| Comando | O quê |
|---|---|
| `/status` | épico atual, progresso, próxima story, bloqueadores |
| `/story 4.2` | carrega a story + os ADs dela; define a primeira verificação |
| `/test` | valida compose e roda os `scripts/verificar-*.sh` |
| `/done 4.2` | verifica o verde, atualiza `PROGRESS.md` + docs, commita |
| `/gate EPIC-4` | verifica o gate de saída do épico **com evidência ao vivo** |

O verde de uma story é o **critério de aceite verificado ao vivo** + o artefato versionado + os
verificadores passando. Não force pytest onde não há código.

## Repos irmãos

| Repo | Papel |
|---|---|
| `crm-flash-capital` | comercial: Twenty + N8N. Verdade do **lead**. Independente deste repo: nenhuma rede e nenhum proxy em comum |
| `monorepo-flash-capital` | plataforma interna + app + site + FastAPI/worker + Supabase. Verdade de **cedente/sacado/cobrança**; origina os disparos e os espelha aqui |
| `inbox-flash-capital` (este) | a central. **Espelho e cockpit — dono de nenhum dado de negócio** |
