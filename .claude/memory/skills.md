# Skills — roteador de acionamento por estágio — Inbox Flash Capital

> **Reescopo 2026-09-02, JÁ APLICADO** — EPIC-2 (Evolution) e EPIC-5 (Sync) cancelados; Caddy, Makefile e a rede `flash-canais` saíram na Fase 1. Hoje: `compose.yaml`, `.env` e `scripts/` na raiz, `docker compose up -d --wait` como comando único, central em `127.0.0.1:3001`, rede `flash-espelho` com 2 membros (AD-10..AD-13 em `docs/architecture.md`).
>
> **Como ficou:** as skills ligadas à Evolution/prospecção perderam uso — a Evolution saiu do repo.


> Carregado pelo `/story`. Ao iniciar uma story, acione as skills da linha do épico dela **+** as
> transversais aplicáveis.
> Stack: Docker/Caddy (infra) · Chatwoot (config, sem código) · Python/FastAPI (Serviço de Sync).
> **Sem frontend próprio** — a UI é a do Chatwoot.

## Sempre

| Quando | Skill |
|---|---|
| Escrever código no Serviço de Sync (ciclo RED→GREEN→REFACTOR) | `test-driven-development` |
| Travou num bug de integração entre serviços (fan-out, webhook, merge) | `systematic-debugging` |
| Antes de commitar | `/code-review` (built-in) |

## Por épico

| Épico | Skills a acionar |
|---|---|
| **EPIC-1** Fundação (Docker/Caddy/Postgres/backup) | `chatwoot-cli` (conhecer a API/CLI oficial antes de modelar o deploy) · `secrets-management` (`.env`, AD-8) |
| **EPIC-2** WhatsApp Prospecção (Evolution) | `api-design-principles` (contrato do webhook de fan-out) · `systematic-debugging` (**o fan-out é o ponto de falha mais provável do MVP** — dois consumidores no mesmo evento) |
| **EPIC-3** WhatsApp Oficial (Twilio/Meta) | `twilio-messaging-overview` (janela de 24h, qualidade do número) · `twilio-content-template-builder` (**templates Meta aprovados** — obrigatório fora da janela de 24h) · `api-design-principles` (push do outbound do monorepo) |
| **EPIC-4** E-mail (Gmail) | `chatwoot-cli` (config de inbox de e-mail) · `api-design-principles` (unificação de contato) |
| **EPIC-5** Serviço de Sync (**único código do zero**) | `fastapi-templates` (estrutura do serviço) · `python-testing-patterns` (testes de identidade/merge/idempotência) · `test-driven-development` (obrigatório) · `api-design-principles` (contrato dos eventos de domínio) · `chatwoot-cli` (API de contatos/labels/atributos) |
| **EPIC-6** Operação & Governança | `gdpr-data-handling` (LGPD ≈ GDPR — retenção, acesso, exclusão) · `chatwoot-cli` (papéis, labels, respostas rápidas) · `secrets-management` |

## Transversal (acione conforme a tarefa, não o épico)

| Tarefa | Skill |
|---|---|
| Escrever/ajustar testes Python (pytest, fixtures, mocks de API externa) | `python-testing-patterns` |
| Desenhar endpoint/webhook do Serviço de Sync | `api-design-principles` |
| Mexer em `.env`, token, credencial de webhook | `secrets-management` |
| Retenção, PII em log, direito de exclusão | `gdpr-data-handling` |
| Operar/inspecionar o Chatwoot pelo terminal (smoke test, gate de épico) | `chatwoot-cli` |
| Descobrir/instalar novas skills | `find-skills` |

## Skills a IGNORAR (não se aplicam)

- **Frontend** (React/Next.js/design system) — a UI é a do Chatwoot; não construímos tela.
- **Rails/Ruby** — não forkamos o Chatwoot (AD-7). Se você está pensando em mexer no código do
  Chatwoot, **pare** — a extensão é por API/webhook/automação/atributo custom.
- **n8n-\*** — os workflows N8N vivem no repo `crm-flash-capital`, não aqui. (Se a story mexer no
  fan-out do lado do CRM, trabalhe **lá**, com as skills de lá.)

## Manutenção

- Instaladas em `.claude/skills/` (project-level, agent `claude-code`), versionadas em `skills-lock.json`.
- Atualizar: `npx skills update` · Listar: `npx skills ls -a claude-code` · Buscar: `npx skills find <termo>`
- **Fontes oficiais em uso:** `chatwoot/cli` (org do Chatwoot) e `twilio/ai` (org da Twilio) — install
  count baixo, mas fonte de primeira mão. As demais vêm de `obra/superpowers`, `wshobson/agents` e
  `vercel-labs/skills`, as mesmas do CRM.
