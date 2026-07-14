#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# verificar-canal-email.sh — invariantes do canal E-mail (EPIC-4)
# ═══════════════════════════════════════════════════════════════════
# O canal de e-mail do Chatwoot falha CALADO de três jeitos. Este script
# recusa cada um deles:
#
#   1. OAuth pela metade. A inbox pode existir com `provider` vazio e sem
#      token: ela aparece bonita na UI e simplesmente nunca busca e-mail.
#   2. Sem refresh_token. O access_token vive 1h. Sem o refresh, o
#      Google::RefreshOauthTokenService levanta 'A refresh_token is not
#      available' DENTRO de um job do Sidekiq — a caixa para de sincronizar e
#      ninguém vê erro. (O Google só devolve refresh_token com
#      `access_type=offline` + `prompt=consent`; re-autorizar sem revogar o
#      consentimento anterior costuma devolver NADA.)
#   3. Agendador morto. O job `trigger_imap_email_inboxes_job` roda a cada
#      minuto e é ele que BUSCA o e-mail — e, de quebra, é ele que mantém o
#      access_token fresco no `provider_config`. E o SMTP de saída autentica
#      com esse token CRU (ConversationReplyMailerHelper#base_smtp_settings usa
#      `provider_config['access_token']`, sem passar pelo refresh).
#      Logo: agendador parado ⇒ em 1h a atendente também PARA DE CONSEGUIR
#      RESPONDER, e o erro morre dentro de um job.
#
# Uso:  deploy/scripts/verificar-canal-email.sh
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
COMPOSE="docker compose -f ${RAIZ}/deploy/docker-compose.yml --env-file ${ENV_FILE}"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"; }

DB="$(env_get POSTGRES_DATABASE)"
INBOX="$(env_get INBOX_EMAIL_NOME)"; INBOX="${INBOX:-E-mail}"
CAIXA="$(env_get GMAIL_CAIXA_ATENDIMENTO)"
REDIS_PW="$(env_get REDIS_PASSWORD)"

consultar() { $COMPOSE exec -T postgres psql -tAX -U postgres -d "$DB" -c "$1" 2>/dev/null | tr -d '[:space:]'; }

FALHAS=0
ok()    { echo "  ✓ $1"; }
falha() { echo "  ✗ $1"; FALHAS=$((FALHAS + 1)); }
aviso() { echo "  ⚠ $1"; }

echo
echo "── Canal E-mail (Gmail/OAuth) — inbox '${INBOX}' ──────────────"

# ── 1. A inbox existe e é do canal certo ──────────────────────────
INBOX_ID="$(consultar "SELECT id FROM inboxes WHERE name = '${INBOX}' LIMIT 1;")"
if [ -z "$INBOX_ID" ]; then
  falha "a inbox '${INBOX}' não existe. Rode: make gmail"
  echo
  echo "  ${FALHAS} falha(s)."
  exit 1
fi
TIPO="$(consultar "SELECT channel_type FROM inboxes WHERE id = ${INBOX_ID};")"
if [ "$TIPO" = "Channel::Email" ]; then
  ok "inbox ${INBOX_ID} existe e é Channel::Email"
else
  falha "inbox ${INBOX_ID} é '${TIPO}', não Channel::Email"
fi
CH="$(consultar "SELECT channel_id FROM inboxes WHERE id = ${INBOX_ID};")"

# ── 2. É a caixa que o .env declara ───────────────────────────────
EMAIL_GRAVADO="$(consultar "SELECT email FROM channel_email WHERE id = ${CH};")"
if [ "$EMAIL_GRAVADO" = "$CAIXA" ]; then
  ok "caixa = ${EMAIL_GRAVADO} (bate com GMAIL_CAIXA_ATENDIMENTO)"
else
  falha "caixa gravada é '${EMAIL_GRAVADO}', mas o .env diz '${CAIXA}'"
fi

# ── 3. OAuth concluído (provider=google) ──────────────────────────
PROVIDER="$(consultar "SELECT coalesce(provider,'') FROM channel_email WHERE id = ${CH};")"
if [ "$PROVIDER" = "google" ]; then
  ok "provider = google (fluxo OAuth concluído)"
else
  falha "provider = '${PROVIDER}' — o OAuth NÃO foi concluído. A inbox existe mas nunca vai buscar e-mail. Rode: make gmail-url"
fi

# ── 4. IMAP ligado e apontando para o Gmail ───────────────────────
IMAP_ON="$(consultar "SELECT imap_enabled FROM channel_email WHERE id = ${CH};")"
IMAP_ADDR="$(consultar "SELECT coalesce(imap_address,'') FROM channel_email WHERE id = ${CH};")"
if [ "$IMAP_ON" = "t" ] && [ "$IMAP_ADDR" = "imap.gmail.com" ]; then
  ok "imap_enabled + imap.gmail.com (o poller vai buscar)"
else
  falha "imap_enabled=${IMAP_ON} imap_address='${IMAP_ADDR}' — esperado t / imap.gmail.com"
fi

