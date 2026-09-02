# CLAUDE.md

Guia para o Claude Code (claude.ai/code) trabalhar neste repositório.

> Repo em **português**. Domínio, docs e código usam termos em PT-BR (cedente, sacado, deságio,
> securitizadora). Mantenha o idioma ao escrever docs e mensagens.

---

## ⚠️ REESCOPO 2026-09-02 — leia ANTES de tudo

O projeto foi retomado com uma simplificação. **Boa parte do que este arquivo descreve abaixo continua
verdadeira como as-built, mas a direção mudou.** Se algo aqui conflitar com esta seção, esta seção ganha.

| Cancelado / mudado | Onde está a decisão |
|---|---|
| **EPIC-2 (Evolution) cancelado** — sai dos dois repos | AD-11 · `crm/docs/07_Decisoes.md` ADR-010 |
| **EPIC-5 (Serviço de Sync) cancelado** — `sync-service/` **não será construído** | **AD-13** |
| **STORY-4.2 destravada** — o contexto vai nos `custom_attributes` no instante do disparo | **AD-13** |
| **Caddy, Makefile, `/etc/hosts` e a rede `flash-canais` saem** — só `docker compose`, tudo em loopback | **AD-10** |
| **A central nunca é site público** — a Twilio fala com o monorepo; o e-mail é polling IMAP | **AD-11** |
| **O painel é amostral** enquanto o uptime não for garantido — o espelho não tem retry | **AD-12** |

**Escopo vigente: 16 stories** (19 − 3 do EPIC-2). **Próximo trabalho: Fase 0 (backup) → Fase 1.**

**Onde ler:** `docs/architecture.md` (AD-10..AD-13) · `HANDOFF-espelho-chatwoot.md` em `~/projects/` ·
`docs/0014-atendimento-no-monorepo-corte-chatwoot.md` (ADR arquivado: a direção rejeitada, com medição).

**Enquanto a Fase 1 não roda, os comandos `make …` e o Caddy continuam funcionando** — os docs de
runbook estão marcados com o que muda e em qual fase. Não "adiante" a limpeza fora da ordem das fases:
a Fase 2.1 do CRM (consertar os testes) precede qualquer remoção de arquivo lá.

---

## Estado atual do repositório (leia primeiro)

> **`PROGRESS.md` é a fonte da verdade do estado.** Esta seção dá o mapa grosso; o rastreamento
> story a story (com hash de commit, gate e dívida técnica) vive lá. Se as duas divergirem,
> **`PROGRESS.md` ganha** — e conserte esta seção.

**A central está no ar** (embora a stack esteja **desligada** no momento — os volumes persistem, com PII
real desde 2026-07-14). `deploy/` existe (6 containers, 12 scripts de operação) e **os dois canais do
escopo vigente** estão ligados: WhatsApp Oficial (Twilio) e E-mail (Gmail). O `sync-service/` **não
existe e não será construído** — o EPIC-5 foi cancelado (AD-13).

| Épico | Estado |
|---|---|
| **EPIC-1** Fundação | ✅ fechado, gate verificado ao vivo — a stack sobe com `make up`, backup/restore validados |
| **EPIC-2** WhatsApp Prospecção | 🟡 pronto até onde é automatizável — as stories 2.1/2.2 esperam o **pareamento do chip físico** (passo manual, `docs/runbook-canal-prospeccao.md`) |
| **EPIC-3** WhatsApp Oficial | ✅ fechado, gate verificado **com o número real de produção** — recebe, responde e espelha os disparos do monorepo sem reenviá-los |
| **EPIC-4** E-mail (Gmail) | ⬜ próximo — nada feito |
| **EPIC-5** Serviço de Sync | ⬜ não iniciado — `sync-service/` ainda não existe |
| **EPIC-6** Operação & Governança | ⬜ não iniciado |

O que **já está decidido e não se re-discute** está em `docs/architecture.md` (AD-1..AD-9) e
condensado em `.claude/memory/decisions.md`.

### Comandos de operação (`make help` lista todos)

| Alvo | O quê |
|---|---|
| `make up` · `down` · `ps` · `logs s=<svc>` | ciclo de vida da stack |
| `make check` | invariantes AD-7/8/9 — **rode antes de commitar** |
| `make smoke` | semeia, reinicia, prova a persistência (dev) |
| `make backup` · `restore-check` | backup do par banco+anexos e ensaio de restore |
| `make evolution` · `evolution-status` · `fanout` · `dedup` · `aquecimento` | canal de prospecção |
| `make twilio` · `twilio-status` · `oficial` | canal oficial |
| `make gmail` · `gmail-status` · `gmail-url` · `email` | canal de e-mail (Gmail/OAuth) |
| `make migrate` · `retencao` | migrações do upgrade · expurgo LGPD (simulado) |

