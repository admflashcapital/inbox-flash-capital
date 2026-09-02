#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# conectar-twilio.sh — liga o número oficial à central (STORY-3.1 / FR-7)
# ═══════════════════════════════════════════════════════════════════
# Cria no Chatwoot a inbox `WhatsApp Oficial` como Channel::TwilioSms com
# `medium: whatsapp`, e sincroniza os Content Templates aprovados na Meta.
#
#   POST /api/v1/accounts/{id}/channels/twilio_channel
#   POST /api/v1/accounts/{id}/inboxes/{id}/sync_templates
#
# ── Por que `medium: whatsapp` é o detalhe que importa ────────────
# É o `medium` que faz o Chatwoot aplicar a JANELA DE 24H do WhatsApp
# (Conversations::MessageWindowService). Dentro da janela, a atendente responde
# texto livre; passadas 24h, o `can_reply?` fecha o campo e a UI só oferece os
# templates aprovados. Criado como `sms`, não haveria janela: a atendente
# escreveria texto livre, e a Meta rejeitaria o envio — falha silenciosa.
#
# ── O que este script NÃO faz (de propósito) ──────────────────────
# Não mexe no webhook do número na Twilio. Quem recebe o inbound é o MONOREPO
# (ele já valida a assinatura e usa a resposta do cliente para a confirmação de
# sacado); é de lá que o evento é espelhado para cá, por fan-out. Apontar o
# Twilio para o Chatwoot quebraria a confirmação de cobrança.
# O Chatwoot só repontaria o webhook sozinho se o canal fosse `medium: sms`
# (TwilioChannelsController: `setup_webhooks if @twilio_channel.sms?`) — mais um
# motivo para o medium estar certo.
#
# Uso:
#   scripts/conectar-twilio.sh            # cria a inbox + sincroniza templates
#   scripts/conectar-twilio.sh --status   # mostra o que está valendo
#   scripts/conectar-twilio.sh --templates # só re-sincroniza os templates
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
. "${RAIZ}/scripts/lib/env.sh"

# Não-secretos.
CENTRAL_URL="$(env_get CENTRAL_URL_INTERNA)"; CENTRAL_URL="${CENTRAL_URL:-http://chatwoot-web:3000}"
CONTA="$(env_get CENTRAL_ACCOUNT_ID)"
NOME_INBOX="$(env_get INBOX_OFICIAL_NOME)"; NOME_INBOX="${NOME_INBOX:-WhatsApp Oficial}"
NUMERO="$(env_get TWILIO_NUMERO_OFICIAL)"
TWILIO_ACCOUNT_SID="$(env_get TWILIO_ACCOUNT_SID)"

# Secretos: entram por STDIN (corpo) ou por ENV lido DENTRO do container.
# Nunca na linha de comando — `docker run ... -H "token: $X"` colocaria o valor
# no argv, visível em `ps`.
TWILIO_AUTH_TOKEN="$(env_get TWILIO_AUTH_TOKEN)"
CENTRAL_ACCESS_TOKEN="$(env_get CENTRAL_ACCESS_TOKEN)"

faltando=""
for chave in CENTRAL_ACCOUNT_ID CENTRAL_ACCESS_TOKEN TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_NUMERO_OFICIAL; do
  [ -n "$(env_get "$chave")" ] || faltando="${faltando} ${chave}"
done
if [ -n "$faltando" ]; then
  echo "[twilio] ERRO: chaves ausentes no .env:${faltando}"
  echo "[twilio] as credenciais Twilio são as MESMAS do monorepo — ver docs/runbook-canal-oficial.md"
  exit 1
fi

if ! printf '%s' "$NUMERO" | grep -qE '^\+[0-9]{10,15}$'; then
  echo "[twilio] ERRO: TWILIO_NUMERO_OFICIAL='${NUMERO}' não está em E.164 (ex.: +5531999999999)."
  echo "[twilio] o formato importa: é ele que casa a conversa do disparo com a resposta do cliente."
  exit 1
fi

REDE="${REDE_CANAIS:-flash-canais}"
IMAGEM_CURL="curlimages/curl:8.11.1"

# O token da central é expandido pelo shell DE DENTRO do container (aspas
# escapadas), então não aparece no argv do `docker run` no host.
cw_curl() {  # cw_curl <método> <caminho>   [corpo JSON por stdin]
  local metodo="$1" caminho="$2" data=""
  [ "$metodo" = "GET" ] || data="--data-binary @-"
  CENTRAL_ACCESS_TOKEN="$CENTRAL_ACCESS_TOKEN" docker run --rm -i \
    --network "$REDE" -e CENTRAL_ACCESS_TOKEN --entrypoint sh "$IMAGEM_CURL" -c "
      curl -sS -w '\n%{http_code}' -X ${metodo} \
        -H \"api_access_token: \$CENTRAL_ACCESS_TOKEN\" \
        -H 'Content-Type: application/json' \
        ${data} '${CENTRAL_URL}${caminho}'
    "
}

# Devolve o id da inbox pelo nome, ou vazio.
achar_inbox() {
  cw_curl GET "/api/v1/accounts/${CONTA}/inboxes" </dev/null | sed '$d' | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for i in d.get('payload', []):
    if i.get('name') == '''${NOME_INBOX}''':
        print(i['id']); break
"
}

