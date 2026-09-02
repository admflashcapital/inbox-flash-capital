#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# conectar-gmail.sh — liga a caixa Gmail à central (STORY-4.1 / FR-9)
# ═══════════════════════════════════════════════════════════════════
# Cria a inbox `E-mail` (Channel::Email) e devolve a URL de autorização do
# Google. O operador clica, autoriza, e o callback do Chatwoot grava os tokens.
#
#   POST /api/v1/accounts/{id}/inboxes              (channel.type = email)
#   POST /api/v1/accounts/{id}/google/authorization (devolve a URL do consent)
#
# ── Por que SERVICE ACCOUNT não serve (não re-discutir) ────────────
# O Chatwoot só sabe o fluxo OAuth de USUÁRIO (3-legged):
#   Imap::GoogleFetchEmailService  → autentica XOAUTH2 com
#   Google::RefreshOauthTokenService → BaseRefreshOauthTokenService#refresh_tokens
#     `raise 'A refresh_token is not available' if provider_config[:refresh_token].blank?`
# Service account usa o grant JWT-bearer (domain-wide delegation) e NUNCA emite
# refresh_token. Não há onde pôr o JSON da SA. Injetar um access token de SA na
# marra faz o canal viver 1h e morrer DENTRO de um job do Sidekiq — em silêncio.
#
# ── Por que PRÉ-CRIAMOS a inbox (e não deixamos o callback criá-la) ─
# O `OauthCallbackController#create_channel_with_inbox` nomeia a inbox com o
# `users_data['name']` do perfil Google (ou o prefixo do e-mail). Isso violaria o
# nome FIXO `E-mail` do glossário do PRD. Pré-criada com o endereço certo, o
# callback a ENCONTRA (`find_channel_by_email`) e só anexa os tokens.
#
# ── O que este script NÃO faz ──────────────────────────────────────
# Não configura SMTP separado: com provider=google o Chatwoot envia por
# smtp.gmail.com:587 com XOAUTH2, usando o MESMO token do IMAP
# (ConversationReplyMailerHelper#oauth_smtp_settings).
#
# Uso:
#   scripts/conectar-gmail.sh          # cria a inbox + imprime a URL
#   scripts/conectar-gmail.sh --status # mostra o que está valendo
#   scripts/conectar-gmail.sh --url    # só re-imprime a URL (expira em 15min)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

# Não-secretos.
CENTRAL_URL="$(env_get CENTRAL_URL_INTERNA)"; CENTRAL_URL="${CENTRAL_URL:-http://chatwoot-web:3000}"
CONTA="$(env_get CENTRAL_ACCOUNT_ID)"
NOME_INBOX="$(env_get INBOX_EMAIL_NOME)"; NOME_INBOX="${NOME_INBOX:-E-mail}"
CAIXA="$(env_get GMAIL_CAIXA_ATENDIMENTO)"
FRONTEND_URL="$(env_get FRONTEND_URL)"
DB="$(env_get POSTGRES_DATABASE)"

# Secreto: expandido DENTRO do container, nunca no argv do host.
CENTRAL_ACCESS_TOKEN="$(env_get CENTRAL_ACCESS_TOKEN)"

faltando=""
for chave in CENTRAL_ACCOUNT_ID CENTRAL_ACCESS_TOKEN GMAIL_CAIXA_ATENDIMENTO \
             GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET FRONTEND_URL; do
  [ -n "$(env_get "$chave")" ] || faltando="${faltando} ${chave}"
done
if [ -n "$faltando" ]; then
  echo "[gmail] ERRO: chaves ausentes no .env:${faltando}"
  echo "[gmail] o OAuth Client é criado no Google Cloud — ver docs/runbook-canal-email.md"
  exit 1
fi

if ! printf '%s' "$CAIXA" | grep -qE '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$'; then
  echo "[gmail] ERRO: GMAIL_CAIXA_ATENDIMENTO='${CAIXA}' não parece um e-mail."
  exit 1
fi

REDE="${REDE_CANAIS:-flash-canais}"
IMAGEM_CURL="curlimages/curl:8.11.1"

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