### As-built que vai te morder (aprendido em produção, não re-descubra)

Todas as falhas caras deste projeto foram **silenciosas**. Nenhuma deu erro. Guarde estas:

1. **`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` é obrigatório.** O anti-SSRF do Chatwoot (`SafeFetch`)
   recusa webhook e download de mídia de host sem IP público — e a Evolution vive em rede privada.
   Sem o flag, a resposta da atendente falha **em silêncio**. Está registrado como dívida técnica.
2. **Um host = um Caddy.** Central e CRM não podem ambos publicar 80/443. O Caddy da central é
   perfil `edge` (default em dev/staging); com as duas stacks no mesmo host, o Caddy do CRM serve o
   vhost `inbox.<DOMAIN>`.
3. **O Caddy 2.11 descarta header com underscore** — e o Chatwoot autentica com `api_access_token`.
   Há uma ponte hífen→underscore no Caddyfile. Mexer nela = **401 com token válido**.
4. **O guard do `source_id` impede cobrança em dobro.** Mensagem `outgoing` empurrada pelo monorepo
   **com** `source_id` o Chatwoot **não reenvia**; sem ele, reenviaria — o cliente seria cobrado
   duas vezes. Nunca empurre outbound espelhado sem `source_id`.
5. **O `.env` não é aparado pelo Docker Compose.** Espaço ou `\r` sobrando num valor vira erro sem
   pista. Os scripts usam `env_get`, que apara; `make check` detecta a sujeira.

---

## O produto

Central de atendimento omnichannel da **Flash Capital** (FLASH SECURITIZADORA S.A, CNPJ
52.297.978/0001-60), securitizadora de BH que compra títulos de crédito de empresas **cedentes**
com deságio.

O **Inbox Flash Capital** consolida numa única tela os canais de conversa da Flash, usando
**Chatwoot self-hosted** (Community Edition, imagem oficial, sem fork):

| Inbox | Canal | Provider | Uso |
|---|---|---|---|
| `WhatsApp Prospecção` | número novo pré-pago | Evolution API (no CRM) | recepciona leads pescados — **só inbound** |
| `WhatsApp Oficial` | número Meta/Twilio | Twilio (no monorepo) | cobrança e transacional |
| `E-mail` | caixa Gmail | IMAP/SMTP | atendimento por e-mail |

**Volume é pequeno** (5–20 leads/mês no CRM; cobrança na casa das dezenas). Simplicidade >
performance/escala. Não super-engenheirar.

### Os três repos (contexto de máquina)