# ── --status ──────────────────────────────────────────────────────
if [ "${1:-}" = "--status" ]; then
  echo "[twilio] inbox '${NOME_INBOX}' na conta ${CONTA} (${CENTRAL_URL})"
  cw_curl GET "/api/v1/accounts/${CONTA}/inboxes" </dev/null | sed '$d' | python3 -c "
import sys, json
d = json.load(sys.stdin)
alvo = [i for i in d.get('payload', []) if i.get('name') == '''${NOME_INBOX}''']
if not alvo:
    print('  (inbox ainda não existe — rode: bash scripts/conectar-twilio.sh)'); raise SystemExit(0)
i = alvo[0]
# O auth_token da Twilio volta no corpo — NUNCA imprima. Só o que é seguro.
for k in ['id', 'name', 'channel_type', 'medium', 'phone_number', 'messaging_service_sid']:
    if i.get(k) is not None:
        print(f'  {k:22} {i[k]}')
"
  exit 0
fi

# ── Cria a inbox (ou reaproveita, se já existe) ───────────────────
INBOX_ID="$(achar_inbox)"

if [ -n "$INBOX_ID" ]; then
  echo "[twilio] inbox '${NOME_INBOX}' já existe (id ${INBOX_ID}) — não recrio, só sincronizo os templates."
elif [ "${1:-}" = "--templates" ]; then
  echo "[twilio] ERRO: inbox '${NOME_INBOX}' não existe. Rode sem --templates para criá-la."
  exit 1
else
  echo "[twilio] criando a inbox '${NOME_INBOX}' (Channel::TwilioSms, medium=whatsapp, ${NUMERO})"

  RESPOSTA="$(cw_curl POST "/api/v1/accounts/${CONTA}/channels/twilio_channel" <<JSON
{
  "twilio_channel": {
    "name": "${NOME_INBOX}",
    "medium": "whatsapp",
    "account_sid": "${TWILIO_ACCOUNT_SID}",
    "auth_token": "${TWILIO_AUTH_TOKEN}",
    "phone_number": "${NUMERO}"
  }
}
JSON
)"
  CODIGO="$(echo "$RESPOSTA" | tail -1)"
  CORPO="$(echo "$RESPOSTA" | sed '$d')"

  if [ "$CODIGO" != "200" ] && [ "$CODIGO" != "201" ]; then
    # O corpo ecoa o que ENVIAMOS (inclusive o auth_token) e a mensagem de erro do
    # Rails pode conter a URL da Twilio com o Account SID dentro. Nada daqui sai cru:
    # imprimimos só o `motivo`, e ainda assim redigido.
    echo "[twilio] FALHOU (HTTP ${CODIGO})."
    echo "$CORPO" | python3 -c "
import sys, json, re

def redigir(texto: str) -> str:
    # Identificadores da Twilio (AC/SK/HX/SM/MM/MG + 32 hex) e qualquer cadeia longa
    # que cheire a token. Vale a pena ser agressivo: o custo de um falso positivo é
    # uma mensagem menos legível; o de um falso negativo é uma credencial no terminal.
    texto = re.sub(r'\b(AC|SK|HX|SM|MM|MG|IS|PN)[0-9a-fA-F]{32}\b', r'\1…[redigido]', texto)
    return re.sub(r'\b[0-9a-fA-F]{32,}\b', '[redigido]', texto)

try:
    d = json.load(sys.stdin)
    motivo = d.get('message') or d.get('error') or d.get('attributes') or '(sem mensagem)'
    print('  motivo:', redigir(str(motivo)))
except Exception:
    print('  (resposta não-JSON — veja: docker compose logs -f chatwoot-web)')
" 2>/dev/null || true
    echo
    echo "  Causas comuns:"
    echo "   • credencial Twilio inválida (o Chatwoot testa com client.messages.list antes de criar)"
    echo "   • CENTRAL_ACCESS_TOKEN sem permissão de admin"
    echo "   • já existe outra inbox com este número (índice único em phone_number)"
    exit 1
  fi

  INBOX_ID="$(achar_inbox)"
  echo "[twilio] inbox criada (id ${INBOX_ID})."
fi

# ── Sincroniza os Content Templates aprovados ─────────────────────
# Puxa da Content API da Twilio TODOS os templates da conta — os mesmos `HX...`
# que o monorepo já usa (lembrete de vencimento, alerta de vencidos, protesto…).
# É assíncrono (Sidekiq): o job pode levar alguns segundos.
echo "[twilio] sincronizando os Content Templates da Twilio…"
RESPOSTA="$(cw_curl POST "/api/v1/accounts/${CONTA}/inboxes/${INBOX_ID}/sync_templates" </dev/null)"
CODIGO="$(echo "$RESPOSTA" | tail -1)"
if [ "$CODIGO" != "200" ]; then
  echo "[twilio] sync de templates FALHOU (HTTP ${CODIGO}) — a inbox existe, mas fora da janela"
  echo "         de 24h a atendente ficaria sem template. Veja: docker compose logs -f chatwoot-sidekiq"
  exit 1
fi
echo "[twilio] sync disparado (job assíncrono no Sidekiq)."
echo
echo "  Confira: bash scripts/verificar-canal-oficial.sh   (valida as invariantes do canal, incl. a contagem de templates)"
echo
echo "  Falta o passo manual do lado do MONOREPO: o fan-out do webhook Twilio"
echo "  (o inbound entra lá, é validado, e é relayado para cá). Ver STORY-3.2 e"
echo "  docs/runbook-canal-oficial.md."
