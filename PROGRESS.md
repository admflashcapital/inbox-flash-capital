# Inbox Flash Capital — Progress Tracker

> Para iniciar sessão: "Leia o CLAUDE.md e o PROGRESS.md, continue da próxima story pendente."
> Atualizado pelo Claude Code via `/done`. Detalhe de cada story em `docs/epics-and-stories.md`.

**Legenda:** `[ ]` pendente · `[~]` em andamento · `[x]` concluída · `[!]` bloqueada

**Milestones:** M1 = EPIC-1 · M2 = EPIC-2 + 3 + 4 (canais) · M3 = EPIC-5 (sync) · M4 = EPIC-6 (go-live).
O EPIC-1 bloqueia tudo. Os EPICs 2/3/4 podem correr em paralelo depois dele. O EPIC-5 precisa de ≥1 canal vivo.
Cada épico tem um gate de saída — use `/gate EPIC-N`.

**Progresso total:** 0 / 19 stories.

---

## EPIC-1 — Fundação da Plataforma

Chatwoot self-hosted na infra da Flash: deploy reproduzível, banco isolado, versão fixada, backup validado.

| # | Story | Status | Commit |
|---|---|---|---|
| 1.1 | Stack Docker da central sobe com um comando (FR-1) | [ ] | |
| 1.2 | Banco da central isolado dos bancos de domínio (FR-1, AD-9) | [ ] | |
| 1.3 | Versão fixada e procedimento de upgrade (FR-2) | [ ] | |
| 1.4 | Backup e restore validados (FR-3) | [ ] | |

**Gate EPIC-1:** `docker compose up -d` sobe web + Sidekiq + Postgres/pgvector + Redis + Caddy; UI do Chatwoot responde em HTTPS com cert válido; dados persistem após restart; imagem com **tag fixa** (nunca `latest`); Postgres próprio, sem credencial cruzada com Twenty/Supabase; restore de backup recompõe conversas e anexos num ambiente limpo.

---

## EPIC-2 — Canal WhatsApp Prospecção (Evolution)

Número novo pré-pago, **só inbound**, convivendo com o Agente N8N sem perda de mensagem.

| # | Story | Status | Commit |
|---|---|---|---|
| 2.1 | Inbox de prospecção espelhada no Chatwoot (FR-4) | [ ] | |
| 2.2 | Convivência com o Agente N8N sem perda — fan-out (FR-5, AD-5) | [ ] | |
| 2.3 | Aquecimento e proteção do número (FR-6) | [ ] | |

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
| — | — | — |

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

> **Nota sobre este registro:** é um log **por sessão** (grão grosso). O rastreamento **por story** — com hash de commit — vive nas tabelas de cada épico acima.
