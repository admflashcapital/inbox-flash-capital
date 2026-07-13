#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# verificar-aquecimento.sh — proteção do número (STORY-2.3 / FR-6)
# ═══════════════════════════════════════════════════════════════════
# Um chip novo que dispara muito, ou que INICIA conversa com quem nunca falou
# com ele, é o retrato do spammer para o Meta — e o bloqueio vem rápido. Aqui a
# regra do projeto vira verificação:
#
#   1. O número de prospecção é SÓ INBOUND. Ele responde quem chegou; nunca
#      puxa conversa. Uma conversa cuja PRIMEIRA mensagem é nossa = outbound
#      frio. Isso deve ser ZERO — e falha aqui se não for.
#   2. Volume diário dentro da rampa de aquecimento (semana a semana).
#
# Prospecção fria da Flash sai por E-MAIL. O WhatsApp de prospecção só
# recepciona o lead pescado e manda o link do Jotform. E o número OFICIAL (o de
# cobrança) fica longe de tudo isso: número queimado leva o canal de dinheiro
# junto.
#
# Uso:  deploy/scripts/verificar-aquecimento.sh
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
COMPOSE="docker compose -f ${RAIZ}/deploy/docker-compose.yml --env-file ${ENV_FILE}"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/^"\(.*\)"$/\1/'; }

DB="$(env_get POSTGRES_DATABASE)"
INBOX="$(env_get INBOX_PROSPECCAO_NOME)"; INBOX="${INBOX:-WhatsApp Prospecção}"
DESDE="$(env_get NUMERO_PROSPECCAO_DESDE)"   # data do pareamento (YYYY-MM-DD)

consultar() { $COMPOSE exec -T postgres psql -tAX -U postgres -d "$DB" -c "$1" 2>/dev/null | tr -d '[:space:]'; }

FALHAS=0
ok()    { echo "  ✓ $1"; }
falha() { echo "  ✗ $1"; FALHAS=$((FALHAS + 1)); }
aviso() { echo "  ⚠ $1"; }

INBOX_ID="$(consultar "SELECT id FROM inboxes WHERE name = '${INBOX}' LIMIT 1;")"
if [ -z "$INBOX_ID" ]; then
  echo "  … inbox '${INBOX}' ainda não existe (rode: make evolution). Nada a verificar."
  exit 0
fi

# ── Rampa de aquecimento ──────────────────────────────────────────
# Conservadora de propósito: o volume real da Flash é de 5–20 leads/mês, então a
# rampa nunca é o gargalo — ela existe para proteger o chip, não para acelerar.
limite_do_dia() {
  local semana="$1"
  case "$semana" in
    1) echo 20  ;;   # semana 1: quase só responder quem chegou
    2) echo 40  ;;
    3) echo 60  ;;
    4) echo 80  ;;
    *) echo 100 ;;   # regime (≥ semana 5)
  esac
}

if [ -n "$DESDE" ]; then
  DIAS=$(( ( $(date -u +%s) - $(date -u -d "$DESDE" +%s) ) / 86400 ))
  SEMANA=$(( DIAS / 7 + 1 ))
else
  SEMANA=1
  aviso "NUMERO_PROSPECCAO_DESDE não está no .env — assumindo SEMANA 1 (o limite mais apertado)."
fi
LIMITE="$(limite_do_dia "$SEMANA")"

echo
echo "── Número de prospecção — inbox '${INBOX}' (id ${INBOX_ID}) ───"
echo "  semana de aquecimento: ${SEMANA} → limite de ${LIMITE} mensagens enviadas/dia"

# ── 1. Só inbound: nenhuma conversa iniciada por nós ───────────────
# A primeira mensagem de cada conversa: se for `outgoing` (message_type=1),
# nós puxamos conversa com alguém que não nos procurou. Isso é cold outreach.
FRIAS="$(consultar "
  SELECT count(*) FROM (
    SELECT DISTINCT ON (m.conversation_id) m.conversation_id, m.message_type
    FROM messages m
    JOIN conversations c ON c.id = m.conversation_id
    WHERE c.inbox_id = ${INBOX_ID}
    ORDER BY m.conversation_id, m.id
  ) primeira WHERE primeira.message_type = 1;")"

if [ "${FRIAS:-0}" -eq 0 ] 2>/dev/null; then
  ok "nenhuma conversa iniciada pela Flash — o número está operando SÓ INBOUND"
else
  falha "${FRIAS} conversa(s) INICIADA(S) por nós neste número = outbound frio. Pare: isso queima o chip."
fi

# ── 2. Campanha na central: a central não é motor de disparo (AD-6) ─
CAMPANHAS="$(consultar "SELECT count(*) FROM campaigns WHERE inbox_id = ${INBOX_ID};")"
if [ "${CAMPANHAS:-0}" -eq 0 ] 2>/dev/null; then
  ok "nenhuma campanha configurada nesta inbox (AD-6: o motor de disparo é o monorepo)"
else
  falha "${CAMPANHAS} campanha(s) na inbox de prospecção — a central NÃO origina disparo (AD-6)"
fi

# ── 3. Volume enviado nas últimas 24h ─────────────────────────────
ENVIADAS="$(consultar "
  SELECT count(*) FROM messages m
  JOIN conversations c ON c.id = m.conversation_id
  WHERE c.inbox_id = ${INBOX_ID}
    AND m.message_type = 1
    AND m.created_at > now() - interval '24 hours';")"
ENVIADAS="${ENVIADAS:-0}"

if [ "$ENVIADAS" -le "$LIMITE" ]; then
  ok "${ENVIADAS} mensagem(ns) enviada(s) nas últimas 24h (limite da semana ${SEMANA}: ${LIMITE})"
else
  falha "${ENVIADAS} enviadas nas últimas 24h — ACIMA do limite de ${LIMITE} da semana ${SEMANA}"
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ número dentro da política de aquecimento e proteção."
  exit 0
fi
echo "❌ ${FALHAS} violação(ões) — ver docs/runbook-aquecimento-numero.md"
exit 1