# ── 5. refresh_token presente (o canal morre em 1h sem ele) ───────
# Só testamos EXISTÊNCIA. O valor nunca é impresso (AD-8).
TEM_REFRESH="$(consultar "SELECT (provider_config->>'refresh_token') IS NOT NULL AND (provider_config->>'refresh_token') <> '' FROM channel_email WHERE id = ${CH};")"
if [ "$TEM_REFRESH" = "t" ]; then
  ok "refresh_token gravado (o canal se renova sozinho)"
else
  falha "SEM refresh_token. O access_token expira em 1h e o canal morre EM SILÊNCIO dentro do job. Re-autorize revogando antes o acesso em myaccount.google.com/permissions — sem isso o Google não devolve refresh_token de novo."
fi

# ── 6. O agendador está vivo (recebimento E envio dependem dele) ──
CRON_KEY="cron_job:default:trigger_imap_email_inboxes_job"
CRON_EXISTE="$($COMPOSE exec -T redis sh -c "redis-cli -a '${REDIS_PW}' --no-auth-warning EXISTS '${CRON_KEY}'" 2>/dev/null | tr -d '[:space:]')"
if [ "$CRON_EXISTE" = "1" ]; then
  ok "agendador do Sidekiq vivo e o job IMAP registrado (roda a cada minuto)"
else
  falha "o job '${CRON_KEY}' NÃO está registrado no Redis. Sem ele a caixa não sincroniza — e, em 1h, o token vence e a atendente também PARA DE RESPONDER. Veja: make logs s=chatwoot-sidekiq"
fi

# ── 7. As credenciais OAuth chegaram ao BANCO (não só ao .env) ────
# O controller do OAuth lê `GlobalConfigService.load`, que consulta
# `installation_configs` — NÃO a env var. E o yml do Chatwoot semeia essas linhas
# VAZIAS, o que faz o fallback para ENV (`first_or_create`) devolver o vazio da
# linha existente. Resultado: URL de consentimento com `client_id` em branco.
# Só checamos EXISTÊNCIA do valor, nunca o valor.
#
# ⚠️ NÃO dá para checar isto por SQL. A coluna é `serialized_value` (jsonb), mas o
# Rails grava YAML DENTRO dela (`serialize :serialized_value, coder: YAML` — o
# próprio Chatwoot marca a linha com um "FIX ME"). O jsonb é um ESCALAR contendo
# texto YAML, então `->>'value'` e `jsonb_object_keys` falham. Quem sabe
# desserializar é o model. Só perguntamos se está preenchido — nunca o valor.
# O `rails runner` escreve warnings de gem no STDOUT (RubyLLM, ip_lookup...), então
# a resposta vai atrás de um marcador e é isolada por grep — não por captura crua.
CREDS_OK="$($COMPOSE exec -T chatwoot-web bundle exec rails runner '
faltando = %w[GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET].reject do |k|
  InstallationConfig.find_by(name: k)&.value.present?
end
puts "CREDS_RESULT=#{faltando.empty? ? "ok" : faltando.join(",")}"
' 2>/dev/null | sed -n 's/^CREDS_RESULT=//p' | tr -d '[:space:]')"
if [ "$CREDS_OK" = "ok" ]; then
  ok "credenciais OAuth gravadas no installation_configs (é de lá que o controller lê, não do ENV)"
else
  falha "vazio no installation_configs: ${CREDS_OK:-erro ao consultar}. A env var sozinha NÃO basta — o Chatwoot semeia essa linha vazia e o fallback do GlobalConfigService devolve o vazio dela. A URL de consentimento sairia sem client_id. Rode: make gmail"
fi

# ── 8. AD-6: a central NÃO origina disparo em massa ───────────────
CAMPANHAS="$(consultar "SELECT count(*) FROM campaigns WHERE inbox_id = ${INBOX_ID};")"
if [ "${CAMPANHAS:-0}" -eq 0 ] 2>/dev/null; then
  ok "zero campanhas nesta inbox (AD-6 — o motor de disparo é o monorepo)"
else
  falha "${CAMPANHAS} campanha(s) na inbox de e-mail — AD-6 proíbe a central originar disparo em massa."
fi

# ── 9. Criptografia at-rest (não cobre o token do Gmail — avisa) ──
if grep -qE '^ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=.+' "$ENV_FILE" 2>/dev/null; then
  ok "ACTIVE_RECORD_ENCRYPTION ligado (protege Hook#access_token e imap/smtp_password)"
else
  aviso "ACTIVE_RECORD_ENCRYPTION desligado — segredo de integração fica em texto puro."
fi
# Dívida técnica conhecida, registrada no PROGRESS.md: independe do item acima.
aviso "o refresh_token do Gmail fica em TEXTO PURO no channel_email.provider_config (jsonb que o Chatwoot não criptografa) e, portanto, dentro de todo backup. Trate o BACKUP_DIR como segredo; revogue em myaccount.google.com/permissions se vazar."

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "  Canal de e-mail OK — nenhuma invariante violada."
  exit 0
fi
echo "  ${FALHAS} falha(s)."
exit 1
