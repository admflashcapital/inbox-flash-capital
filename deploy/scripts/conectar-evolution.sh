#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# conectar-evolution.sh — liga o número de prospecção à central (STORY-2.1)
# ═══════════════════════════════════════════════════════════════════
# Configura a integração NATIVA Chatwoot da Evolution API (v2), que faz a
# instância do número de prospecção espelhar suas conversas na central.
#
#   POST {EVOLUTION_URL}/chatwoot/set/{EVOLUTION_INSTANCE}
#
# Com `autoCreate: true`, a própria Evolution cria no Chatwoot uma inbox do
# tipo `api` cujo `webhook_url` aponta de volta para
# {SERVER_URL da Evolution}/chatwoot/webhook/{instância} — é por esse webhook
# que a resposta digitada na central sai no WhatsApp do lead.
#
# ── Quem é dono do quê (AD-4/AD-5) ────────────────────────────────
# A instância Evolution mora no repo `crm-flash-capital` e continua sendo
# do CRM. Este script só a APONTA para a central; não a cria, não a pareia.
# O pareamento do chip (QR) é físico e manual — ver docs/runbook-canal-prospeccao.md.
#
# ── Por que importMessages/importContacts ficam DESLIGADOS ────────
# Esse recurso da Evolution abre conexão DIRETA no Postgres do Chatwoot
# (CHATWOOT_IMPORT_DATABASE_CONNECTION_URI). Isso exigiria expor o banco da
# central fora da rede interna — violaria AD-8 e AD-9. Importar histórico não
# vale o acoplamento: o espelho começa do zero, daqui para a frente.
#
# Uso:
#   deploy/scripts/conectar-evolution.sh            # aplica
#   deploy/scripts/conectar-evolution.sh --status   # só consulta o que está valendo
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"; }

# Não-secretos.
EVOLUTION_URL="$(env_get EVOLUTION_URL)"
EVOLUTION_INSTANCE="$(env_get EVOLUTION_INSTANCE)"
CENTRAL_URL="$(env_get CENTRAL_URL_PARA_EVOLUTION)"
CENTRAL_ACCOUNT_ID="$(env_get CENTRAL_ACCOUNT_ID)"
NOME_INBOX="$(env_get INBOX_PROSPECCAO_NOME)"
NOME_INBOX="${NOME_INBOX:-WhatsApp Prospecção}"

# Secretos: nunca ecoados, nem em erro, nem em log.
EVOLUTION_API_KEY="$(env_get EVOLUTION_API_KEY)"
CENTRAL_ACCESS_TOKEN="$(env_get CENTRAL_ACCESS_TOKEN)"

faltando=""
for chave in EVOLUTION_URL EVOLUTION_INSTANCE EVOLUTION_API_KEY CENTRAL_URL_PARA_EVOLUTION CENTRAL_ACCOUNT_ID CENTRAL_ACCESS_TOKEN; do
  [ -n "$(env_get "$chave")" ] || faltando="${faltando} ${chave}"
done
if [ -n "$faltando" ]; then
  echo "[evolution] ERRO: chaves ausentes no deploy/.env:${faltando}"
  echo "[evolution] veja docs/runbook-canal-prospeccao.md — o token da central é gerado na UI."
  exit 1
fi

# ── Como falamos com a Evolution ──────────────────────────────────
# De DENTRO da rede `flash-canais`, e não do host: a Evolution não publica
# porta (por design — AD-8), e um nome de container como `evolution-api` não
# resolve no host. Um contêiner efêmero na rede compartilhada resolve tanto o
# nome interno quanto uma URL pública (a bridge tem egress) — um caminho só,
# igual em dev e em produção.
#
# Os segredos entram por ENV (`-e VAR`, sem valor na linha de comando) e o
# corpo do POST por STDIN — nenhum token aparece em `ps` nem em log de shell.
REDE="${REDE_CANAIS:-flash-canais}"
IMAGEM_CURL="curlimages/curl:8.11.1"

