# Segurança — Regras Invioláveis — Inbox Flash Capital

> **Reescopo 2026-09-02** — EPIC-2 (Evolution) e EPIC-5 (Sync) **cancelados**; Caddy, Makefile e a rede `flash-canais` saem (AD-10..AD-13 em `docs/architecture.md`). O que segue vale até a Fase 1 rodar.
>
> **Muda aqui:** o gate do `/twilio/callback` sai do Caddy e vira regra de ingress/Access — mas **continua obrigatório** (AD-11), porque o `Twilio::CallbackController` não valida assinatura. `/twilio/delivery_status` está registrado como "a Twilio chama direto" — isso é **suposição herdada**, não fato medido: confirmar no console da Twilio antes de qualquer exposição. As linhas sobre Evolution e Serviço de Sync morrem.


> A central concentra conversa de cliente com **CPF/CNPJ, valor em aberto e situação de
> inadimplência**. É o repositório de PII mais denso da Flash. Trate como tal.

## NUNCA

- ❌ Colar conteúdo real do `.env` no chat (nem parcialmente)
- ❌ Hardcodar API key/token/senha no código, no `docker-compose.yml` ou no runbook — usar env var
- ❌ `git add .env` — conferir `git status` antes de todo commit
- ❌ Logar valor de env var, ou logar **PII** (CPF/CNPJ, telefone, conteúdo de mensagem) em log de serviço
- ❌ Commitar `.env`, `secrets/`, `*.key`, `*.pem`, JSON de service account
- ❌ Expor Postgres/Redis da central fora da rede Docker interna — só o Caddy publica porta
- ❌ Aceitar webhook sem validar a origem (ver abaixo)

## SEMPRE

- ✅ Fluxo de nova env var: 1) `.env` (valor real) → 2) `.env.example` (placeholder + comentário) →
  3) `compose.yaml` → 4) commitar **apenas** o `.env.example` e a config
- ✅ Manter o `.env.example` sincronizado com todas as chaves
- ✅ TLS em todo tráfego externo (Caddy, auto-HTTPS)
- ✅ Revogar credencial imediatamente ao suspeitar de vazamento

## Autenticação de webhook (AD-8) — cada canal tem o seu

| Origem | Como validar |
|---|---|
| **Twilio** (inbound oficial) | assinatura `X-Twilio-Signature` — quem valida é o **monorepo**, dono do webhook (`api/routers/twilio_webhooks_router.py`) |
| **Relay monorepo → central** (`/twilio/callback`) | ⚠️ o `Twilio::CallbackController` do Chatwoot **NÃO valida assinatura nenhuma**. Quem protege é o **`RELAY_TOKEN`** no header `X-Relay-Token`, barrado no **Caddy** (falha fechada: sem token → 403). O inbound legítimo chega pelo monorepo, que já validou a assinatura |
| **`/twilio/delivery_status`** | fica **aberto de propósito** — é a Twilio que o chama direto, para as mensagens que a própria central envia. Forjá-lo só altera status de entrega. Dívida técnica: allowlist de IP no Caddy (EPIC-6) |
| **Evolution** (fan-out do CRM) | token compartilhado no header |
| **Chatwoot** (eventos → Serviço de Sync) | token compartilhado no header |
| **Serviço de Sync → API do Chatwoot** | access token de agente/bot, escopo mínimo |

## Segredo que o Chatwoot NÃO criptografa (EPIC-4)

O `Channel::Email` criptografa só `imap_password`/`smtp_password`. Com OAuth (Gmail), a credencial
real é o **`refresh_token` no `provider_config`** — coluna **jsonb, não criptografada**, mesmo com as
chaves `ACTIVE_RECORD_ENCRYPTION_*` ligadas. Escopo `https://mail.google.com/` (lê e envia na caixa
inteira) e **não expira**. Fica em texto puro no Postgres **e em todo backup**. Corrigir exigiria
forkar o Chatwoot (proibido, AD-7). Mitigação: `BACKUP_DIR` é segredo; revogar em
`myaccount.google.com/permissions` se vazar.

Webhook público sem verificação = ingestão forjada (mensagem falsa na conversa de um cliente real).

## Menor privilégio (serviços externos)

- **Gmail:** conta/app password dedicada à caixa de atendimento — não a conta pessoal de ninguém
- **Twilio:** credencial já existente no monorepo; a central **não** ganha permissão de disparo em massa
- **Evolution:** apikey interna, sem exposição externa
- **Chatwoot:** token de bot para o Sync, separado do token de admin humano

## LGPD (Story 6.3)

- Retenção de conversas **configurada** (não infinita por default)
- Acesso a dado sensível (CPF/CNPJ, valor em aberto) **restrito por papel**
- Direito de exclusão: apagar o contato na central **não** apaga a verdade no domínio — e vice-versa.
  O pedido do titular atinge **os dois lados**; documente o procedimento antes do go-live.

## gitleaks

```bash
gitleaks detect --no-banner            # escaneia o histórico completo
gitleaks protect --staged --no-banner  # escaneia apenas o staged
```
O hook `PreToolUse` (`.claude/hooks/commit-guard.sh`) roda `gitleaks protect --staged` antes de cada
`git commit`.

## Em caso de vazamento

1. Revogar a credencial no serviço **imediatamente**
2. Gerar nova credencial e atualizar o `.env` local
3. `git log --all -- '*.env'` para verificar se foi commitado
4. Se commitado: `git filter-repo` para remover do histórico
