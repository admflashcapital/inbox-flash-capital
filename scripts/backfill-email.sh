#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# backfill-email.sh — importa histórico retroativo da caixa (EPIC-4)
# ═══════════════════════════════════════════════════════════════════
# O job agendado do Chatwoot roda com `interval = 1`, ou seja, busca só
# `SINCE (hoje − 1 dia)`. Isso é o certo para o regime permanente — mas na
# PRIMEIRA sincronização a central nasce sem histórico nenhum.
#
# Este script chama o mesmo job com um intervalo maior. É seguro:
#   • IDEMPOTENTE — `Imap::BaseFetchEmailService#email_already_present?` deduplica
#     por `message_id`, então re-rodar não duplica conversa nem mensagem.
#   • TETO — `MAX_MESSAGES_PER_SYNC = 500` por sync. Acima disso o Chatwoot para
#     e loga; rode de novo (ou em fatias) se a caixa for grande.
#
# ⚠️ O Chatwoot lê SÓ a pasta INBOX (`imap.select('INBOX')` está fixo no código).
#    E-mail ARQUIVADO no Gmail sai da INBOX e NUNCA será importado por aqui.
#
# ⚠️ Isto traz PII de cliente para a central. Ver a dívida de retenção (LGPD) no
#    PROGRESS.md — o expurgo existe (`bash scripts/retencao-conversas.sh`) mas não está no cron.
#
# Uso:
#   scripts/backfill-email.sh          # 30 dias (default)
#   scripts/backfill-email.sh 90       # 90 dias
#   scripts/backfill-email.sh --contar # só CONTA o que existe, não importa
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

INBOX="$(env_get INBOX_EMAIL_NOME)"; INBOX="${INBOX:-E-mail}"

# ── --contar: quanto histórico existe, por janela (não importa nada) ──
if [ "${1:-}" = "--contar" ]; then
  $COMPOSE exec -T chatwoot-web bundle exec rails runner '
require "net/imap"
ch  = Inbox.find_by(name: ENV.fetch("INBOX_EMAIL_NOME", "E-mail")).channel
tok = Google::RefreshOauthTokenService.new(channel: ch).access_token
imap = Net::IMAP.new("imap.gmail.com", port: 993, ssl: true)
Imap::Authentication.authenticate!(imap, "XOAUTH2", ch.imap_login, tok)
imap.select("INBOX")
[1, 7, 30, 90, 365].each do |d|
  n = imap.search(["SINCE", (Date.today - d).strftime("%d-%b-%Y")]).length
  puts "BF   últimos #{d.to_s.rjust(3)} dia(s): #{n.to_s.rjust(4)} msg na INBOX#{n > 500 ? "  ⚠️ acima do teto de 500/sync" : ""}"
end
puts "BF"
puts "BF   já na central: #{ch.inbox.conversations.count} conversas / #{ch.inbox.messages.count} mensagens"
imap.logout
' 2>/dev/null | sed -n 's/^BF //p'
  exit 0
fi

DIAS="${1:-30}"
if ! printf '%s' "$DIAS" | grep -qE '^[0-9]+$'; then
  echo "[backfill] ERRO: '${DIAS}' não é um número de dias. Uso: backfill-email.sh [dias|--contar]"
  exit 1
fi

echo "[backfill] importando os últimos ${DIAS} dia(s) da caixa para a inbox '${INBOX}'…"
echo "[backfill] (idempotente — o que já está na central não duplica)"

DIAS="$DIAS" $COMPOSE exec -T -e BACKFILL_DIAS="$DIAS" chatwoot-web bundle exec rails runner '
dias = ENV.fetch("BACKFILL_DIAS").to_i
ch   = Inbox.find_by(name: ENV.fetch("INBOX_EMAIL_NOME", "E-mail")).channel
raise "inbox de e-mail não encontrada" if ch.nil?
raise "OAuth não concluído — rode: bash scripts/conectar-gmail.sh" unless ch.provider == "google" && ch.imap_enabled

antes_c = ch.inbox.conversations.count
antes_m = ch.inbox.messages.count
puts "BF antes:  #{antes_c} conversas / #{antes_m} mensagens"

Inboxes::FetchImapEmailsJob.perform_now(ch, dias)

ch.inbox.reload
depois_c = ch.inbox.conversations.count
depois_m = ch.inbox.messages.count
puts "BF depois: #{depois_c} conversas / #{depois_m} mensagens"
puts "BF novas:  +#{depois_c - antes_c} conversas / +#{depois_m - antes_m} mensagens"
puts "BF"
puts "BF ⚠️ e-mail ARQUIVADO no Gmail não vem: o Chatwoot lê só a pasta INBOX."
' 2>/dev/null | sed -n 's/^BF //p'

echo
echo "  Confira: bash scripts/verificar-canal-email.sh"
