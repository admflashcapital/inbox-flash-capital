#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# monitorar-canais.sh — a saúde dos canais vira aviso (STORY-6.3)
# ═══════════════════════════════════════════════════════════════════
# Os `verificar-*.sh` provam INVARIANTE DE CONFIGURAÇÃO: o medium é whatsapp, o
# banco é isolado, as 8 definições existem. Nada disso muda sozinho. Este script
# prova outra coisa — LIVENESS —, e por isso é o único que roda no cron.
#
# O que ele existe para pegar, e que hoje falha em SILÊNCIO:
#
#   1. Agendador do Sidekiq parado ⇒ em até 1h a atendente PARA de conseguir
#      responder e-mail. O SMTP de saída usa o access_token cru, e quem o mantém
#      fresco é o job IMAP que roda a cada minuto. A falha acontece DENTRO de um
#      job: nenhum erro chega na tela.
#   2. Túnel caído ⇒ a Twilio recusa o envio da central com 21609 e a atendente
#      não responde pelo WhatsApp (AD-11.1). ⚠️ Um ngrok morto devolve **404**,
#      igual ao 404 legítimo do Rails numa rota POST-only — por isso a prova é
#      `/api` devolver a MESMA versão que o local, não "respondeu alguma coisa".
#   3. Entrega falhando. `Channel::TwilioSms` **não inclui `Reauthorizable`**: o
#      Chatwoot não tem noção de "canal WhatsApp desconectado". A única matéria-
#      prima é `messages.status = 3` + `external_error`.
#
#   --simular   (default) só reporta. Não notifica ninguém.
#   --executar  reporta E posta no sino do Nexus quando o estado MUDA.
#
# Anti-ruído: notifica na TRANSIÇÃO, não a cada tick (estado anterior em
# backups/monitor-canais.estado). Uma queda de 6h gera 2 avisos, não 6.
#
# Uso:
#   scripts/monitorar-canais.sh --simular
#   scripts/monitorar-canais.sh --executar
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

MODO="${1:---simular}"
case "$MODO" in
  --simular|--executar) ;;
  *) echo "uso: monitorar-canais.sh [--simular | --executar]" >&2; exit 1 ;;
esac

PORTA="$(env_get CHATWOOT_HOST_PORT)"; PORTA="${PORTA:-3001}"
PUBLICA="$(env_get CENTRAL_URL_PUBLICA)"
JANELA_FALHAS_H=24
IDADE_MAX_IMAP_S=180
ESTADO_ARQ="${RAIZ}/backups/monitor-canais.estado"

FALHAS=()
SINAIS_OK=0
log() { echo "[monitor] $1"; }
falha() { echo "[monitor] ✗ $1"; FALHAS+=("$1"); }
ok() { echo "[monitor] ✓ $1"; SINAIS_OK=$((SINAIS_OK + 1)); }

# ── 1. A central está de pé e serve ────────────────────────────────
LOCAL="$(curl -s --max-time 10 "http://127.0.0.1:${PORTA}/api" 2>/dev/null)"
VERSAO_LOCAL="$(printf '%s' "$LOCAL" | jq -r '.version // empty' 2>/dev/null)"
if [ -z "$VERSAO_LOCAL" ]; then
  falha "central não responde em 127.0.0.1:${PORTA} — ninguém atende e o espelho se perde (AD-12)"
else
  FILA="$(printf '%s' "$LOCAL" | jq -r '.queue_services // "?"')"
  DADO="$(printf '%s' "$LOCAL" | jq -r '.data_services // "?"')"
  if [ "$FILA" = "ok" ] && [ "$DADO" = "ok" ]; then
    ok "central de pé (v${VERSAO_LOCAL}, Postgres e Redis ok)"
  else
    falha "central responde mas degradada: fila=${FILA} banco=${DADO}"
  fi
fi

# ── 2. A URL pública chega NA NOSSA central ────────────────────────
case "$PUBLICA" in
  ""|http://localhost*|http://127.0.0.1*)
    falha "CENTRAL_URL_PUBLICA está em loopback — a Twilio recusa o envio da central com 21609 e a atendente não responde pelo WhatsApp. Suba o túnel (tuneis-manha.sh do monorepo)" ;;
  *)
    VERSAO_PUB="$(curl -s --max-time 12 "${PUBLICA}/api" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)"
    if [ -z "$VERSAO_PUB" ]; then
      falha "a URL pública não chega na central (túnel caído). Atenção: ngrok morto devolve 404 e engana quem só olha o código HTTP"
    elif [ -n "$VERSAO_LOCAL" ] && [ "$VERSAO_PUB" != "$VERSAO_LOCAL" ]; then
      falha "a URL pública responde outra instalação (v${VERSAO_PUB} ≠ v${VERSAO_LOCAL}) — o túnel aponta para o lugar errado"
    else
      ok "URL pública chega na central (v${VERSAO_PUB}) — sem 21609 no envio pela tela"
    fi ;;
