#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# smoke-test.sh — prova viva dos critérios do EPIC-1 (STORY-1.1 / 1.4)
# ═══════════════════════════════════════════════════════════════════
# Não é pytest: o EPIC-1 é infra, e o "verde" aqui é o critério de aceite
# verificado ao vivo. Este script é essa verificação, reproduzível:
#
#   1. semeia dados reais na central (conta, inbox, contato, conversa,
#      mensagem e um ANEXO — que exercita o volume de storage)
#   2. reinicia os containers
#   3. confere que tudo sobreviveu ao restart (critério da STORY-1.1)
#
# Os dados semeados também alimentam o `restore.sh --verificar` (STORY-1.4):
# sem conversa e sem anexo, o teste de restore não prova nada.
#
# ⚠️ AMBIENTE DE DESENVOLVIMENTO/STAGING. Em produção este script não roda
#    (aborta se DOMAIN não for localhost) — não se semeia lixo em prod.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
COMPOSE="docker compose -f ${RAIZ}/deploy/docker-compose.yml --env-file ${ENV_FILE}"

# Lê UMA chave do .env. Deliberadamente não damos `source` no arquivo: isso
# jogaria todos os segredos no ambiente do script (e um valor com `<`, `$` ou
# aspas seria interpretado pelo shell). Aqui só entram chaves NÃO-secretas.
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/^"\(.*\)"$/\1/'; }

DOMAIN="$(env_get DOMAIN)"
if [ "${DOMAIN:-}" != "localhost" ]; then
  echo "[smoke] abortado: DOMAIN=${DOMAIN} não é 'localhost'. Este script só roda em dev/staging."
  exit 1
fi

DB="$(env_get POSTGRES_DATABASE)"
consultar() { $COMPOSE exec -T postgres psql -tAX -U postgres -d "$DB" -c "$1" | tr -d '[:space:]'; }

# ── 1. Semeia (idempotente: re-rodar não duplica) ──────────────────
echo "[smoke] semeando conta, inbox, contato, conversa, mensagem e anexo…"
$COMPOSE exec -T chatwoot-web bundle exec rails runner '
  conta = Account.find_or_create_by!(name: "Flash Capital (smoke)")

  usuario = User.find_by(email: "smoke@flashcapital.local") || begin
    # Senha aleatória, nunca impressa. O sufixo satisfaz a política do Chatwoot
    # (exige ao menos 1 maiúscula e 1 caractere especial); hex puro é rejeitado.
    senha = "#{SecureRandom.hex(16)}A!"
    u = User.new(name: "Smoke Test", email: "smoke@flashcapital.local",
                 password: senha, type: "SuperAdmin")
    u.skip_confirmation!
    u.save!
    u
  end
  AccountUser.find_or_create_by!(account: conta, user: usuario) { |au| au.role = "administrator" }

  inbox = Inbox.find_by(account: conta, name: "Smoke Inbox") || begin
    canal = Channel::Api.create!(account: conta, webhook_url: "")
    Inbox.create!(account: conta, name: "Smoke Inbox", channel: canal)
  end

  contato = Contact.find_or_create_by!(account: conta, phone_number: "+5531999998888") do |c|
    c.name = "Cedente de Teste"
  end
  ci = ContactInbox.find_or_create_by!(contact: contato, inbox: inbox) { |x| x.source_id = SecureRandom.uuid }

  conversa = Conversation.find_by(account: conta, inbox: inbox, contact: contato) ||
             Conversation.create!(account: conta, inbox: inbox, contact: contato, contact_inbox: ci)

  if conversa.messages.empty?
    msg = Message.new(account: conta, inbox: inbox, conversation: conversa,
                      message_type: :incoming, content: "Mensagem de smoke test — EPIC-1")
    # O anexo é o ponto: exercita o ActiveStorage no volume storage_data.
    anexo = msg.attachments.new(account_id: conta.id, file_type: :file)
    anexo.file.attach(io: StringIO.new("nota fiscal de teste"), filename: "nf-teste.txt",
                      content_type: "text/plain")
    msg.save!
  end
  puts "[smoke] semeadura ok"
'

ANTES_CONVERSAS="$(consultar 'SELECT count(*) FROM conversations;')"
ANTES_MENSAGENS="$(consultar 'SELECT count(*) FROM messages;')"
ANTES_ANEXOS="$(consultar 'SELECT count(*) FROM attachments;')"
ANTES_BLOBS="$(consultar 'SELECT count(*) FROM active_storage_blobs;')"
echo "[smoke] antes do restart: conversas=${ANTES_CONVERSAS} mensagens=${ANTES_MENSAGENS} anexos=${ANTES_ANEXOS} blobs=${ANTES_BLOBS}"

[ "$ANTES_ANEXOS" -ge 1 ] || { echo "[smoke] FALHOU: nenhum anexo foi criado — o teste de persistência ficaria cego."; exit 1; }

# ── 2. Restart (o critério da STORY-1.1) ───────────────────────────
echo "[smoke] reiniciando os containers…"
$COMPOSE restart >/dev/null
$COMPOSE up -d --wait >/dev/null

# ── 3. Confere que sobreviveu ──────────────────────────────────────
DEPOIS_CONVERSAS="$(consultar 'SELECT count(*) FROM conversations;')"
DEPOIS_MENSAGENS="$(consultar 'SELECT count(*) FROM messages;')"
DEPOIS_ANEXOS="$(consultar 'SELECT count(*) FROM attachments;')"
echo "[smoke] depois do restart: conversas=${DEPOIS_CONVERSAS} mensagens=${DEPOIS_MENSAGENS} anexos=${DEPOIS_ANEXOS}"

# O arquivo do anexo tem de continuar no volume — não basta a linha no banco.
ARQUIVOS="$($COMPOSE exec -T chatwoot-web sh -c 'find /app/storage -type f | wc -l' | tr -d '[:space:]')"
echo "[smoke] arquivos no volume de anexos: ${ARQUIVOS}"

falhou=0
[ "$DEPOIS_CONVERSAS" = "$ANTES_CONVERSAS" ] || { echo "[smoke] FALHOU: conversas não persistiram."; falhou=1; }
[ "$DEPOIS_MENSAGENS" = "$ANTES_MENSAGENS" ] || { echo "[smoke] FALHOU: mensagens não persistiram."; falhou=1; }
[ "$DEPOIS_ANEXOS"    = "$ANTES_ANEXOS"    ] || { echo "[smoke] FALHOU: anexos não persistiram."; falhou=1; }
[ "$ARQUIVOS" -ge 1 ] || { echo "[smoke] FALHOU: volume de anexos vazio após restart."; falhou=1; }
[ "$falhou" = 0 ] || exit 1

# ── 4. A UI responde em HTTPS pelo Caddy ───────────────────────────
CODIGO="$(curl -sk -o /dev/null -w '%{http_code}' --resolve "inbox.${DOMAIN}:443:127.0.0.1" "https://inbox.${DOMAIN}/app/login")"
echo "[smoke] https://inbox.${DOMAIN}/app/login → HTTP ${CODIGO}"
[ "$CODIGO" = "200" ] || [ "$CODIGO" = "302" ] || { echo "[smoke] FALHOU: UI não respondeu em HTTPS."; exit 1; }

echo
echo "[smoke] OK — stack sobe com um comando, responde em HTTPS e os dados sobrevivem ao restart."