| Repo | Papel | Relação com este |
|---|---|---|
| `crm-flash-capital` | comercial: leads, docs, análise, contrato mãe. Twenty + N8N + Evolution | **fonte da verdade de lead**; hospeda a instância Evolution que espelha o número de prospecção |
| `monorepo-flash-capital` | plataforma interna, app do cliente, site, FastAPI + worker. Supabase | **fonte da verdade de cedente/sacado/cobrança**; origina os disparos e os espelha na central |
| `inbox-flash-capital` (**este**) | a central (Chatwoot) + o Serviço de Sync | **espelho e cockpit** — não é dono de nenhum dado de negócio |

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
✅  Twenty/Supabase → evento → Serviço de Sync → push de label/atributo → Chatwoot
```

Quebrar isso empobrece o dado relacional do domínio e coloca o canal financeiro (cobrança) refém
da disponibilidade de uma ferramenta de chat.

### As 4 camadas

1. **Hub** (Chatwoot) — modelo de Conversa/Contato, UI de atendimento, labels, atribuição, relatórios.
2. **Adapters** (providers) — Evolution, Twilio, Gmail. Tradução canal ↔ hub. Trocar provider não muda o modelo de conversa.
3. **Bridge** (Serviço de Sync) — resolução de identidade + push de labels/atributos. **Único componente construído do zero** e único dono da lógica de reconciliação.
4. **Domínio** (Twenty, Supabase/monorepo) — fontes da verdade. Emitem eventos; **nunca** são consultados em runtime pelo hub.

O enriquecimento é **unidirecional e assíncrono** (domínio → central). Domínio fora do ar degrada o
enriquecimento, **nunca** o atendimento (AD-2).

### Decisões travadas (não re-discutir — detalhe em `docs/architecture.md`)

- **AD-3** — identidade por **chave dupla**: merge automático só quando telefone (E.164) **E** documento casam; casando só uma chave → **sugestão de merge** para revisão humana.
- **AD-5** — a instância Evolution fica **no CRM** e faz **fan-out** (N8N **e** Chatwoot recebem cada mensagem). Não é fila competida. At-least-once, consumidores idempotentes.
- **AD-6** — disparo em massa **origina no monorepo**; a central recebe o outbound por push na API do Chatwoot. A central não é motor de campanha.
- **AD-7** — Community Edition, imagem oficial com **tag fixa**, **sem fork**. Não habilitar a pasta `enterprise/`.
- **AD-9** — Postgres da central **isolado** dos bancos de domínio. Sem cross-DB.

### Stack

Chatwoot CE (tag fixa) · PostgreSQL 16 + pgvector · Redis 7 · Caddy 2 (TLS) · Evolution API v2.3.7
(existente no CRM) · Twilio WhatsApp (existente no monorepo) · Serviço de Sync em **Python 3.12 +
FastAPI + httpx** (alinhado ao monorepo) · Docker Compose v2.

### Segmentação de risco de número (guardrail de reputação)

Prospecção fria sai por **e-mail**, nunca por WhatsApp. O número de prospecção opera **só inbound**
(recepciona o lead pescado e manda o link do Jotform). O número oficial (cobrança) fica isolado da
atividade de risco — um número queimado não pode levar o canal de dinheiro junto.

---

## Workflow de desenvolvimento

Ciclo por story (configurado em `.claude/`):

- **TDD onde há código** (Serviço de Sync): `RED → GREEN → REFACTOR → commit`. Uma story = um commit.
- Boa parte das stories é **configuração/infra** (subir container, conectar inbox, configurar label).
  Nessas, o "teste" é o **critério de aceite verificado ao vivo** + o artefato versionado
  (`docker-compose.yml`, `Caddyfile`, runbook em `docs/`). Não force pytest onde não há código.
- Comandos: `/status` (próxima story) · `/story 2.1` (carrega a story + define o 1º teste) · `/test` ·
  `/done 2.1` (verifica, atualiza `PROGRESS.md`, commita) · `/gate EPIC-1` (gate de saída do épico).
- Hooks (`.claude/settings.json` + `.claude/hooks/`): `ruff --fix` em Write/Edit de `.py`;
  `commit-guard.sh` roda gitleaks + pytest antes de `git commit` (degrada com segurança se a
  ferramenta ou os testes ainda não existirem).
- `PROGRESS.md` rastreia as 19 stories por épico (`[ ]` pendente · `[~]` em andamento · `[x]` done ·
  `[!]` bloqueada), com gate de saída por épico.
- Ordem de build: **EPIC-1** (fundação) bloqueia tudo → **EPIC-2/3/4** (canais, podem correr em
  paralelo) → **EPIC-5** (sync, precisa de ≥1 canal vivo) → **EPIC-6** (operação/governança).
- **Skills:** roteador por épico em `.claude/memory/skills.md` (carregado pelo `/story`).

---

## Convenções

- **Python (Serviço de Sync):** `ruff format`/`ruff check --fix`, type hints e docstrings Google em
  função pública. Testes em `pytest` (+ `httpx` para simular webhooks, mocks para APIs externas).
- **Labels do Chatwoot:** kebab-case, **dicionário fechado** do Glossário do PRD (`lead-frio`,
  `lead-qualificado`, `cliente-ativo`, `em-cobranca`, `regua-etapa-N`, `inadimplente`,
  `nao-identificado`). **Sem sinônimos** — label nova exige atualizar o Glossário.
- **Atributos custom:** snake_case (`cnpj`, `status_operacao`, `dias_atraso`, `valor_em_aberto`,
  `link_twenty`, `link_supabase`, `source_twenty_id`, `source_supabase_id`).
- **Nomes de inbox:** fixos — `WhatsApp Prospecção`, `WhatsApp Oficial`, `E-mail`.
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
5. **NUNCA** disparar prospecção fria em massa pelo número de WhatsApp — sai por e-mail. O número de prospecção é **só inbound**.
6. **NUNCA** originar disparo em massa dentro da central (AD-6) — o motor é o monorepo.
7. **NUNCA** criar label fora do dicionário fechado do Glossário, nem merge automático de contato sem casar telefone **E** documento (AD-3).
8. **NUNCA** commitar `.env`/segredos/credenciais; todo webhook valida origem (assinatura Twilio, token compartilhado nos demais) e todo tráfego externo é TLS (AD-8).
9. **NUNCA expor o VALOR de um segredo no chat/terminal.** É **proibido** rodar `Read`/`cat`/`echo`/`grep`/`sed` que imprima o conteúdo de `.env` ou de qualquer arquivo com credencial (API key, token, senha, `*.key`, `*.pem`, JSON de service account). Mesmo o transcript local conta como vazamento — uma chave exibida é uma **chave comprometida** (= rotação + retrabalho). Para mexer em `.env`: edite **às cegas** com `Edit` (casando por nome de chave, sem ler o valor) ou só **mascarado** (`${#VAR}` / `${VAR:0:8}…`). Para checar presença de uma chave, teste existência (`grep -q`), nunca imprima o valor. Na dúvida, **pergunte** antes.