esac

# ── 3/4/5. O que só o Rails sabe ───────────────────────────────────
# Uma chamada só. O `rails runner` polui o stdout com warning de gem, então a
# resposta sai num marcador isolado — mesmo truque do verificar-canal-email.sh.
SONDA="$($COMPOSE exec -T \
  -e JANELA_H="$JANELA_FALHAS_H" \
  chatwoot-web bundle exec rails runner '
    partes = []

    job = Sidekiq::Cron::Job.find("trigger_imap_email_inboxes_job")
    if job.nil?
      partes << "imap=SEM_JOB"
    elsif job.last_enqueue_time.nil?
      partes << "imap=NUNCA"
    else
      partes << "imap=#{(Time.current - job.last_enqueue_time).to_i}"
    end

    canal = Channel::Email.first
    if canal.nil?
      partes << "email=SEM_CANAL"
    else
      partes << "email=#{canal.reauthorization_required? ? "REAUTORIZAR" : "ok"}"
      partes << "email_erros=#{canal.authorization_error_count}"
    end

    janela = ENV.fetch("JANELA_H").to_i.hours.ago
    ruins  = Message.where(status: 3).where("created_at > ?", janela)
    partes << "falhas=#{ruins.count}"
    ultima = ruins.order(:created_at).last
    if ultima
      erro = ultima.content_attributes.to_h["external_error"].to_s.split("\n").first.to_s
      partes << "erro=#{erro.gsub(/[|=]/, " ").strip[0, 120]}"
    end

    puts "MONITOR_RESULT=#{partes.join("|")}"
  ' 2>/dev/null | sed -n 's/^MONITOR_RESULT=//p')"

campo() { printf '%s' "$SONDA" | tr '|' '\n' | sed -n "s/^$1=//p" | head -1; }

if [ -z "$SONDA" ]; then
  falha "não consegui sondar o Rails (central parada ou runner falhando) — os sinais de IMAP e de entrega ficaram cegos"
else
  IMAP="$(campo imap)"
  case "$IMAP" in
    SEM_JOB) falha "o cron do IMAP não está registrado no Sidekiq — a caixa de e-mail parou de ser lida" ;;
    NUNCA)   falha "o cron do IMAP nunca rodou — o agendador do Sidekiq não está de pé" ;;
    *)
      if [ "$IMAP" -gt "$IDADE_MAX_IMAP_S" ] 2>/dev/null; then
        falha "agendador do IMAP parado há ${IMAP}s — em até 1h a atendente PARA de conseguir responder e-mail, sem erro na tela"
      else
        ok "agendador do IMAP vivo (último enfileiramento há ${IMAP}s)"
      fi ;;
  esac

  EMAIL="$(campo email)"
  case "$EMAIL" in
    ok)          ok "canal de e-mail autorizado (0 erro de autorização acumulado)" ;;
    REAUTORIZAR) falha "o canal de e-mail pede reautorização — rode: bash scripts/conectar-gmail.sh --url" ;;
    SEM_CANAL)   falha "não existe Channel::Email — a inbox de e-mail sumiu" ;;
    *)           falha "estado do canal de e-mail desconhecido: ${EMAIL:-vazio}" ;;
  esac

  N_FALHAS="$(campo falhas)"
  if [ "${N_FALHAS:-0}" -gt 0 ] 2>/dev/null; then
    falha "${N_FALHAS} mensagem(ns) não entregue(s) nas últimas ${JANELA_FALHAS_H}h — último erro: $(campo erro)"
  else
    ok "nenhuma entrega falhada nas últimas ${JANELA_FALHAS_H}h"
  fi
fi

# ── 6. O expurgo da LGPD continua agendado ─────────────────────────
if crontab -l 2>/dev/null | grep -q "retencao-conversas.sh"; then
  ok "expurgo LGPD agendado no cron do host"
else
  falha "o cron do expurgo LGPD sumiu — a central passa a guardar conversa de cobrança para sempre"
fi