evo_curl() {  # evo_curl <método> <caminho> [corpo-por-stdin]
  local metodo="$1" caminho="$2"
  EVOLUTION_API_KEY="$EVOLUTION_API_KEY" docker run --rm -i \
    --network "$REDE" \
    -e EVOLUTION_API_KEY \
    "$IMAGEM_CURL" \
    -sS -w '\n%{http_code}' -X "$metodo" \
    -H "apikey: ${EVOLUTION_API_KEY}" \
    -H "Content-Type: application/json" \
    "${EVOLUTION_URL}${caminho}" \
    "${@:3}"
}

# ── --status: o que está configurado hoje ─────────────────────────
if [ "${1:-}" = "--status" ]; then
  echo "[evolution] instância '${EVOLUTION_INSTANCE}' em ${EVOLUTION_URL}"
  evo_curl GET "/chatwoot/find/${EVOLUTION_INSTANCE}" </dev/null | sed '$d' \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print('  (sem integração configurada ou resposta inesperada)'); raise SystemExit(0)
if not d:
    print('  (integração Chatwoot ainda não configurada nesta instância)'); raise SystemExit(0)
# O token do Chatwoot volta no corpo — NUNCA imprima. Só o que é seguro.
seguro = ['enabled', 'accountId', 'url', 'nameInbox', 'signMsg', 'reopenConversation',
          'conversationPending', 'importContacts', 'importMessages', 'autoCreate', 'webhook_url']
for k in seguro:
    if k in d:
        print(f'  {k:20} {d[k]}')
"
  exit 0
fi

# ── Aplica a integração ───────────────────────────────────────────
echo "[evolution] apontando a instância '${EVOLUTION_INSTANCE}' para a central em ${CENTRAL_URL}"
echo "[evolution] inbox alvo: '${NOME_INBOX}' (autoCreate)"

RESPOSTA="$(evo_curl POST "/chatwoot/set/${EVOLUTION_INSTANCE}" -d @- <<JSON
{
  "enabled": true,
  "accountId": "${CENTRAL_ACCOUNT_ID}",
  "token": "${CENTRAL_ACCESS_TOKEN}",
  "url": "${CENTRAL_URL}",
  "nameInbox": "${NOME_INBOX}",
  "autoCreate": true,
  "signMsg": false,
  "signDelimiter": "\n",
  "reopenConversation": true,
  "conversationPending": false,
  "mergeBrazilContacts": true,
  "importContacts": false,
  "importMessages": false,
  "daysLimitImportMessages": 0,
  "organization": "Flash Capital",
  "ignoreJids": ["@g.us"]
}
JSON
)"

CODIGO="$(echo "$RESPOSTA" | tail -1)"
CORPO="$(echo "$RESPOSTA" | sed '$d')"

if [ "$CODIGO" != "200" ] && [ "$CODIGO" != "201" ]; then
  # O corpo pode ecoar o token enviado — não imprima. Só o código e a mensagem.
  echo "[evolution] FALHOU (HTTP ${CODIGO})."
  echo "$CORPO" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    msg = d.get('response', {}).get('message') or d.get('message') or d.get('error')
    print(f'  motivo: {msg}')
except Exception:
    print('  (resposta não-JSON — veja os logs da Evolution)')
" 2>/dev/null || true
  exit 1
fi

echo "[evolution] integração aplicada (HTTP ${CODIGO})."
echo
echo "  Confira na central: a inbox '${NOME_INBOX}' deve existir agora, do tipo 'api',"
echo "  com webhook_url = ${EVOLUTION_URL}/chatwoot/webhook/${EVOLUTION_INSTANCE}"
echo
echo "  Próximo passo (manual): parear o chip pelo QR e mandar uma mensagem de teste."
echo "  Ver docs/runbook-canal-prospeccao.md."
