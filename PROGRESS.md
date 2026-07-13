# Inbox Flash Capital — Progress Tracker

> Para iniciar sessão: "Leia o CLAUDE.md e o PROGRESS.md, continue da próxima story pendente."
> Atualizado pelo Claude Code via `/done`. Detalhe de cada story em `docs/epics-and-stories.md`.

**Legenda:** `[ ]` pendente · `[~]` em andamento · `[x]` concluída · `[!]` bloqueada

**Milestones:** M1 = EPIC-1 · M2 = EPIC-2 + 3 + 4 (canais) · M3 = EPIC-5 (sync) · M4 = EPIC-6 (go-live).
O EPIC-1 bloqueia tudo. Os EPICs 2/3/4 podem correr em paralelo depois dele. O EPIC-5 precisa de ≥1 canal vivo.
Cada épico tem um gate de saída — use `/gate EPIC-N`.

**Progresso total:** 4 / 19 stories. **M1 (EPIC-1) concluído** — a central está no ar em dev.

---

## EPIC-1 — Fundação da Plataforma

Chatwoot self-hosted na infra da Flash: deploy reproduzível, banco isolado, versão fixada, backup validado.

| # | Story | Status | Commit |
|---|---|---|---|
| 1.1 | Stack Docker da central sobe com um comando (FR-1) | [x] | |
| 1.2 | Banco da central isolado dos bancos de domínio (FR-1, AD-9) | [x] | |
| 1.3 | Versão fixada e procedimento de upgrade (FR-2) | [x] | |
| 1.4 | Backup e restore validados (FR-3) | [x] | |

**Gate EPIC-1:** `docker compose up -d` sobe web + Sidekiq + Postgres/pgvector + Redis + Caddy; UI do Chatwoot responde em HTTPS com cert válido; dados persistem após restart; imagem com **tag fixa** (nunca `latest`); Postgres próprio, sem credencial cruzada com Twenty/Supabase; restore de backup recompõe conversas e anexos num ambiente limpo.

