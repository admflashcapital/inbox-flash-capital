#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# retencao-conversas.sh — expurgo de conversas antigas (STORY-1.4 / LGPD)
# ═══════════════════════════════════════════════════════════════════
# O Chatwoot CE não tem expurgo nativo por idade: sem isto, a central guarda
# conversa de cliente (com CPF/CNPJ, valor em aberto, inadimplência) para
# sempre — o oposto da minimização exigida pela LGPD.
#
# Apaga conversas RESOLVIDAS mais velhas que RETENCAO_CONVERSAS_DIAS, junto
# com suas mensagens e anexos. Conversas abertas/pendentes nunca são tocadas.
#
#   --simular   (default) só CONTA o que seria apagado. Não apaga nada.
#   --executar  apaga de verdade.
#
# A TENSÃO que definiu o prazo, para quem for revisá-lo: a central guarda a
# conversa de COBRANÇA. Apagar cedo demais destrói a prova da negociação de uma
# dívida; tarde demais viola a minimização da LGPD. O default (1825 dias = 5
# anos) segue a prescrição civil comum de dívida, foi APROVADO por escrito pelo
# operador em 2026-09-02, e roda pelo central-retencao.timer (domingo 12:00,
# com Persistent=true, que recupera a semana em que a máquina ficou desligada).
# Procedimento completo, com o direito de exclusão do titular: docs/runbook-lgpd.md.
#
# Uso:
#   scripts/retencao-conversas.sh --simular
#   scripts/retencao-conversas.sh --executar
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

DIAS="$(env_get RETENCAO_CONVERSAS_DIAS)"
DIAS="${DIAS:-1825}"
MODO="${1:---simular}"

case "$MODO" in
  --simular)  APAGAR="false" ;;
  --executar) APAGAR="true"  ;;
  *) echo "uso: retencao-conversas.sh [--simular | --executar]" >&2; exit 1 ;;
esac

echo "[retencao] política: apagar conversas RESOLVIDAS com mais de ${DIAS} dias (modo: ${MODO})"

$COMPOSE exec -T chatwoot-web bundle exec rails runner "
  dias   = ${DIAS}
  apagar = ${APAGAR}
  corte  = dias.days.ago

  # status 1 = resolved. Aberta ou pendente jamais é apagada por idade.
  alvo = Conversation.where(status: 1).where('last_activity_at < ?', corte)
  total = alvo.count
  puts \"[retencao] conversas resolvidas anteriores a #{corte.to_date}: #{total}\"

  if !apagar
    puts '[retencao] SIMULAÇÃO — nada foi apagado. Rode com --executar para aplicar.'
  elsif total.zero?
    puts '[retencao] nada a apagar.'
  else
    # destroy_all (não delete_all): precisa disparar os callbacks que removem
    # mensagens e ANEXOS do storage. delete_all deixaria arquivo órfão no volume.
    alvo.find_each(&:destroy!)
    puts \"[retencao] #{total} conversas apagadas (mensagens e anexos junto).\"
  end
"