consultar() { $COMPOSE exec -T postgres psql -tAX -U postgres -d "$DB" -c "$1" 2>/dev/null | tr -d '[:space:]'; }

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
  echo "[gmail] inbox '${NOME_INBOX}' na conta ${CONTA} (${CENTRAL_URL})"
  ID="$(consultar "SELECT id FROM inboxes WHERE name = '${NOME_INBOX}' LIMIT 1;")"
  if [ -z "$ID" ]; then
    echo "  (inbox ainda não existe — rode: bash scripts/conectar-gmail.sh)"
    exit 0
  fi
  CH="$(consultar "SELECT channel_id FROM inboxes WHERE id = ${ID};")"
  echo "  inbox_id               ${ID}"
  echo "  caixa                  $(consultar "SELECT email FROM channel_email WHERE id = ${CH};")"
  echo "  provider               $(consultar "SELECT coalesce(provider,'(vazio — OAuth não concluído)') FROM channel_email WHERE id = ${CH};")"
  echo "  imap_enabled           $(consultar "SELECT imap_enabled FROM channel_email WHERE id = ${CH};")"
  echo "  imap_address           $(consultar "SELECT coalesce(nullif(imap_address,''),'(vazio)') FROM channel_email WHERE id = ${CH};")"
  # NUNCA imprimimos o token — só se ele EXISTE.
  echo "  access_token gravado   $(consultar "SELECT (provider_config->>'access_token') IS NOT NULL AND (provider_config->>'access_token') <> '' FROM channel_email WHERE id = ${CH};")"
  echo "  refresh_token gravado  $(consultar "SELECT (provider_config->>'refresh_token') IS NOT NULL AND (provider_config->>'refresh_token') <> '' FROM channel_email WHERE id = ${CH};")"
  exit 0
fi

# ── Cria a inbox (ou reaproveita) ─────────────────────────────────
INBOX_ID="$(achar_inbox)"

if [ -n "$INBOX_ID" ]; then
  echo "[gmail] inbox '${NOME_INBOX}' já existe (id ${INBOX_ID}) — não recrio."
elif [ "${1:-}" = "--url" ]; then
  echo "[gmail] ERRO: inbox '${NOME_INBOX}' não existe. Rode sem --url para criá-la."
  exit 1
else
  echo "[gmail] criando a inbox '${NOME_INBOX}' (Channel::Email, ${CAIXA})"
  RESPOSTA="$(cw_curl POST "/api/v1/accounts/${CONTA}/inboxes" <<JSON
{
  "name": "${NOME_INBOX}",
  "channel": { "type": "email", "email": "${CAIXA}" }
}
JSON
)"
  CODIGO="$(echo "$RESPOSTA" | tail -1)"
  if [ "$CODIGO" != "200" ] && [ "$CODIGO" != "201" ]; then
    echo "[gmail] FALHOU (HTTP ${CODIGO})."
    echo "$RESPOSTA" | sed '$d' | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('  motivo:', d.get('message') or d.get('error') or d.get('attributes') or '(sem mensagem)')
except Exception:
    print('  (resposta não-JSON — veja: docker compose logs -f chatwoot-web)')
" 2>/dev/null || true
    echo
    echo "  Causas comuns:"
    echo "   • já existe um Channel::Email com este e-mail (índice único em channel_email.email)"
    echo "   • CENTRAL_ACCESS_TOKEN sem permissão de admin"
    exit 1
  fi
  INBOX_ID="$(achar_inbox)"
  echo "[gmail] inbox criada (id ${INBOX_ID}). Ainda SEM tokens — falta autorizar no Google."
fi

# ── Guard: a FRONTEND_URL precisa ser um redirect URI que o Google ACEITA ──
# O redirect é montado de FRONTEND_URL (OmniAuth.config.full_host), e o
# OauthCallbackController repete a MESMA URL na troca do code.
#
# Regra de validação do Google para client "Web application":
#   • HTTPS obrigatório …
#   • … EXCETO para `localhost` / `127.0.0.1`, que são ISENTOS e podem usar http.
# A isenção vale para o localhost PURO. `https://inbox.localhost` é um SUBDOMÍNIO
# e é RECUSADO — é por isso que em dev usamos a ponte de loopback na 3000.
aceito_pelo_google=false
# produção: https em domínio público
printf '%s' "$FRONTEND_URL" | grep -qE '^https://[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}(:[0-9]+)?(/|$)' \
  && ! printf '%s' "$FRONTEND_URL" | grep -qE '\.localhost(:[0-9]+)?(/|$)' \
  && aceito_pelo_google=true
# dev: localhost puro (http permitido pela isenção do Google)
printf '%s' "$FRONTEND_URL" | grep -qE '^https?://(localhost|127\.0\.0\.1)(:[0-9]+)?(/|$)' \
  && aceito_pelo_google=true

