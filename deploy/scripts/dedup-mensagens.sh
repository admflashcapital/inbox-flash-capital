#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# dedup-mensagens.sh — idempotência do espelho (STORY-2.2 / AD-5)
# ═══════════════════════════════════════════════════════════════════
# O AD-5 exige entrega at-least-once com CONSUMIDORES IDEMPOTENTES. Do lado da
# central, ninguém garante isso hoje:
#
#   • a Evolution só deduplica por source_id quando o import por conexão DIRETA
#     no Postgres da central está ligado — e nós o desligamos de propósito
#     (violaria AD-8/AD-9). Ver chatwoot.service.ts:1062 (`isImportHistoryAvailable`).
#   • o Chatwoot NÃO tem índice único em `messages.source_id` (só índice comum),
#     nem validação de unicidade — ele aceita a mesma mensagem duas vezes.
#   • o handler da Evolution processa `notify` E `append` (whatsapp.baileys.
#     service.ts:1166), e `append` é o replay do Baileys ao RECONECTAR — que
#     acontece (o próprio ADR-003 do CRM lista a desconexão como risco aceito).
#
# Consertar na entrada exigiria forkar o Chatwoot (proibido, AD-7) ou abrir o
# banco dele para a Evolution (proibido, AD-9). Então a central limpa depois:
# a mesma mensagem (mesmo `source_id`, mesma conversa) fica só uma vez — a mais
# antiga. O resultado observável é o de um consumidor idempotente.
#
#   --simular   (default) só conta as duplicatas. Não apaga nada.
#   --executar  apaga, mantendo a primeira ocorrência.
#
# Em produção, agende junto do backup (ex.: de hora em hora).
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
COMPOSE="docker compose -f ${RAIZ}/deploy/docker-compose.yml --env-file ${ENV_FILE}"

MODO="${1:---simular}"
case "$MODO" in
  --simular)  APAGAR="false" ;;
  --executar) APAGAR="true"  ;;
  *) echo "uso: dedup-mensagens.sh [--simular | --executar]" >&2; exit 1 ;;
esac

echo "[dedup] procurando mensagens repetidas (mesmo source_id na mesma conversa) — modo: ${MODO}"

$COMPOSE exec -T chatwoot-web bundle exec rails runner "
  apagar = ${APAGAR}

  # Só mensagens com source_id (as que vieram de um canal). Mensagem digitada
  # pelo atendente não tem source_id e nunca entra aqui.
  # reorder(nil): o Message tem ordenação default por created_at, e o Postgres
  # recusa um GROUP BY com coluna que não está no agrupamento.
  duplicadas = Message.where.not(source_id: nil)
                      .reorder(nil)
                      .group(:conversation_id, :source_id)
                      .having('count(*) > 1')
                      .count

  if duplicadas.empty?
    puts '[dedup] nenhuma duplicata.'
  else
    total_extra = duplicadas.values.sum { |n| n - 1 }
    puts \"[dedup] #{duplicadas.size} mensagem(ns) duplicada(s); #{total_extra} cópia(s) sobrando.\"

    if apagar
      duplicadas.each_key do |conversation_id, source_id|
        copias = Message.where(conversation_id: conversation_id, source_id: source_id).order(:id).to_a
        copias.drop(1).each(&:destroy!)   # mantém a mais antiga
      end
      puts \"[dedup] #{total_extra} cópia(s) removida(s).\"
    else
      puts '[dedup] SIMULAÇÃO — nada foi apagado. Rode com --executar para limpar.'
    end
  end
"
