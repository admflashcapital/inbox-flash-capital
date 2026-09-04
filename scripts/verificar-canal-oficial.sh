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
#      Com a central atrás de um túnel (AD-11.1), isso deixou de ser topológico:
#      o gate vive na borda e este script bate nele AO VIVO.
#   5. Guardar contexto invisível. A barra lateral do Chatwoot ITERA as
#      `custom_attribute_definitions` — sem definição, o valor que o espelho
#      carimba é gravado e nunca aparece. Falha 100% silenciosa (AD-13).
#
# Uso:  scripts/verificar-canal-oficial.sh
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

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
  falha "a inbox '${INBOX}' não existe. Rode: bash scripts/conectar-twilio.sh (ver docs/runbook-canal-oficial.md)"
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
  falha "nenhum Content Template sincronizado — fora da janela de 24h a atendente fica sem o que enviar. Rode: bash scripts/conectar-twilio.sh"
fi

# ── 5. AD-6: a central NÃO origina disparo em massa ───────────────
CAMPANHAS="$(consultar "SELECT count(*) FROM campaigns WHERE inbox_id = ${INBOX_ID};")"
if [ "${CAMPANHAS:-0}" -eq 0 ] 2>/dev/null; then
  ok "nenhuma campanha nesta inbox (AD-6: o motor de disparo é o monorepo)"
else
  falha "${CAMPANHAS} campanha(s) na inbox oficial — a central NÃO origina disparo em massa (AD-6)"
fi

# ── 6. O /twilio/callback não pode estar alcançável de fora ───────
# O Twilio::CallbackController do Chatwoot NÃO confere X-Twilio-Signature:
# alcançável, ele aceita mensagem forjada. A proteção é TOPOLÓGICA — a central só
# escuta em 127.0.0.1 — então a asserção prova exatamente isso: que nada publica
# fora da loopback. Qualquer ingresso futuro precisa de um gate no X-Relay-Token.
FORA="$($COMPOSE config --format json 2>/dev/null \
  | python3 -c "
import sys, json
s = json.load(sys.stdin)['services']
print(' '.join(
    f\"{n}:{(p.get('host_ip') if isinstance(p, dict) else None) or '0.0.0.0'}\"
    for n, c in s.items() for p in (c.get('ports') or [])
    if (p.get('host_ip') if isinstance(p, dict) else None) != '127.0.0.1'
))" 2>/dev/null)"
if [ -z "$FORA" ]; then
  ok "nada publica além de 127.0.0.1 no compose (AD-10)"
else
  falha "publicando fora da loopback (${FORA}) e o /twilio/callback ficou exposto — o Chatwoot não valida a assinatura da Twilio. Qualquer ingresso PRECISA do gate do X-Relay-Token antes."
fi

# ── 6. Os 8 atributos de conversa estão DEFINIDOS (AD-13) ─────────
# A barra lateral itera as definições, não as chaves gravadas: sem definição o
# carimbo do espelho some da tela sem erro nenhum. Os nomes são contrato com
# `monorepo-flash-capital/api/integrations/chatwoot/atributos.py::CHAVES`.
ESPERADOS="cedente cnpj data_vencimento dias_atraso link_boleto numero_nf titulo_id valor_em_aberto"
DEFINIDOS="$(consultar "SELECT string_agg(attribute_key, ' ' ORDER BY attribute_key) FROM custom_attribute_definitions WHERE attribute_model = 0;" | tr ',' ' ')"
FALTANDO=""
for chave in $ESPERADOS; do
  case " $DEFINIDOS " in *"$chave"*) ;; *) FALTANDO="${FALTANDO} ${chave}";; esac
done
if [ -z "$FALTANDO" ]; then
  ok "8 atributos de conversa definidos — o carimbo do espelho aparece na barra lateral (AD-13)"
else
  falha "sem CustomAttributeDefinition para:${FALTANDO} — o espelho carimba e o valor fica INVISÍVEL. Rode: docker compose run --rm chatwoot-seed"
fi

# ── 7. Se a central está exposta por túnel, o gate da borda está de pé ──
# O `/twilio/delivery_status` PRECISA responder (o 21609 exige alcançabilidade)
# e o `/twilio/callback` PRECISA ser negado. É a especificação de
# docs/runbook-deploy.md, cobrada na URL que está no .env agora.
PUB="$(env_get CENTRAL_URL_PUBLICA)"
case "$PUB" in
  http://localhost*|http://127.0.0.1*|"")
    ok "central em loopback: a proteção do /twilio/callback é topológica (sem borda para cobrar)"
    ;;
  *)
    # O que se cobra é o EFEITO — "o anônimo não chega no controller" —, não um código
    # específico. A borda de hoje (ngrok policy) nega com 403; a do AD-15 (Cloudflare
    # Access Service Auth) responde 302 para o IdP, e 401 em alguns caminhos. Fixar 403
    # faria este verificador ficar vermelho no dia da migração, com a agravante de
    # mandar o operador subir um túnel que já não existe.
    # 200/404/405 são os códigos do PRÓPRIO Rails: se vierem, o anônimo passou.
    COD_CB="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${PUB}/twilio/callback" 2>/dev/null)"
    case "$COD_CB" in
      403)         ok "borda nega /twilio/callback na URL pública (HTTP 403 — policy do túnel)" ;;
      302|303|401) ok "borda nega /twilio/callback na URL pública (HTTP ${COD_CB} — Access do AD-15)" ;;
      000|"")      falha "/twilio/callback não respondeu em ${PUB} — a borda está fora do ar, não protegendo" ;;
      *)           falha "/twilio/callback devolveu ${COD_CB} em ${PUB} — isso é resposta do próprio Rails, ou seja o anônimo CHEGOU no controller, que não valida assinatura nenhuma. Confira a policy da borda (hoje: deploy/ngrok-policy.yml; no AD-15: a App de Service Auth do Access)" ;;
    esac
    COD_DS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${PUB}/twilio/delivery_status" 2>/dev/null)"
    case "$COD_DS" in
      403|000|"") falha "/twilio/delivery_status devolveu ${COD_DS:-sem resposta} — a Twilio precisa alcançá-lo, senão volta o 21609 e a atendente não responde" ;;
      *)          ok "/twilio/delivery_status alcançável (HTTP ${COD_DS}) — sem 21609 no envio pela tela" ;;
    esac
    ;;
esac

if [ -n "$(env_get RELAY_TOKEN)" ]; then
  ok "RELAY_TOKEN presente no .env"
else
  falha "RELAY_TOKEN ausente no .env — o fan-out do monorepo não conseguiria entregar o inbound"
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ canal oficial dentro das invariantes (AD-4, AD-6, AD-8)."
  exit 0
fi
echo "❌ ${FALHAS} violação(ões) — ver docs/runbook-canal-oficial.md"
exit 1
