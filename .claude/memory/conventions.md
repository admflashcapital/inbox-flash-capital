# Convenções — Inbox Flash Capital

> **Reescopo 2026-09-02, JÁ APLICADO** — EPIC-2 (Evolution) e EPIC-5 (Sync) cancelados; Caddy, Makefile e a rede `flash-canais` saíram na Fase 1. Hoje: `compose.yaml`, `.env` e `scripts/` na raiz, `docker compose up -d --wait` como comando único, central em `127.0.0.1:3001`, rede `flash-espelho` com 2 membros (AD-10..AD-13 em `docs/architecture.md`).
>
> **Como ficou:** não há Python neste repo (o Sync foi cancelado) nem `Caddyfile`. Bash em `scripts/` (com `scripts/lib/env.sh` para ler o `.env` sem `source`) e um seed Ruby em `scripts/seed/`, idempotente por contrato.


## Chatwoot (dicionário fechado — a consistência é o produto)

- **Labels:** kebab-case, **só** as do Glossário do PRD. **Sem sinônimos.**
  `lead-frio` · `lead-qualificado` · `cliente-ativo` · `em-cobranca` · `regua-etapa-N` ·
  `inadimplente` · `nao-identificado`
  Label nova = atualizar o Glossário em `docs/prd.md` **primeiro**. Sinônimo solto mata o filtro.
- **Atributos custom:** snake_case.
  `cnpj` · `cpf` · `status_operacao` · `dias_atraso` · `valor_em_aberto` · `origem` ·
  `link_twenty` · `link_supabase` · `source_twenty_id` · `source_supabase_id`
- **Nomes de inbox:** fixos — `WhatsApp Prospecção` · `WhatsApp Oficial` · `E-mail`

## Dados e formatos

- **Telefone:** sempre **E.164** (`+5531999998888`). Normalize na borda, antes de casar.
  ⚠️ O Twenty guarda `primaryPhoneNumber` **nacional** + `primaryPhoneCallingCode` (`+55`) —
  a conversão E.164 ↔ shape do Twenty é do Serviço de Sync, não do hub.
- **Documento:** **só dígitos** para casar (CPF/CNPJ sem máscara).
- **Timestamps:** UTC.
- **Link reverso:** ids de origem guardados como atributos `source_*_id`.

## Python (Serviço de Sync)

- `ruff format` + `ruff check --fix` (hook automático em Write/Edit de `.py`)
- Type hints e docstrings Google em toda função pública
- Testes: `pytest` + `httpx` (simular webhooks), mocks para APIs externas
- Alinhado ao monorepo: Python 3.12 + FastAPI + httpx
- **Idempotência é requisito, não zelo:** o push é upsert por identidade; o fan-out é at-least-once,
  então o mesmo evento **vai** chegar duas vezes. Retry com backoff exponencial em falha transitória.

## Infra

- `compose.yaml` + `(removido — Caddy)` + `.env.example`
- Imagem do Chatwoot **sempre com tag explícita** — `latest` é proibido (AD-7/FR-2)
- Upgrade: bump da tag + migrações, **validado em staging antes de produção**

## Variáveis de ambiente

- `.env.example` sempre sincronizado: var nova → placeholder + comentário no `.env.example`
- Segredos só em `.env` (gitignored) — nunca no código, no compose, no runbook nem no chat
- Nunca logar valor de env var

## Git

- Conventional commits: `feat(EPIC-N): STORY-X.Y — descrição` | `fix` | `chore` | `test` | `docs`
- Uma story = um commit. `main` direto (MVP single-dev).

## Idioma

- Tudo em PT-BR: docs, mensagens de commit, comentários de código, labels visíveis ao operador.
