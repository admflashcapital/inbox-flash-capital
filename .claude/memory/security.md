# Segurança — Regras Invioláveis — Inbox Flash Capital

> **Escopo: 16 stories**, nos épicos 1, 3, 4 e 6. `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).
>
> A proteção do `/twilio/callback` é **topológica**: a central só escuta em `127.0.0.1`. Qualquer ingresso futuro **precisa** de um gate no `X-Relay-Token` (AD-11) — o `Twilio::CallbackController` não valida assinatura. O `RELAY_TOKEN` está no `.env` e é conferido por `verificar-canal-oficial.sh`. `/twilio/delivery_status` está registrado como "a Twilio chama direto" — **suposição herdada**, não fato medido: confirmar no console antes de expor.


> A central concentra conversa de cliente com **CPF/CNPJ, valor em aberto e situação de
> inadimplência**. É o repositório de PII mais denso da Flash. Trate como tal.

## NUNCA

- ❌ Colar conteúdo real do `.env` no chat (nem parcialmente)
- ❌ Hardcodar API key/token/senha no código, no `docker-compose.yml` ou no runbook — usar env var
- ❌ `git add .env` — conferir `git status` antes de todo commit
- ❌ Logar valor de env var, ou logar **PII** (CPF/CNPJ, telefone, conteúdo de mensagem) em log de serviço
- ❌ Commitar `.env`, `secrets/`, `*.key`, `*.pem`, JSON de service account
- ❌ Publicar QUALQUER porta fora de `127.0.0.1` (AD-10). Só `chatwoot-web`, e só em loopback; Postgres e Redis não publicam nada
- ❌ Aceitar webhook sem validar a origem (ver abaixo)

## SEMPRE

- ✅ Fluxo de nova env var: 1) `.env` (valor real) → 2) `.env.example` (placeholder + comentário) →
  3) `compose.yaml` → 4) commitar **apenas** o `.env.example` e a config
- ✅ Manter o `.env.example` sincronizado com todas as chaves
- ✅ TLS em todo tráfego externo — hoje não há nenhum: a central só escuta em loopback
- ✅ Revogar credencial imediatamente ao suspeitar de vazamento

## Autenticação de webhook (AD-8) — cada canal tem o seu

| Origem | Como validar |
|---|---|
| **Twilio** (inbound oficial) | assinatura `X-Twilio-Signature` — quem valida é o **monorepo**, dono do webhook (`api/routers/twilio_webhooks_router.py`) |
| **Relay monorepo → central** (`/twilio/callback`) | ⚠️ o `Twilio::CallbackController` do Chatwoot **NÃO valida assinatura nenhuma**. Hoje quem protege é a **topologia**: a central só publica em `127.0.0.1` e só o `fastapi_api` a alcança, pela rede `flash-espelho`. O **`RELAY_TOKEN`** viaja no header `X-Relay-Token` e é o contrato com o monorepo, mas **nada o exige na borda** — passar a exigi-lo é pré-condição bloqueante de qualquer ingresso futuro |
| **`/twilio/delivery_status`** | fica **aberto de propósito** — é a Twilio que o chama direto, para as mensagens que a própria central envia. Forjá-lo só altera status de entrega. Inalcançável hoje; com ingresso, precisa de allowlist de origem |

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
- **Chatwoot:** o `CENTRAL_ACCESS_TOKEN` que o espelho do monorepo usa é de agente, separado do token de admin humano

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
