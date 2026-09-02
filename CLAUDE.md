# CLAUDE.md

Guia para o Claude Code (claude.ai/code) trabalhar neste repositório.

> Repo em **português**. Domínio, docs e código usam termos em PT-BR (cedente, sacado, deságio,
> securitizadora). Mantenha o idioma ao escrever docs e mensagens.

---

## Estado atual do repositório (leia primeiro)

> **`PROGRESS.md` é a fonte da verdade do estado.** Esta seção dá o mapa grosso; o rastreamento
> story a story (com hash de commit, gate e dívida técnica) vive lá. Se as duas divergirem,
> **`PROGRESS.md` ganha** — e conserte esta seção.

**A central está no ar.** A stack sobe com `docker compose up -d --wait` (6 serviços, 11 scripts de
operação) e **os dois canais do escopo** estão ligados: WhatsApp Oficial (Twilio) e E-mail (Gmail).
O banco tem **PII real de cliente desde 2026-07-14** — trate backup como segredo.

**Escopo: 16 stories.** Próximo trabalho: **espelho ponta a ponta** (STORY-4.2 — carimbar
`titulo_id`, CNPJ, valor e dias de atraso nos `custom_attributes`, AD-13).

| Épico | Estado |
|---|---|
| **EPIC-1** Fundação | ✅ fechado, gate verificado ao vivo — a stack sobe com `docker compose up -d --wait`, backup/restore validados |
| **EPIC-2** WhatsApp Prospecção | ❌ **CANCELADO** — fora do escopo |
| **EPIC-3** WhatsApp Oficial | ✅ fechado, gate verificado **com o número real de produção** — recebe, responde e espelha os disparos do monorepo sem reenviá-los |
| **EPIC-4** E-mail (Gmail) | ✅ STORY-4.1 fechada e verificada ao vivo; a 4.2 está destravada pelo AD-13 (contexto nos `custom_attributes`) |
| **EPIC-5** Serviço de Sync | ❌ **CANCELADO** (AD-13) — não se constrói serviço de reconciliação |
| **EPIC-6** Operação & Governança | ⬜ não iniciado |

O que **já está decidido e não se re-discute** está em `docs/architecture.md` (AD-1..AD-9) e
condensado em `.claude/memory/decisions.md`.

### Comandos de operação

O compose, o `.env` e os `scripts/` estão na raiz, então `docker compose` acha tudo sozinho — sem
`-f`, sem `--env-file`.

| Comando | O quê |
|---|---|
| `docker compose up -d --wait` · `down` · `ps` · `logs -f <svc>` | ciclo de vida da stack |
| `bash scripts/verificar-invariantes.sh` | invariantes AD-7/8/9/10 — **rode antes de commitar** |
| `bash scripts/verificar-canal-oficial.sh` · `-canal-email.sh` | invariantes de cada canal |
| `SMOKE_EU_SEI_O_QUE_ESTOU_FAZENDO=1 bash scripts/smoke-test.sh` | semeia, reinicia, prova persistência (dev) |
| `bash scripts/backup.sh` · `bash scripts/restore.sh --verificar` | backup do par banco+anexos e ensaio de restore |
| `bash scripts/conectar-twilio.sh [--status\|--templates]` | canal oficial (a inbox já nasce do seed) |
| `bash scripts/conectar-gmail.sh [--status\|--url]` | canal de e-mail — o consent é clique humano |
| `docker compose run --rm chatwoot-init` | migrações do upgrade (one-shot idempotente) |
| `docker compose run --rm chatwoot-seed` | re-semeia canais e configs (idempotente) |
| `bash scripts/retencao-conversas.sh --simular` | expurgo LGPD (simulado) |

A central escuta em **`http://127.0.0.1:${CHATWOOT_HOST_PORT}`** (hoje 3001). O navegador entra por
aí; o monorepo fala com ela pela rede `flash-espelho`, por nome de container.

**E há uma terceira porta de entrada, em dev:** a chave `CENTRAL_URL_PUBLICA` do `.env` recebe um
túnel para a 3001, subido pelo `tuneis-manha.sh` do monorepo. Ela vira o `FRONTEND_URL` do Chatwoot,
e **sem ela a atendente não consegue responder pelo WhatsApp** — a Twilio recusa o envio com 21609
(AD-11.1). O túnel sobe com `deploy/ngrok-policy.yml`, que nega `/twilio/callback` na borda.
`bash scripts/verificar-canal-oficial.sh` cobra as duas coisas ao vivo.