if [ "$aceito_pelo_google" != "true" ]; then
  echo
  echo "  ⚠️  FRONTEND_URL='${FRONTEND_URL}' NÃO é um redirect URI que o Google aceita."
  echo "      A dança falharia com redirect_uri_mismatch."
  echo
  echo "      O Google exige HTTPS, e só isenta o localhost PURO. Um subdomínio como"
  echo "      'inbox.localhost' NÃO é isento — foi por isso que existiu a ponte socat."
  echo "      Desde o AD-10 a central publica direto em 127.0.0.1, então a ponte morreu:"
  echo "      a própria FRONTEND_URL já é um redirect URI aceitável."
  echo
  echo "      Válido:   http://localhost:<CHATWOOT_HOST_PORT>   (dev — hoje 3001)"
  echo "                https://<host-publico>                  (quando houver ingresso)"
  echo
  echo "      ⚠️  A porta precisa constar em Authorized redirect URIs no Google Cloud,"
  echo "          com o sufixo /google/callback. Trocou a porta? Cadastre a nova."
  echo
  echo "      Passo a passo: docs/runbook-canal-email.md"
  exit 1
fi

# ── Sincroniza o installation_configs com o .env ──────────────────
# ARMADILHA: o controller do OAuth NÃO lê a env var. Ele lê
# `GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)`, que consulta a tabela
# `installation_configs`. Esse loader até tenta cair para o ENV… mas:
#
#   config = GlobalConfig.get(k)[k]
#   return config if config.present?              # linha existe e está VAZIA → segue
#   config_value = ENV.fetch(k) { default }       # pega do ENV, ok
#   i = InstallationConfig.where(name: k).first_or_create(value: config_value)
#   return i.value                                # ← ACHA a linha vazia e devolve o VAZIO
#
# O `installation_config.yml` do Chatwoot SEMEIA `GOOGLE_OAUTH_CLIENT_ID` com valor
# vazio no deploy. Então o `first_or_create` nunca cria nada, nunca atualiza, e o
# ENV é ignorado PARA SEMPRE. Sintoma: a URL de consentimento sai com `client_id`
# vazio e o Google responde um erro genérico — falha silenciosa clássica.
#
# Por isso gravamos o valor no banco explicitamente. O valor nunca é impresso.
echo "[gmail] sincronizando as credenciais OAuth no installation_configs…"
$COMPOSE exec -T chatwoot-web bundle exec rails runner '
%w[GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET].each do |k|
  v = ENV[k].to_s
  if v.empty?
    puts "  #{k}: ENV vazia — pulando"
    next
  end
  c = InstallationConfig.find_or_initialize_by(name: k)
  if c.value.to_s == v
    puts "  #{k}: já em dia"
  else
    c.value = v
    c.locked = false
    c.save!
    puts "  #{k}: gravado (#{v.length} chars)"   # tamanho, NUNCA o valor
  end
end
GlobalConfig.clear_cache
' 2>/dev/null | grep -E '^  ' || {
  echo "[gmail] FALHOU ao gravar as credenciais no banco."
  exit 1
}

# ── Gera a URL de autorização ─────────────────────────────────────
echo "[gmail] gerando a URL de autorização do Google…"
RESPOSTA="$(cw_curl POST "/api/v1/accounts/${CONTA}/google/authorization" </dev/null)"
CODIGO="$(echo "$RESPOSTA" | tail -1)"
if [ "$CODIGO" != "200" ]; then
  echo "[gmail] FALHOU ao gerar a URL (HTTP ${CODIGO})."
  echo "        Confira GOOGLE_OAUTH_CLIENT_ID/SECRET no .env e reinicie: docker compose up -d --wait"
  exit 1
fi

URL="$(echo "$RESPOSTA" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))")"
if [ -z "$URL" ]; then
  echo "[gmail] o Chatwoot não devolveu URL — GOOGLE_OAUTH_CLIENT_ID está preenchido?"
  exit 1
fi

echo
echo "  Abra no navegador, logado com ${CAIXA}:"
echo
echo "  ${URL}"
echo
echo "  ⏱️  O 'state' é um sgid assinado e EXPIRA EM 15 MINUTOS. Se demorar,"
echo "      rode de novo com --url para gerar outro."
echo
echo "  Depois de autorizar, confira:  bash scripts/verificar-canal-email.sh"