**Gate verificado ao vivo em 2026-07-13 (dev):** `make up` sobe os 6 containers healthy com um
comando · `https://inbox.localhost` responde (HTTP→HTTPS 308; cert da CA interna em dev — o cert
público do Let's Encrypt depende do **DNS de produção**, ver abaixo) · `make smoke` prova que
conversa, mensagem e anexo sobrevivem ao restart · `make check` valida tag fixa `-ce`, banco próprio
sem credencial cruzada, usuário não-superusuário, sem dblink/fdw, só o Caddy publicando porta ·
`make backup` + `make restore-check` recompõem banco **e** anexos num ambiente limpo.

**Pendências de produção (passo manual do operador — `docs/runbook-deploy.md`):** apontar o DNS de
`inbox.<DOMAIN>` para o host antes do 1º boot (sem isso o Let's Encrypt não emite cert), preencher o
`.env` de produção com segredos próprios, criar o admin em `/installation/onboarding`, configurar o
SMTP transacional e agendar o cron de backup + cópia offsite criptografada.

---

## EPIC-2 — Canal WhatsApp Prospecção (Evolution)

Número novo pré-pago, **só inbound**, convivendo com o Agente N8N sem perda de mensagem.

| # | Story | Status | Commit |
|---|---|---|---|
| 2.1 | Inbox de prospecção espelhada no Chatwoot (FR-4) | [~] | 4bbccb5 |
| 2.2 | Convivência com o Agente N8N sem perda — fan-out (FR-5, AD-5) | [~] | |
| 2.3 | Aquecimento e proteção do número (FR-6) | [x] | |

> **O EPIC-2 está pronto até onde é automatizável.** As stories 2.1 e 2.2 só viram `[x]` depois de
> **parear o chip** e provar o gate com uma mensagem real — o checklist está em
> `docs/runbook-canal-prospeccao.md` (§ Checklist para fechar o gate do EPIC-2). Antes disso é
> preciso **decidir quem responde o lead** (Agente ou humano), senão o lead recebe resposta dupla.

**STORY-2.2 — fan-out verificado na configuração e no código (2026-07-13, dev).** `make fanout`
prova que os dois consumidores estão vivos na mesma instância (webhook global → N8N **e** integração
Chatwoot aplicada). No código da Evolution 2.3.7: os dois disparos acontecem no mesmo handler de
mensagem (`chatwootService.eventWhatsapp` na linha 1331, `sendDataWebhook` na 1483) e o envio à
central tem `try/catch` próprio (linha 2525) — **não é fila competida, e central fora do ar não cega
o Agente**. A saudação do Agente aparece na central porque mensagem `fromMe` também é espelhada
(vira `outgoing`).
**Idempotência:** o dedup nativo da Evolution só roda com o import por Postgres direto (que
desligamos por AD-8/AD-9) e o Chatwoot não tem índice único em `source_id` — duplicata é possível no
replay do Baileys. Resolvido do lado da central por `dedup-mensagens.sh` (testado: 2 cópias → 1).
**Perda:** com a central fora do ar, o espelho perde as mensagens daquele intervalo (o N8N não). É
assimetria proposital; sem reenvio automático no MVP.

**STORY-2.3 — política do número, com guardrail executável.** `make aquecimento` **falha** se alguma
conversa da inbox de prospecção tiver sido **iniciada por nós** (assinatura de outbound frio), se
existir **campanha** na inbox (AD-6) ou se o volume enviado em 24h passar do teto da rampa
(20/40/60/80/100 por semana). Política e playbook de bloqueio em `docs/runbook-aquecimento-numero.md`.

**STORY-2.1 — integração ligada e verificada até onde dá sem o chip (2026-07-13, dev).**
Verificado ao vivo: rede `flash-canais` liga Evolution 2.3.7 ↔ Chatwoot 4.15.1 sem expor nenhuma das
duas; `make evolution` criou a inbox `WhatsApp Prospecção` (`Channel::Api`, webhook
`/chatwoot/webhook/crm`); a resposta digitada na central **chega** na Evolution; e a Evolution
**escreve de volta** na conversa usando o token de admin. **Falta o passo manual do operador:** parear
o chip pré-pago pelo QR (`docs/runbook-canal-prospeccao.md`) — só então dá para provar os CAs
(mensagem real do lead, resposta chegando no WhatsApp, mídia anexada). A story só vira `[x]` depois
disso.

**Dois achados que mudaram o desenho:**
1. **`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` é obrigatório na central.** O Chatwoot recusa webhook e
   download de mídia em host sem IP público (anti-SSRF do `SafeFetch`), e a Evolution vive em rede
   privada. Sem o flag, a resposta do atendente falha em silêncio (`failed` + `has no public ip
   addresses`). Alternativa seria expor a Evolution na internet — pior.
2. **Um host = um Caddy.** Central e CRM não podem ambos publicar 80/443. O Caddy da central virou
   perfil `edge` (default em dev/staging); com as duas stacks no mesmo host, o Caddy do CRM serve o
   vhost `inbox.<DOMAIN>` pela rede compartilhada.

**Gate EPIC-2:** mensagem inbound no número novo aparece na inbox `WhatsApp Prospecção`; resposta pela central chega ao lead; mídia é anexada; **N8N e Chatwoot recebem cada evento** (fan-out at-least-once, sem mensagem engolida nem duplicada); a saudação + link Jotform do agente aparecem na conversa; limite de aquecimento documentado e zero outbound frio em massa.

> ⚠️ **Risco de engenharia do épico:** a instância Evolution tem **dois consumidores** (N8N + Chatwoot). Se virar fila competida, um engole o evento do outro. Fan-out é requisito, não detalhe.

---

## EPIC-3 — Canal WhatsApp Oficial (Twilio/Meta)

Número oficial como inbox de cobrança/transacional + espelho dos disparos originados no monorepo.

| # | Story | Status | Commit |
|---|---|---|---|
| 3.1 | Inbox oficial espelhada (FR-7) | [ ] | |
| 3.2 | Espelho dos disparos em massa — push do monorepo (FR-8, AD-6) | [ ] | |

**Gate EPIC-3:** mensagem ao número oficial cai na inbox `WhatsApp Oficial`; resposta dentro da janela de 24h sai pelo canal oficial e fora dela usa **template Meta aprovado**; disparo de cobrança do pipeline do monorepo aparece como outbound na conversa correta (push na API do Chatwoot); a resposta do cliente cai na **mesma thread**; a central **não origina** disparo em massa.

---

## EPIC-4 — Canal E-mail (Gmail)

Caixa Gmail de atendimento como inbox, com as threads unificadas ao mesmo contato dos WhatsApps.

| # | Story | Status | Commit |
|---|---|---|---|
| 4.1 | Inbox de e-mail espelhada (FR-9) | [ ] | |
| 4.2 | Unificação sob o mesmo contato (FR-10) | [ ] | |

**Gate EPIC-4:** e-mail que chega na caixa vira conversa na inbox `E-mail`; resposta pela central volta ao remetente na mesma thread; conversas de e-mail e de WhatsApp do mesmo cliente aparecem sob o **mesmo Contato** quando e-mail/documento casam, sem duplicidade (fecha junto com o EPIC-5).

---

## EPIC-5 — Serviço de Sync (Enriquecimento de Contato)

A Ponte: identidade por telefone+documento e push unidirecional de labels e atributos.
**Único componente construído do zero** — aqui TDD é obrigatório.

| # | Story | Status | Commit |
|---|---|---|---|
| 5.1 | Resolução de identidade por telefone + documento (FR-11) | [ ] | |
| 5.2 | Regra de merge — automático vs. sugestão (FR-10, FR-11, AD-3) | [ ] | |
| 5.3 | Push de labels de segmento/estado (FR-12) | [ ] | |
| 5.4 | Push de atributos de domínio (FR-13) | [ ] | |
| 5.5 | Desacoplamento e degradação graciosa (FR-14, AD-2) | [ ] | |

**Gate EPIC-5:** contato reconhecido vira **um único** Contato no Chatwoot com `source_twenty_id`/`source_supabase_id`; desconhecido recebe a label `nao-identificado`; merge automático **só** com telefone **E** documento casando, senão **sugestão `pending`** sem alterar o contato; labels do **dicionário fechado** aplicadas na transição de estado; atributos (`cnpj`, `status_operacao`, `dias_atraso`, `valor_em_aberto`, `link_twenty`, `link_supabase`) visíveis na barra lateral com link abrindo o registro-fonte; **com Twenty/Supabase fora do ar o atendimento continua funcionando** (só o enriquecimento atrasa); push idempotente com retry e backoff; **zero chamada síncrona central→domínio**.

---

## EPIC-6 — Operação de Atendimento & Governança

Cockpit, papéis, atribuição, labels manuais, respostas rápidas, LGPD e observabilidade.

| # | Story | Status | Commit |
|---|---|---|---|
| 6.1 | Cockpit unificado e papéis de agente (FR-15) | [ ] | |
| 6.2 | Atribuição, labels manuais e respostas rápidas (FR-16) | [ ] | |
| 6.3 | Observabilidade e conformidade LGPD | [ ] | |

**Gate EPIC-6:** as 3 inboxes visíveis numa interface única; papéis (admin/agente) negam acesso indevido; atribuição manual e automática por inbox funcionando; respostas rápidas inseridas; labels manuais aplicáveis além das empurradas pelo Sync; log estruturado + alerta de saúde da conexão Evolution; retenção de conversas configurada e acesso a CPF/CNPJ restrito por papel.

---

## Dívida técnica conhecida

Nada ainda — implementação não iniciada. Itens levantados em code-review e desvios as-built entram aqui.

| Item | Risco | Alvo |
|---|---|---|
| **Dupla resposta no número de prospecção.** O `WF-04-004` (N8N) responde automaticamente toda mensagem inbound com o LLM. Se a atendente também responder pela central, o lead recebe **duas respostas** — o robô e a humana. Não é bug da integração: são dois cérebros no mesmo número. Até haver handoff, ou a central fica só observando, ou o Agente fica desligado. **Não pôr os dois com tráfego real.** | lead recebe resposta duplicada/contraditória | STORY-2.2 |
| **Espelho pode duplicar e pode perder.** Duplicar: o dedup nativo da Evolution depende do import por Postgres direto (desligado por AD-8/AD-9) e o Chatwoot não tem índice único em `source_id` — o replay do Baileys reinsere. Mitigado *a posteriori* por `dedup-mensagens.sh` (precisa estar no cron). Perder: central fora do ar = mensagens só no N8N e no WhatsApp, sem reenvio automático. | espelho incompleto/duplicado (não afeta o Agente nem o lead) | reenvio vira trabalho do Serviço de Sync se doer (EPIC-5) |
| **Anti-SSRF do Chatwoot desligado para rede privada** (`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`). Necessário para falar com a Evolution e baixar mídia; em troca, um webhook malicioso configurado na central poderia alcançar serviço interno. Mitigação atual: só admin configura webhook, e a rede `flash-canais` tem apenas Evolution, Chatwoot e o Caddy. | SSRF a partir da central | revisar no EPIC-6 (governança) |
| **Retenção de conversa sem aval jurídico.** `RETENCAO_CONVERSAS_DIAS=1825` (5 anos) é um default técnico, não uma decisão. A central guarda conversa de **cobrança**: apagar cedo destrói prova de negociação de dívida; tarde demais viola a LGPD. O expurgo existe (`retencao-conversas.sh`) mas **não está no cron**. | LGPD / prova em disputa de dívida | STORY-6.3 |
| **Cópia offsite do backup é manual.** O `backup.sh` grava só local; host morre = backup morre junto. A cópia criptografada para fora do host está documentada, não automatizada. | perda total em falha de host | antes do go-live |
| **Staging não existe ainda.** O runbook de upgrade exige validar em staging antes de produção (FR-2); hoje só há o ambiente dev local. | upgrade sem rede de proteção | antes do 1º upgrade em prod |

### Adiado para a fase 2 (registrado em `docs/architecture.md` §Deferred)

| Item | Por quê ficou fora do MVP |
|---|---|
| **Instância B** — número de relacionamento (clientes que já operam) no Evolution | mesmo padrão do canal de prospecção, sem agente; baixo esforço — revisar se o cronograma permitir |
| **Dashboard App (iframe)** com dado de domínio ao vivo | o MVP usa só atributos empurrados; mantém a central leve (AD-2) |
| **Sync bidirecional** (central → domínio) | MVP é unidirecional |
| **Campanhas/disparo em massa na central** | permanece no monorepo (AD-6) |
| **SSO / embed na plataforma interna** | fase 2 |
| **Novos canais** (Instagram, webchat, Telegram) | o padrão de adapter (AD-4) já os acomoda |

---

## Registro de sessões

| Data | Épico | Stories | Notas |
|---|---|---|---|
| 2026-07-13 | — | planejamento | Documentação BMAD gerada em `docs/`: `product-brief.md` (fase 1), `prd.md` (16 FRs, glossário fechado, jornadas), `architecture.md` (spine hub-and-spoke, AD-1..AD-9, diagramas, árvore-alvo), `epics-and-stories.md` (6 epics · 19 stories com CA Given/When/Then). Decisões travadas: Evolution fica no CRM com fan-out; merge só com telefone **E** documento; disparo em massa origina no monorepo. |
| 2026-07-13 | — | setup | Scaffold do repo: `.claude/` (hooks, 5 comandos, 4 memories), `PROGRESS.md`, `CLAUDE.md`, `README.md`, `.gitignore`. 11 skills instaladas em `.claude/skills/` (incl. as oficiais `chatwoot-cli` e `twilio/ai`). Nenhum código de runtime. |
| 2026-07-13 | EPIC-1 | 1.1 · 1.2 · 1.3 · 1.4 | **A central subiu.** `deploy/` criado: compose (Caddy 2.11.4 · Chatwoot `v4.15.1-ce` web+sidekiq+init · pgvector 0.8.5-pg16 · Redis 7.4.9), `Caddyfile`, `.env.example`, init-db e 5 scripts de operação; `Makefile` com `up/check/smoke/backup/restore-check/retencao`; runbooks de deploy, upgrade e backup. Decisões as-built: **`chatwoot-init` one-shot** (`db:chatwoot_prepare` via `service_completed_successfully`) para o `up` ser mesmo **um** comando — o compose oficial exige migração à mão; **extensões pré-criadas pelo superusuário** no init-db (o `pg_stat_statements` não é *trusted*, e o usuário da app é não-superusuário por AD-9); **`APP_DB_*`** no init para desfazer a colisão de `POSTGRES_PASSWORD` (superusuário na imagem do Postgres vs. usuário da app no Chatwoot). Gate do épico verificado ao vivo em dev. |

| 2026-07-13 | EPIC-2 | 2.1 · 2.2 · 2.3 | **Canal de prospecção ligado.** A instância `crm` (Evolution, no CRM) passou a ter **dois consumidores**: o Agente N8N (webhook global) e a central (integração nativa Chatwoot). A inbox `WhatsApp Prospecção` é criada pela própria Evolution (`autoCreate`). Ponte por rede Docker externa `flash-canais` — nada exposto na internet. Novos comandos: `make evolution`, `make fanout`, `make dedup`, `make aquecimento`. Runbooks de canal e de aquecimento. **Achados que mudaram o desenho:** (1) o Chatwoot recusa webhook/mídia em host sem IP público (anti-SSRF do `SafeFetch`) → `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`, senão o canal falha **em silêncio**; (2) um host só tem uma porta 443 → o Caddy da central virou perfil `edge` e, no host compartilhado, o Caddy do CRM serve `inbox.<DOMAIN>`; (3) o dedup nativo da Evolution depende do import por Postgres direto (proibido por AD-9) → faxineiro `dedup-mensagens.sh` na central. Commits: `4bbccb5` (central) · `46b96b2` (CRM). Gate do épico **pendente do pareamento do chip** (manual). |

> **Nota sobre este registro:** é um log **por sessão** (grão grosso). O rastreamento **por story** — com hash de commit — vive nas tabelas de cada épico acima.
