#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# verificar-canal-oficial.sh — invariantes do número oficial (EPIC-3)
# ═══════════════════════════════════════════════════════════════════
# O número oficial é o canal de DINHEIRO (cobrança e transacional). O que ele
# não pode ser, e o que este script recusa:
#
#   1. Ser um canal sem janela de 24h. `Channel::TwilioSms` só entra na janela
#      de 24h do WhatsApp quando `medium = whatsapp`. Criado como `sms` por
#      engano, o Chatwoot deixaria a atendente escrever texto livre depois das
#      24h — e a Meta REJEITA o envio. A mensagem sumiria em silêncio.
#   2. Ficar sem templates. Fora da janela, o único envio possível é por
#      template Meta aprovado. Sem os Content Templates sincronizados da
#      Twilio, a UI não tem o que oferecer e a conversa morre.
#   3. Virar motor de campanha (AD-6). Disparo em massa origina no monorepo; a
#      central só ESPELHA o outbound. Campanha nesta inbox = violação.
#   4. Expor o `/twilio/callback` na internet. O controller do Chatwoot NÃO
#      valida a assinatura da Twilio (só filtra params e enfileira). Quem
#      valida é o monorepo, que é o dono do webhook e faz o fan-out para cá.
#      Logo, este path só pode entrar pela rede interna / com o token do relay.
#
# Uso:  deploy/scripts/verificar-canal-oficial.sh
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
CADDYFILE="${RAIZ}/deploy/Caddyfile"
COMPOSE="docker compose -f ${RAIZ}/deploy/docker-compose.yml --env-file ${ENV_FILE}"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/^"\(.*\)"$/\1/'; }

DB="$(env_get POSTGRES_DATABASE)"
INBOX="$(env_get INBOX_OFICIAL_NOME)"; INBOX="${INBOX:-WhatsApp Oficial}"

consultar() { $COMPOSE exec -T postgres psql -tAX -U postgres -d "$DB" -c "$1" 2>/dev/null | tr -d '[:space:]'; }

FALHAS=0
ok()    { echo "  ✓ $1"; }
falha() { echo "  ✗ $1"; FALHAS=$((FALHAS + 1)); }

echo
echo "── Canal WhatsApp Oficial (Twilio) — inbox '${INBOX}' ─────────"

# ── 1. A inbox existe e é do canal certo ──────────────────────────
INBOX_ID="$(consultar "SELECT id FROM inboxes WHERE name = '${INBOX}' LIMIT 1;")"
if [ -z "$INBOX_ID" ]; then
  falha "a inbox '${INBOX}' não existe. Rode: make twilio (ver docs/runbook-canal-oficial.md)"
  echo
  echo "❌ ${FALHAS} violação(ões) — o canal oficial ainda não está ligado."
  exit 1
fi

TIPO="$(consultar "SELECT channel_type FROM inboxes WHERE id = ${INBOX_ID};")"
if [ "$TIPO" = "Channel::TwilioSms" ]; then
  ok "inbox '${INBOX}' (id ${INBOX_ID}) é Channel::TwilioSms"
else
  falha "inbox '${INBOX}' é '${TIPO}', deveria ser Channel::TwilioSms (AD-4: um número = uma inbox)"
fi

CHANNEL_ID="$(consultar "SELECT channel_id FROM inboxes WHERE id = ${INBOX_ID};")"

# ── 2. medium = whatsapp ⇒ janela de 24h ativa ────────────────────
# Enum do Chatwoot: 0 = sms, 1 = whatsapp. É o `medium` que faz o
# MessageWindowService aplicar a janela de 24h (twilio_messaging_window).
MEDIUM="$(consultar "SELECT medium FROM channel_twilio_sms WHERE id = ${CHANNEL_ID};")"
if [ "$MEDIUM" = "1" ]; then
  ok "medium = whatsapp ⇒ janela de 24h ativa (fora dela, o Chatwoot exige template)"
else
  falha "medium = ${MEDIUM} (não é whatsapp). Sem a janela de 24h a atendente escreveria texto livre e a Meta rejeitaria o envio."
fi

# ── 3. O número está em formato `whatsapp:+E164` ──────────────────
# É esse identificador que casa a conversa: o `From`/`To` da Twilio chega assim,
# e é assim que o monorepo precisa criar o contact_inbox para o disparo e a
# resposta caírem na MESMA thread (STORY-3.2).
NUMERO="$(consultar "SELECT phone_number FROM channel_twilio_sms WHERE id = ${CHANNEL_ID};")"
if printf '%s' "$NUMERO" | grep -qE '^whatsapp:\+[0-9]{10,15}$'; then
  ok "número gravado como '${NUMERO}' (formato que casa a thread com a Twilio)"
else
  falha "número gravado como '${NUMERO}' — esperado 'whatsapp:+E164'. A resposta do cliente não casaria com o disparo."
fi

# ── 4. Templates Meta sincronizados da Twilio ─────────────────────
QTD_TEMPLATES="$(consultar "
  SELECT coalesce(jsonb_array_length(content_templates->'templates'), 0)
  FROM channel_twilio_sms WHERE id = ${CHANNEL_ID};")"
if [ "${QTD_TEMPLATES:-0}" -gt 0 ] 2>/dev/null; then
  ok "${QTD_TEMPLATES} Content Template(s) sincronizado(s) da Twilio (envio fora da janela de 24h)"
else
  falha "nenhum Content Template sincronizado — fora da janela de 24h a atendente fica sem o que enviar. Rode: make twilio"
fi

# ── 5. AD-6: a central NÃO origina disparo em massa ───────────────
CAMPANHAS="$(consultar "SELECT count(*) FROM campaigns WHERE inbox_id = ${INBOX_ID};")"
if [ "${CAMPANHAS:-0}" -eq 0 ] 2>/dev/null; then
  ok "nenhuma campanha nesta inbox (AD-6: o motor de disparo é o monorepo)"
else
  falha "${CAMPANHAS} campanha(s) na inbox oficial — a central NÃO origina disparo em massa (AD-6)"
fi

# ── 6. O /twilio/callback não pode estar aberto na internet ───────
# Sem isso, qualquer um forja uma mensagem inbound na central: o
# Twilio::CallbackController do Chatwoot não confere X-Twilio-Signature.
if grep -q 'twilio/callback' "$CADDYFILE" && grep -q 'RELAY_TOKEN' "$CADDYFILE"; then
  ok "Caddy protege /twilio/callback com o token do relay (AD-8 — quem valida a assinatura é o monorepo)"
else
  falha "o Caddyfile não protege /twilio/callback. O controller do Chatwoot não valida a assinatura da Twilio: exposto, aceita mensagem forjada."
fi

if [ -n "$(env_get RELAY_TOKEN)" ]; then
  ok "RELAY_TOKEN presente no .env"
else
  falha "RELAY_TOKEN ausente no deploy/.env — o fan-out do monorepo não conseguiria entregar o inbound"
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ canal oficial dentro das invariantes (AD-4, AD-6, AD-8)."
  exit 0
fi
echo "❌ ${FALHAS} violação(ões) — ver docs/runbook-canal-oficial.md"
exit 1