### As-built que vai te morder (aprendido em produção, não re-descubra)

Todas as falhas caras deste projeto foram **silenciosas**. Nenhuma deu erro. Guarde estas:

1. **Bind de loopback não é alcançável de container.** A central publica em `127.0.0.1`, e essa
   porta é do NAVEGADOR. Um container que tente `host.docker.internal:3001` leva conexão recusada:
   pacote de container chega pela bridge (`172.17.0.1`), não pela loopback. É por isso que existe a
   rede `flash-espelho` — e é o tipo de erro que o espelho **não** reporta (AD-12).
2. **O `/twilio/callback` não valida assinatura.** O `Twilio::CallbackController` do Chatwoot não
   confere `X-Twilio-Signature`. Com a central atrás de um túnel a proteção deixou de ser
   topológica: quem barra é a borda (`deploy/ngrok-policy.yml` → 403). **Toda exposição nova tem de
   trazer esse gate junto** — e o `/twilio/delivery_status` tem de ficar aberto, senão volta o 21609.
   A especificação está em `docs/runbook-deploy.md`.
3. **O seed não cria conta nem admin, e isso é deliberado.** No Chatwoot os dois nascem juntos no
   `AccountBuilder` do onboarding; pré-criar a conta faria o onboarding criar uma SEGUNDA — e
   "existe exatamente uma conta" é invariante verificada.
4. **O guard do `source_id` impede cobrança em dobro.** Mensagem `outgoing` empurrada pelo monorepo
   **com** `source_id` o Chatwoot **não reenvia**; sem ele, reenviaria — o cliente seria cobrado
   duas vezes. Nunca empurre outbound espelhado sem `source_id`.
5. **O `.env` não é aparado pelo Docker Compose.** Espaço ou `\r` sobrando num valor vira erro sem
   pista. Os scripts usam `env_get`, que apara; `bash scripts/verificar-invariantes.sh` detecta a sujeira.
6. **Atributo sem definição é invisível.** A barra lateral do Chatwoot **itera as
   `custom_attribute_definitions`**, não as chaves gravadas. O espelho carimba, o Postgres guarda, e
   a tela não mostra nada — sem erro. As 8 definições nascem no `chatwoot_seed.rb` e os mesmos 8
   nomes vivem em `atributos.py::CHAVES` no monorepo (AD-13).

---

## O produto

Central de atendimento omnichannel da **Flash Capital** (FLASH SECURITIZADORA S.A, CNPJ
52.297.978/0001-60), securitizadora de BH que compra títulos de crédito de empresas **cedentes**
com deságio.

O **Inbox Flash Capital** consolida numa única tela os canais de conversa da Flash, usando
**Chatwoot self-hosted** (Community Edition, imagem oficial, sem fork):

| Inbox | Canal | Provider | Uso |
|---|---|---|---|
| `WhatsApp Oficial` | número Meta/Twilio | Twilio (no monorepo) | cobrança e transacional |
| `E-mail` | caixa Gmail | IMAP/SMTP | atendimento por e-mail |

**Volume é pequeno** (5–20 leads/mês no CRM; cobrança na casa das dezenas). Simplicidade >
performance/escala. Não super-engenheirar.

### Os três repos (contexto de máquina)

| Repo | Papel | Relação com este |
|---|---|---|
| `crm-flash-capital` | comercial: leads, docs, análise, contrato mãe. Twenty + N8N | **fonte da verdade de lead**. Sem relação de infra com este repo desde o AD-10 — nenhuma rede, nenhum proxy em comum |
| `monorepo-flash-capital` | plataforma interna, app do cliente, site, FastAPI + worker. Supabase | **fonte da verdade de cedente/sacado/cobrança**; origina os disparos e os espelha na central |
| `inbox-flash-capital` (**este**) | a central (Chatwoot) | **espelho e cockpit** — não é dono de nenhum dado de negócio. Ligado só ao monorepo, pela rede `flash-espelho` |

---

## Onde está a verdade (mapa dos docs)

Antes de implementar qualquer coisa, leia o doc relevante — eles são a fonte de requisitos:

| Doc | Para quê |
|---|---|
| `docs/product-brief.md` | Contexto de negócio, problema, usuários, escopo do MVP |
| `docs/prd.md` | 16 requisitos funcionais (FR-1..16), glossário fechado, jornadas, NFRs, non-goals |
| `docs/architecture.md` | **Arquitetura**: paradigma hub-and-spoke, AD-1..AD-9, diagramas, stack, convenções, árvore-alvo do repo |
| `docs/epics-and-stories.md` | 6 epics · 19 stories (1.1..6.3) com critérios de aceite Given/When/Then |

Não duplique aqui o que esses docs já dizem — vá à fonte.

---

## Arquitetura — o que não pode ser violado

### Regra de ouro (a coisa mais importante do projeto)

**O Chatwoot é ESPELHO e COCKPIT, nunca fonte da verdade de dado de negócio.** (AD-1)

```
❌  editar o CNPJ do cedente só no Chatwoot
❌  Chatwoot consultando o Supabase/Twenty em runtime
✅  monorepo dispara → carimba o contexto nos custom_attributes → espelha no Chatwoot
```

Quebrar isso empobrece o dado relacional do domínio e coloca o canal financeiro (cobrança) refém
da disponibilidade de uma ferramenta de chat.

### As 3 camadas

1. **Hub** (Chatwoot) — modelo de Conversa/Contato, UI de atendimento, labels, atribuição, relatórios.
2. **Adapters** (providers) — Twilio e Gmail. Tradução canal ↔ hub. Trocar provider não muda o
   modelo de conversa.
3. **Domínio** (Supabase/monorepo) — fonte da verdade. Empurra o espelho; **nunca** é consultado em
   runtime pelo hub.

Não há camada de reconciliação (AD-13): o monorepo já conhece `titulo_id`, CNPJ, valor e dias de
atraso **no instante do disparo**, e carimba tudo nos `custom_attributes` da conversa ali mesmo.

O enriquecimento é **unidirecional** (domínio → central). Domínio fora do ar degrada o
enriquecimento, **nunca** o atendimento (AD-2).

### Decisões travadas (não re-discutir — detalhe em `docs/architecture.md`)

- **AD-3** — identidade por **chave dupla**: merge automático só quando telefone (E.164) **E** documento casam; casando só uma chave → **sugestão de merge** para revisão humana.
- **AD-10** — infra é só `docker compose`; nada publica além de `127.0.0.1`, e nunca há proxy compartilhado entre repos.
- **AD-11** — a central **nunca** é site público: a Twilio entrega ao monorepo, o e-mail entra por polling IMAP de saída.
- **AD-12** — o espelho **não tem retry, fila nem backfill**: cada minuto com a central inalcançável é buraco permanente no painel, não atraso.
- **AD-13** — sem Serviço de Sync; o contexto é carimbado no instante do disparo.
- **AD-6** — disparo em massa **origina no monorepo**; a central recebe o outbound por push na API do Chatwoot. A central não é motor de campanha.
- **AD-7** — Community Edition, imagem oficial com **tag fixa**, **sem fork**. Não habilitar a pasta `enterprise/`.
- **AD-9** — Postgres da central **isolado** dos bancos de domínio. Sem cross-DB.

### Stack

Chatwoot CE (tag fixa) · PostgreSQL 16 + pgvector · Redis 7 · Twilio WhatsApp (no monorepo) ·
Gmail IMAP/SMTP com OAuth · Docker Compose v2. **Só isso.**

### Segmentação de risco de número (guardrail de reputação)

Prospecção fria sai por **e-mail**, nunca por WhatsApp: um número queimado por cold outreach levaria
o canal de dinheiro junto. **A central só tem o número oficial**, e ele é exclusivo de cobrança e
transacional.

---

## Workflow de desenvolvimento

Ciclo por story (configurado em `.claude/`):

- **Este repo não tem código de aplicação** — o Chatwoot é imagem oficial sem fork (AD-7). O que
  existe é infra, scripts de operação e o seed em Ruby.
- O "teste" de uma story é o **critério de aceite verificado ao vivo** + o artefato versionado
  (`compose.yaml`, `scripts/`, runbook em `docs/`) + os `scripts/verificar-*.sh` verdes. Não force
  pytest onde não há código.
- Comandos: `/status` (próxima story) · `/story 2.1` (carrega a story + define o 1º teste) · `/test` ·
  `/done 2.1` (verifica, atualiza `PROGRESS.md`, commita) · `/gate EPIC-1` (gate de saída do épico).
