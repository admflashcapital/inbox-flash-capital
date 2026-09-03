# Segurança — Regras Invioláveis — Inbox Flash Capital

> **Escopo: 19 stories** no inventário, das quais **11 vivas** (épicos 1, 3, 4 e 6) — os épicos 2 e 5 foram cancelados. `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).
>
> A proteção do `/twilio/callback` vive na **borda**: `deploy/ngrok-policy.yml` devolve **403** na URL pública, e `verificar-canal-oficial.sh` bate nela ao vivo. Deixou de ser topológica quando a central passou a ter `CENTRAL_URL_PUBLICA` (AD-11.1). Todo ingresso novo tem de trazer esse gate — o `Twilio::CallbackController` não valida assinatura — e exigir o `X-Relay-Token` (que hoje viaja mas nada cobra na entrada). `/twilio/delivery_status` fica **aberto de propósito**: é a Twilio que o chama, e sem ele o envio pela tela morre com 21609. Medido: ela aceita que ele devolva 404.


> A central concentra conversa de cliente com **CPF/CNPJ, valor em aberto e situação de
> inadimplência**. É o repositório de PII mais denso da Flash. Trate como tal.

## NUNCA

- ❌ Colar conteúdo real do `.env` no chat (nem parcialmente)
- ❌ Hardcodar API key/token/senha no código, no `docker-compose.yml` ou no runbook — usar env var
- ❌ `git add .env` — conferir `git status` antes de todo commit
- ❌ Logar valor de env var, ou logar **PII** (CPF/CNPJ, telefone, conteúdo de mensagem) em log de serviço
- ❌ Commitar `.env`, `secrets/`, `*.key`, `*.pem`, JSON de service account
- ❌ Publicar QUALQUER porta fora de `127.0.0.1` **no compose** (AD-10). Só `chatwoot-web`, e só em loopback; Postgres e Redis não publicam nada. A exposição pública vem de fora do compose (túnel/ingresso) e **sempre** com o gate da borda junto
- ❌ Aceitar webhook sem validar a origem (ver abaixo)

## SEMPRE

- ✅ Fluxo de nova env var: 1) `.env` (valor real) → 2) `.env.example` (placeholder + comentário) →
  3) `compose.yaml` → 4) commitar **apenas** o `.env.example` e a config
- ✅ Manter o `.env.example` sincronizado com todas as chaves
- ✅ TLS em todo tráfego externo, terminado pela **borda** (túnel da `CENTRAL_URL_PUBLICA` hoje, ingresso da Fase 4 amanhã) — nunca pelo Chatwoot, por isso `FORCE_SSL=false`
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

- Retenção **decidida e agendada**: 1825 dias (5 anos), aprovada por escrito em 2026-09-02, no cron
  do host (domingo 04:10, com `flock`). `destroy_all`, nunca `delete_all` — são os callbacks que
  removem os anexos do volume.
- Acesso a dado sensível (CPF/CNPJ, valor em aberto) **restrito por INBOX, não por papel** — ver
  AD-14. O CE não tem papel customizado, e o atributo é da conversa: quem a abre vê o documento.
  **Não há trilha de auditoria** (`audit_logs` é premium): não se sabe quem leu o quê.
- Direito de exclusão: apagar o contato na central **não** apaga a verdade no domínio — e vice-versa.
  O pedido do titular atinge **os dois lados**, e os backups seguram o dado por até ~4 semanas
  (7 diários + 4 semanais): restore depois de exclusão **ressuscita o dado**, e a exclusão precisa
  ser refeita. Procedimento completo: `docs/runbook-lgpd.md`.

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
