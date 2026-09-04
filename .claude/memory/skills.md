# Skills — roteador de acionamento por estágio — Inbox Flash Capital

> **Escopo: 19 stories** no inventário, das quais **11 vivas** (épicos 1, 3, 4 e 6) — os épicos 2 e 5 foram cancelados. `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-15).
>

> Carregado pelo `/story`. Ao iniciar uma story, acione as skills da linha do épico dela **+** as
> transversais aplicáveis.
> Stack: Docker (infra) · Chatwoot (configuração, **sem código de aplicação**).
> **Sem frontend próprio** — a UI é a do Chatwoot.

## Sempre

| Quando | Skill |
|---|---|
| Escrever script de operação ou verificador (ciclo RED→GREEN→REFACTOR) | `test-driven-development` |
| Travou num bug de integração entre serviços (fan-out, webhook, merge) | `systematic-debugging` |
| Antes de commitar | `/code-review` (built-in) |

## Por épico

| Épico | Skills a acionar |
|---|---|
| **EPIC-1** Fundação (Docker/Postgres/backup) | `chatwoot-cli` (conhecer a API/CLI oficial antes de modelar o deploy) · `secrets-management` (`.env`, AD-8) |
| **EPIC-3** WhatsApp Oficial (Twilio/Meta) | `twilio-messaging-overview` (janela de 24h, qualidade do número) · `twilio-content-template-builder` (**templates Meta aprovados** — obrigatório fora da janela de 24h) · `api-design-principles` (push do outbound do monorepo) |
| **EPIC-4** E-mail (Gmail) | `chatwoot-cli` (config de inbox de e-mail) · `api-design-principles` (contexto carimbado na conversa, AD-13) |
| **EPIC-6** Operação & Governança | `gdpr-data-handling` (LGPD ≈ GDPR — retenção, acesso, exclusão) · `chatwoot-cli` (papéis, labels, respostas rápidas) · `secrets-management` |

## Transversal (acione conforme a tarefa, não o épico)

| Tarefa | Skill |
|---|---|
| Desenhar contrato de webhook ou de chamada à API da central | `api-design-principles` |
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
