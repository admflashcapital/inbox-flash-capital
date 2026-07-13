#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# verificar-fanout.sh — os DOIS consumidores estão vivos? (STORY-2.2 / AD-5)
# ═══════════════════════════════════════════════════════════════════
# O risco de engenharia do EPIC-2: a instância Evolution tem dois consumidores
# (o Agente N8N e a central). Se um deles "consumir" o evento e sumir com ele, o
# outro fica cego. Este script confere que os dois seguem configurados na MESMA
# instância — e falha se um sumiu.
#
# Não é fila competida: a Evolution dispara os dois no mesmo handler de mensagem
# (chatwootService.eventWhatsapp na linha 1331 e sendDataWebhook na 1483 de
# whatsapp.baileys.service.ts), e o envio ao Chatwoot tem try/catch próprio
# (linha 2525) — central fora do ar NÃO impede o evento de chegar ao N8N.
#
# A prova ao vivo (mensagem real chegando nos dois) exige o chip pareado — o
# procedimento está no fim da saída e em docs/runbook-canal-prospeccao.md.
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/^"\(.*\)"$/\1/'; }

EVOLUTION_URL="$(env_get EVOLUTION_URL)"
EVOLUTION_INSTANCE="$(env_get EVOLUTION_INSTANCE)"
EVOLUTION_API_KEY="$(env_get EVOLUTION_API_KEY)"
REDE="${REDE_CANAIS:-flash-canais}"
CONTAINER_EVO="${CONTAINER_EVOLUTION:-crm-flash-capital-evolution-api-1}"

FALHAS=0
ok()    { echo "  ✓ $1"; }
falha() { echo "  ✗ $1"; FALHAS=$((FALHAS + 1)); }

echo
echo "── Consumidor 1 — o Agente N8N (webhook global) ───────────────"
# O webhook global é config de AMBIENTE da Evolution (não por instância):
# lemos do próprio container. Nenhum segredo é impresso.
if docker inspect "$CONTAINER_EVO" >/dev/null 2>&1; then
  WH_ON="$(docker inspect "$CONTAINER_EVO" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^WEBHOOK_GLOBAL_ENABLED=//p')"
  WH_URL="$(docker inspect "$CONTAINER_EVO" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^WEBHOOK_GLOBAL_URL=//p')"
  CW_ON="$(docker inspect "$CONTAINER_EVO" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^CHATWOOT_ENABLED=//p')"
  SRV_URL="$(docker inspect "$CONTAINER_EVO" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^SERVER_URL=//p')"

  [ "$WH_ON" = "true" ] && ok "WEBHOOK_GLOBAL_ENABLED=true" || falha "webhook global DESLIGADO — o Agente N8N ficaria cego"
  case "$WH_URL" in
    *n8n*) ok "webhook global aponta para o N8N (${WH_URL})" ;;
    "")    falha "WEBHOOK_GLOBAL_URL vazia" ;;
    *)     falha "webhook global NÃO aponta para o N8N: ${WH_URL}" ;;
  esac
else
  echo "  … container ${CONTAINER_EVO} não está no ar: pulei as checagens de ambiente"
  CW_ON=""; SRV_URL=""
fi

echo
echo "── Consumidor 2 — a central (integração nativa Chatwoot) ──────"
[ "${CW_ON:-}" = "true" ] && ok "CHATWOOT_ENABLED=true no ambiente da Evolution" \
  || falha "CHATWOOT_ENABLED não está 'true' — a central ficaria cega"

if [ -n "$EVOLUTION_API_KEY" ]; then
  CFG="$(EVOLUTION_API_KEY="$EVOLUTION_API_KEY" docker run --rm --network "$REDE" -e EVOLUTION_API_KEY \
    curlimages/curl:8.11.1 -sS -H "apikey: ${EVOLUTION_API_KEY}" \
    "${EVOLUTION_URL}/chatwoot/find/${EVOLUTION_INSTANCE}" 2>/dev/null)"
  echo "$CFG" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin) or {}
except Exception:
    d = {}
if d.get('enabled'):
    print(f\"  ✓ integração aplicada na instância — inbox '{d.get('nameInbox')}' (conta {d.get('accountId')})\")
    if d.get('importMessages') or d.get('importContacts'):
        print('  ✗ importMessages/importContacts LIGADOS: exigem conexão direta no Postgres da central (AD-8/AD-9)')
        raise SystemExit(1)
    print('  ✓ import por Postgres direto desligado (AD-8/AD-9 preservados)')
else:
    print('  ✗ a instância NÃO tem a integração Chatwoot aplicada — rode: make evolution')
    raise SystemExit(1)
" || FALHAS=$((FALHAS + 1))
else
  falha "EVOLUTION_API_KEY ausente no .env — não consegui consultar a instância"
fi

echo
echo "── Mídia: a central consegue baixar o anexo do lead? ──────────"
case "${SRV_URL:-}" in
  *localhost*) falha "SERVER_URL=${SRV_URL} — só o próprio container alcança; o anexo do lead não chegaria na central" ;;
  "")          echo "  … não consegui ler o SERVER_URL (Evolution fora do ar)" ;;
  *)           ok "SERVER_URL=${SRV_URL} (alcançável pelos consumidores)" ;;
esac
SAFE="$(env_get SAFE_FETCH_ALLOW_PRIVATE_NETWORK)"
[ "$SAFE" = "true" ] && ok "SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true (a central pode falar com a rede privada)" \
  || falha "SAFE_FETCH_ALLOW_PRIVATE_NETWORK não está 'true' — webhook e mídia falham EM SILÊNCIO"

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ fan-out configurado: N8N e central recebem o MESMO evento."
else
  echo "❌ ${FALHAS} problema(s) — um dos consumidores está cego."
fi

cat <<'FIM'

Prova ao vivo (exige o chip pareado — docs/runbook-canal-prospeccao.md):
  1. mande UMA mensagem de outro celular para o número de prospecção;
  2. a conversa aparece na inbox `WhatsApp Prospecção` da central;   ← consumidor 2
  3. o N8N registra uma execução do WF-04-001 para a MESMA mensagem; ← consumidor 1
  4. a saudação + link do Jotform que o Agente responder também aparece
     na conversa da central (mensagem `fromMe` é espelhada como outgoing).
Nenhum dos dois pode ficar sem o evento — se um viu e o outro não, PARE: virou fila competida.
FIM

exit "$([ "$FALHAS" -eq 0 ] && echo 0 || echo 1)"
