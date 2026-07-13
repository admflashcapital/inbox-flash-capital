# Inbox Flash Capital

Central de atendimento omnichannel da **Flash Capital** (FLASH SECURITIZADORA S.A, CNPJ
52.297.978/0001-60). Consolida numa **única tela** os canais de conversa da Flash — dois WhatsApps
e uma caixa de e-mail — usando **Chatwoot self-hosted** (Community Edition, imagem oficial, **sem
fork**).

O princípio inegociável: **o Chatwoot é espelho e cockpit, não fonte da verdade.** As conversas são
dele; os dados de negócio continuam no CRM (Twenty) e na plataforma interna (Supabase). O contexto
chega ao operador **mastigado** — labels e atributos empurrados por um Serviço de Sync — sem que a
central consulte banco de domínio nenhum.

> **Status: EPIC-1 concluído (4/19 stories).** A central já sobe com um comando (`make up`), responde
> em HTTPS, tem backup/restore validados e banco isolado. Próxima pendente: **STORY-2.1** (inbox de
> prospecção via Evolution).

## As 3 inboxes do MVP

| Inbox | Número/caixa | Provider | Uso |
|---|---|---|---|
| `WhatsApp Prospecção` | chip novo pré-pago | Evolution API (roda no CRM) | recepciona leads pescados — **só inbound** |
| `WhatsApp Oficial` | número Meta/Twilio | Twilio (roda no monorepo) | cobrança e transacional |
| `E-mail` | caixa Gmail | IMAP/SMTP | atendimento por e-mail |

**Prospecção fria sai por e-mail, nunca por WhatsApp.** A segmentação de risco é de propósito: um
número queimado por cold outreach levaria o canal de cobrança junto.

## Arquitetura em uma tela

**Hub-and-spoke com enriquecimento por eventos unidirecional.**

```
   Canais (spokes)                Central (hub)              Domínio (verdade)
   ┌──────────────┐            ┌────────────────┐         ┌──────────────────┐
   │ Evolution    │──fan-out──▶│                │         │ Twenty CRM       │
   │ (nº prospec) │──fan-out──▶│    Chatwoot    │         │ (leads)          │
   ├──────────────┤            │  espelho +     │         ├──────────────────┤
   │ Twilio       │───────────▶│    cockpit     │         │ Supabase/monorepo│
   │ (nº oficial) │            │                │         │ (cedentes,       │
   ├──────────────┤            │                │         │  cobrança)       │
   │ Gmail (IMAP) │───────────▶│                │         └────────┬─────────┘
   └──────────────┘            └───────▲────────┘                  │
                                       │  labels + atributos       │ eventos
                                 ┌─────┴───────────┐               │
                                 │ Serviço de Sync │◀──────────────┘
                                 │  (FastAPI)      │
                                 └─────────────────┘
              A central NUNCA consulta o domínio. O domínio empurra. ✗───▶
```

- **Hub** — Chatwoot: conversa, contato, labels, atribuição, relatório.
- **Adapters** — Evolution / Twilio / Gmail. Trocar provider não muda o modelo de conversa.
- **Bridge** — **Serviço de Sync** (Python/FastAPI): resolve identidade (**E.164 + documento**) e
  empurra labels/atributos. **Único componente construído do zero.**
- **Domínio** — Twenty e Supabase: fontes da verdade. Emitem eventos; nunca são consultados em runtime.

Consequência prática: **Twenty ou Supabase fora do ar não derruba o atendimento** — só deixa o
enriquecimento desatualizado.

Detalhe completo (AD-1..AD-9, diagramas, ERD, convenções) em **`docs/architecture.md`**.

## Documentação

| Doc | Para quê |
|---|---|
| `docs/product-brief.md` | Contexto de negócio, problema, usuários, escopo |
| `docs/prd.md` | 16 requisitos funcionais, glossário fechado, jornadas, NFRs |
| `docs/architecture.md` | Arquitetura: paradigma, decisões (AD-1..AD-9), stack, árvore-alvo |
| `docs/epics-and-stories.md` | 6 epics · 19 stories com critérios de aceite Given/When/Then |
| `CLAUDE.md` | Instruções de desenvolvimento (regra de ouro, convenções, regras invioláveis) |
| `PROGRESS.md` | Rastreamento das 19 stories + gate de saída por épico |

## Subir o ambiente

```bash
cp deploy/.env.example deploy/.env    # preencha os segredos (nunca commite o .env)
make up        # sobe a central inteira e espera ficar saudável
make check     # invariantes: tag fixa, banco isolado, só o Caddy publica porta
make smoke     # (dev) semeia, reinicia e prova que os dados persistem
```

UI em **https://inbox.\<DOMAIN\>** (dev: `https://inbox.localhost`). O primeiro admin nasce em
`/installation/onboarding` — signup público fica fechado.

Stack: Chatwoot CE `v4.15.1-ce` (web + Sidekiq) · PostgreSQL 16 + pgvector · Redis 7 · Caddy
(auto-HTTPS) · Serviço de Sync (FastAPI, EPIC-5). Imagem do Chatwoot **sempre com tag fixa** —
`latest` é proibido. Passo a passo, DNS e segredos: **`docs/runbook-deploy.md`**.

| Runbook | Para quê |
|---|---|
| `docs/runbook-deploy.md` | subir em dev e em produção; passos manuais (DNS, `.env`, 1º admin) |
| `docs/runbook-upgrade.md` | subir de versão do Chatwoot (staging antes de produção) |
| `docs/runbook-backup.md` | backup do par banco+anexos, ensaio de restore, retenção LGPD |

## Desenvolvimento

Build sequencial por épico. **EPIC-1 bloqueia tudo**; os canais (2/3/4) podem correr em paralelo
depois dele; o Sync (5) precisa de ≥1 canal vivo; a Operação (6) fecha o MVP.

Comandos do Claude Code (em `.claude/commands/`):

| Comando | O quê |
|---|---|
| `/status` | épico atual, progresso, próxima story, bloqueadores |
| `/story 2.1` | carrega a story + os ADs dela; define o primeiro teste/verificação |
| `/test` | pytest + ruff (Sync) e validação do compose/Caddy (infra) |
| `/done 2.1` | verifica o verde, atualiza `PROGRESS.md` + docs, commita |
| `/gate EPIC-1` | verifica o gate de saída do épico **com evidência ao vivo** |

**TDD é obrigatório onde há código** (Serviço de Sync, EPIC-5): `RED → GREEN → REFACTOR → commit`.
Uma story = um commit. Boa parte das stories, porém, é **configuração** — nelas o verde é o critério
de aceite verificado ao vivo + o artefato versionado (`deploy/`, runbook em `docs/`), não uma suíte
de testes inventada.

## Repos irmãos

| Repo | Papel |
|---|---|
| `crm-flash-capital` | comercial: Twenty + N8N + Evolution. Verdade do **lead**; hospeda a instância Evolution que espelha o número de prospecção |
| `monorepo-flash-capital` | plataforma interna + app + site + FastAPI/worker + Supabase. Verdade de **cedente/sacado/cobrança**; origina os disparos |
| `inbox-flash-capital` (este) | a central. **Espelho e cockpit — dono de nenhum dado de negócio** |
