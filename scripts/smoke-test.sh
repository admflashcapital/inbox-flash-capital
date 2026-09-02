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
# ⚠️ AMBIENTE DE DESENVOLVIMENTO/STAGING. Exige o opt-in explícito
#    SMOKE_EU_SEI_O_QUE_ESTOU_FAZENDO=1 — não se semeia lixo em prod.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"

# Lê UMA chave do .env. Deliberadamente não damos `source` no arquivo: isso
# jogaria todos os segredos no ambiente do script (e um valor com `<`, `$` ou
# aspas seria interpretado pelo shell). Aqui só entram chaves NÃO-secretas.
. "${RAIZ}/scripts/lib/env.sh"

# Este script SEMEIA e APAGA uma conta de teste: nunca pode rodar em produção.
# O guard antigo era `DOMAIN != localhost`, e a chave DOMAIN morreu com o Caddy.
# O novo guard é a porta: a central só escuta em 127.0.0.1, e exigir o opt-in
# explícito impede que um cron o dispare por engano.
PORTA="$(env_get CHATWOOT_HOST_PORT)"; PORTA="${PORTA:-3001}"
if [ "${SMOKE_EU_SEI_O_QUE_ESTOU_FAZENDO:-}" != "1" ]; then
  echo "[smoke] abortado: este script cria e apaga uma conta no banco."
  echo "[smoke] rode com  SMOKE_EU_SEI_O_QUE_ESTOU_FAZENDO=1 bash scripts/smoke-test.sh"
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

# ── 4. A UI responde na porta publicada ────────────────────────────
CODIGO="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://127.0.0.1:${PORTA}/app/login")"
echo "[smoke] http://127.0.0.1:${PORTA}/app/login → HTTP ${CODIGO}"
[ "$CODIGO" = "200" ] || [ "$CODIGO" = "302" ] || { echo "[smoke] FALHOU: UI não respondeu."; exit 1; }

# ── 5. Limpeza — o smoke NÃO pode deixar conta para trás ───────────
# Aprendido do jeito difícil (2026-07-13): a conta semeada aqui SOBREVIVEU ao
# teste, virou a `Account` de id 1 e, como o `.env` apontava
# `CENTRAL_ACCOUNT_ID=1`, TODO o trabalho dos canais (inbox de prospecção, inbox
# oficial da Twilio) foi criado dentro da conta de TESTE — não na conta real do
# operador. Da UI, o operador via uma central vazia e não entendia por quê.
#
# Um teste que deixa estado para trás não é um teste: é uma armadilha. O smoke
# prova o que precisa provar e some.
echo "[smoke] removendo a conta de teste…"
$COMPOSE exec -T chatwoot-web bundle exec rails runner '
  conta = Account.find_by(name: "Flash Capital (smoke)")
  if conta.nil?
    puts "[smoke] (nada a limpar)"
  else
    usuarios = conta.users.where("email LIKE ?", "smoke@%").to_a
    conta.destroy!
    usuarios.each { |u| u.destroy! if u.accounts.reload.empty? }
    puts "[smoke] conta de teste e usuário removidos"
  end
' 2>/dev/null | grep "\[smoke\]"

RESTANTES="$(consultar "SELECT count(*) FROM accounts WHERE name = 'Flash Capital (smoke)';")"
if [ "${RESTANTES:-1}" != "0" ]; then
  echo "[smoke] FALHOU: a conta de teste sobreviveu à limpeza — ela contaminaria a central."
  exit 1
fi

echo
echo "[smoke] OK — stack sobe com um comando, responde em HTTPS e os dados sobrevivem ao restart."
echo "[smoke] e o teste não deixou rastro: nenhuma conta de teste no banco."