# ── 7. A VM do WSL está ancorada, ou depende de um terminal aberto? ─
# A VM do WSL2 desliga quando o ÚLTIMO processo dela termina: fechar o terminal
# é desligar o servidor. A tarefa WSL-Always-On do Windows segura isso com um
# `sleep infinity` — mas ela dispara **no logon**, e só. Um `wsl --shutdown` no
# meio do dia derruba a âncora e ela NÃO volta sozinha: a máquina segue de pé
# enquanto houver um terminal aberto e morre silenciosamente quando ele fechar.
# Medido em 2026-09-04: foi exatamente o que aconteceu, e só apareceu porque
# alguém foi olhar. Este sinal é o "alguém foi olhar" virando automático.
#
# Ele NÃO cobre a VM já desligada — aí ninguém roda nada, inclusive isto. Cobre
# a janela em que ela está viva e frágil, que é quando ainda dá para agir.
if pgrep -x sleep >/dev/null 2>&1; then
  ok "VM do WSL ancorada (a âncora do WSL-Always-On está viva)"
else
  falha "a VM do WSL NÃO está ancorada: ela morre quando o último terminal fechar, e leva os 25 containers e todos os crons junto. No PowerShell: Start-ScheduledTask -TaskName 'WSL-Always-On' — ver docs/runbook-wsl-autostart.md"
fi

# ── Veredito, e o aviso só quando o estado MUDA ────────────────────
echo
if [ "${#FALHAS[@]}" -eq 0 ]; then
  ESTADO="ok"
  RESUMO="Todos os sinais da central de atendimento voltaram ao normal."
  TIPO="success"
  TITULO="Central de atendimento normalizada"
  echo "[monitor] ✅ ${SINAIS_OK} sinais, nenhuma falha."
else
  ESTADO="$(printf '%s\n' "${FALHAS[@]}" | cksum | cut -d' ' -f1)"
  RESUMO="$(printf '%s\n' "${FALHAS[@]}" | sed 's/^/• /')"
  TIPO="error"
  TITULO="Central de atendimento: ${#FALHAS[@]} sinal(is) em falha"
  echo "[monitor] ❌ ${#FALHAS[@]} falha(s)."
fi

if [ "$MODO" = "--simular" ]; then
  echo "[monitor] SIMULAÇÃO — ninguém foi notificado. Rode com --executar no cron."
  [ "${#FALHAS[@]}" -eq 0 ] && exit 0 || exit 1
fi

ANTERIOR="$(cat "$ESTADO_ARQ" 2>/dev/null || echo "")"
mkdir -p "$(dirname "$ESTADO_ARQ")"
printf '%s' "$ESTADO" > "$ESTADO_ARQ"

if [ "$ESTADO" = "$ANTERIOR" ]; then
  echo "[monitor] estado inalterado — não repito o aviso."
  [ "${#FALHAS[@]}" -eq 0 ] && exit 0 || exit 1
fi
if [ "$ESTADO" = "ok" ] && [ -z "$ANTERIOR" ]; then
  echo "[monitor] primeira execução e está tudo verde — nada a avisar."
  exit 0
fi

URL="$(env_get MONITOR_URL)"
TOKEN="$(env_get MONITOR_TOKEN)"
if [ -z "$URL" ] || [ -z "$TOKEN" ]; then
  echo "[monitor] ⚠ MONITOR_URL/MONITOR_TOKEN ausentes no .env — o aviso não foi postado." >&2
  exit 1
fi

CORPO="$(mktemp)"
trap 'rm -f "$CORPO"' EXIT
jq -n --arg t "$TITULO" --arg m "$RESUMO" --arg tipo "$TIPO" \
  '{title: $t, message: $m, type: $tipo, metadata: {origem: "inbox-flash-capital/monitorar-canais.sh"}}' \
  > "$CORPO"

# O token vai por --config (stdin), nunca em argv: `ps` é lugar público.
COD="$(printf 'header = "X-Monitor-Token: %s"\nurl = "%s/notificacoes/alerta"\n' "$TOKEN" "$URL" \
  | curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
      -X POST -H 'Content-Type: application/json' --data-binary "@${CORPO}" --config - 2>/dev/null)"

case "$COD" in
  201) echo "[monitor] aviso postado no sino do Nexus (${TIPO})." ;;
  401) echo "[monitor] ⚠ o painel recusou o token (401) — MONITOR_TOKEN dos dois lados não bate." >&2 ;;
  503) echo "[monitor] ⚠ o painel não tem perfil nexus para receber o aviso (503)." >&2 ;;
  *)   echo "[monitor] ⚠ não consegui postar o aviso (HTTP ${COD:-sem resposta}). O painel está no ar?" >&2 ;;
esac

[ "${#FALHAS[@]}" -eq 0 ] && exit 0 || exit 1