- Hooks (`.claude/settings.json` + `.claude/hooks/`): `ruff --fix` em Write/Edit de `.py`;
  `commit-guard.sh` roda gitleaks + pytest antes de `git commit` (degrada com segurança se a
  ferramenta ou os testes ainda não existirem).
- `PROGRESS.md` rastreia as 19 stories por épico (`[ ]` pendente · `[~]` em andamento · `[x]` done ·
  `[!]` bloqueada), com gate de saída por épico.
- Ordem de build: **EPIC-1** (fundação) bloqueia tudo → **EPIC-3/4** (canais, podem correr em
  paralelo) → **EPIC-6** (operação/governança).
- **Skills:** roteador por épico em `.claude/memory/skills.md` (carregado pelo `/story`).

---

## Convenções

- **Bash (scripts de operação):** `set -euo pipefail`, cabeçalho explicando **por que** o script
  existe, e `env_get` de `scripts/lib/env.sh` para ler o `.env` — nunca `source`.
- **Ruby (seed):** só `scripts/seed/chatwoot_seed.rb`, rodado por `rails runner`. Idempotente por
  contrato: rodar de novo não pode duplicar nem sobrescrever.
- **Labels do Chatwoot:** kebab-case, **dicionário fechado** do Glossário do PRD (`lead-frio`,
  `lead-qualificado`, `cliente-ativo`, `em-cobranca`, `regua-etapa-N`, `inadimplente`,
  `nao-identificado`). **Sem sinônimos** — label nova exige atualizar o Glossário.
- **Atributos custom:** snake_case (`cnpj`, `status_operacao`, `dias_atraso`, `valor_em_aberto`,
  `link_twenty`, `link_supabase`, `source_twenty_id`, `source_supabase_id`).
- **Nomes de inbox:** fixos — `WhatsApp Oficial`, `E-mail`. São os nomes que o `chatwoot-seed`
  procura antes de criar: renomear pela UI faz o seed criar uma inbox duplicada.
- **Dados:** telefone sempre **E.164**; documento **só dígitos** para casar; timestamps **UTC**.
- **Env vars:** `.env.example` commitado com todas as chaves (valores vazios); `.env` no
  `.gitignore`, nunca commitado.
- **Git:** conventional commits (`feat(EPIC-N): STORY-X.Y — descrição`). `main` direto (MVP single-dev).

---

## Regras invioláveis (NÃO fazer)

1. **NUNCA** tornar o Chatwoot fonte da verdade de dado de negócio (AD-1). O domínio mora no Twenty/Supabase.
2. **NUNCA** fazer o Chatwoot consultar banco de domínio de forma síncrona no caminho de atendimento (AD-2).
3. **NUNCA** forkar o Chatwoot nem habilitar features da pasta `enterprise/` (AD-7). Extensão só via API/webhook/automação/atributo custom.
4. **NUNCA** usar tag `latest` na imagem do Chatwoot — versão fixada, upgrade validado em staging (FR-2).
5. **NUNCA** disparar prospecção fria em massa por WhatsApp — sai por e-mail. O número oficial é exclusivo de cobrança e transacional.
6. **NUNCA** originar disparo em massa dentro da central (AD-6) — o motor é o monorepo.
7. **NUNCA** criar label fora do dicionário fechado do Glossário, nem merge automático de contato sem casar telefone **E** documento (AD-3).
8. **NUNCA** commitar `.env`/segredos/credenciais; todo webhook valida origem (assinatura Twilio, token compartilhado nos demais) e todo tráfego externo é TLS (AD-8).
9. **NUNCA expor o VALOR de um segredo no chat/terminal.** É **proibido** rodar `Read`/`cat`/`echo`/`grep`/`sed` que imprima o conteúdo de `.env` ou de qualquer arquivo com credencial (API key, token, senha, `*.key`, `*.pem`, JSON de service account). Mesmo o transcript local conta como vazamento — uma chave exibida é uma **chave comprometida** (= rotação + retrabalho). Para mexer em `.env`: edite **às cegas** com `Edit` (casando por nome de chave, sem ler o valor) ou só **mascarado** (`${#VAR}` / `${VAR:0:8}…`). Para checar presença de uma chave, teste existência (`grep -q`), nunca imprima o valor. Na dúvida, **pergunte** antes.
