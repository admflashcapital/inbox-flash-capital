#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# restore.sh — restore da central (STORY-1.4 / FR-3)
# ═══════════════════════════════════════════════════════════════════
# Dois modos:
#
#   restore.sh --verificar     ENSAIO (default seguro). Restaura o último
#                              backup num ambiente LIMPO e efêmero (container
#                              Postgres descartável + diretório temporário),
#                              confere que conversas/contatos/anexos vieram
#                              inteiros e destrói tudo. NÃO toca na produção.
#                              É a prova exigida pelo gate do EPIC-1.
#
#   restore.sh --producao      RESTORE DE VERDADE, destrutivo: derruba a
#                              stack, APAGA o banco e o volume de anexos
#                              atuais e recompõe a partir do backup.
#                              Pede confirmação explícita.
#
# Um backup nunca testado não é backup — é esperança. O `--verificar` existe
# para rodar sem medo (semanalmente pelo central-restore-check.timer, ou à mão),
# porque não encosta em prod.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
PROJETO="inbox-flash-capital"
IMAGEM_PG="pgvector/pgvector:0.8.5-pg16"   # a MESMA do compose

# Lê UMA chave do .env (só chaves não-secretas). Ver comentário em backup.sh.
. "${RAIZ}/scripts/lib/env.sh"

BACKUP_DIR="${BACKUP_DIR:-$(env_get BACKUP_DIR)}"
BACKUP_DIR="${BACKUP_DIR:-${RAIZ}/backups}"
DB="$(env_get POSTGRES_DATABASE)"
DB_USER="$(env_get POSTGRES_USERNAME)"
[ -n "$DB" ] && [ -n "$DB_USER" ] || { echo "[restore] ERRO: POSTGRES_DATABASE/POSTGRES_USERNAME ausentes no .env"; exit 1; }
MODO="${1:---verificar}"

ultimo() {  # último arquivo do prefixo, por mtime
  # shellcheck disable=SC2012
  ls -1t "${BACKUP_DIR}/$1"_*.gz 2>/dev/null | head -1
}

DUMP="$(ultimo db)"
ANEXOS="$(ultimo storage)"
[ -n "$DUMP" ]   || { echo "[restore] ERRO: nenhum dump em ${BACKUP_DIR}"; exit 1; }
[ -n "$ANEXOS" ] || { echo "[restore] ERRO: nenhum tar de anexos em ${BACKUP_DIR}"; exit 1; }
echo "[restore] dump   : $(basename "$DUMP")"
echo "[restore] anexos : $(basename "$ANEXOS")"

# ═══ Modo ENSAIO — ambiente limpo, efêmero, isolado da produção ═════
if [ "$MODO" = "--verificar" ]; then
  CONTAINER="inbox-restore-check-$$"
  TMPDIR_ANEXOS="$(mktemp -d)"
  SENHA_EFEMERA="$(openssl rand -hex 16)"   # vive só neste container descartável
  limpar() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -rf "$TMPDIR_ANEXOS"
  }
  trap limpar EXIT

  echo "[restore] subindo Postgres limpo e efêmero (${IMAGEM_PG})…"
  docker run -d --name "$CONTAINER" \
    -e POSTGRES_PASSWORD="$SENHA_EFEMERA" \
    -e POSTGRES_DB=postgres \
    "$IMAGEM_PG" \
    postgres -c shared_preload_libraries=pg_stat_statements >/dev/null

  for _ in $(seq 1 30); do
    docker exec "$CONTAINER" pg_isready -U postgres -d postgres >/dev/null 2>&1 && break
    sleep 2
  done

  # Recria o esqueleto que o init-db cria em produção (mesmo dono, mesmas extensões).
  docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<-EOSQL >/dev/null
	CREATE USER ${DB_USER};
	CREATE DATABASE ${DB} OWNER ${DB_USER};
	EOSQL
  docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d "$DB" <<-EOSQL >/dev/null
	CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
	CREATE EXTENSION IF NOT EXISTS "pg_trgm";
	CREATE EXTENSION IF NOT EXISTS "pgcrypto";
	CREATE EXTENSION IF NOT EXISTS "vector";
	EOSQL

  echo "[restore] restaurando o dump…"
  gunzip -c "$DUMP" | docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres -d "$DB" >/dev/null

  echo "[restore] extraindo os anexos…"
  tar xzf "$ANEXOS" -C "$TMPDIR_ANEXOS"

  # ── Conferência ──────────────────────────────────────────────────
  contar() { docker exec "$CONTAINER" psql -tAX -U postgres -d "$DB" -c "$1" | tr -d '[:space:]'; }
  CONVERSAS="$(contar 'SELECT count(*) FROM conversations;')"
  MENSAGENS="$(contar 'SELECT count(*) FROM messages;')"
  CONTATOS="$(contar 'SELECT count(*) FROM contacts;')"
  INBOXES="$(contar 'SELECT count(*) FROM inboxes;')"
  BLOBS="$(contar 'SELECT count(*) FROM active_storage_blobs;')"
  ARQUIVOS="$(find "$TMPDIR_ANEXOS" -type f | wc -l | tr -d ' ')"

  echo
  echo "  ── restore verificado no ambiente limpo ──"
  printf "  inboxes ....... %s\n  contatos ...... %s\n  conversas ..... %s\n  mensagens ..... %s\n" \
    "$INBOXES" "$CONTATOS" "$CONVERSAS" "$MENSAGENS"
  printf "  anexos (DB) ... %s\n  anexos (disco). %s arquivos\n\n" "$BLOBS" "$ARQUIVOS"

  # O schema TEM de estar íntegro. Volume zero de conversa é legítimo numa
  # central recém-instalada — o que não pode é a tabela não existir.
  [ -n "$CONVERSAS" ] || { echo "[restore] FALHOU: schema incompleto (sem tabela conversations)"; exit 1; }

  # Cada blob registrado no banco precisa ter o arquivo correspondente no tar.
  # Blob sem arquivo = conversa restaurada com anexo quebrado.
  if [ "$BLOBS" -gt 0 ] && [ "$ARQUIVOS" -lt "$BLOBS" ]; then
    echo "[restore] FALHOU: ${BLOBS} anexos no banco, mas só ${ARQUIVOS} arquivos no backup."
    exit 1
  fi

  echo "[restore] OK — banco e anexos recompostos num ambiente limpo. Ambiente de teste destruído."
  exit 0
fi

# ═══ Modo PRODUÇÃO — destrutivo ════════════════════════════════════
if [ "$MODO" = "--producao" ]; then
  echo
  echo "  ⚠️  RESTORE DESTRUTIVO. Isto APAGA o banco e os anexos ATUAIS da central"
  echo "     e os substitui pelo backup acima. Não há desfazer."
  read -r -p "  Digite RESTAURAR para confirmar: " confirma
  [ "$confirma" = "RESTAURAR" ] || { echo "[restore] abortado."; exit 1; }

  echo "[restore] derrubando a stack e apagando os volumes de dados…"
  $COMPOSE down
  docker volume rm -f "${PROJETO}_postgres_data" "${PROJETO}_storage_data" >/dev/null

  echo "[restore] subindo só o Postgres (o init-db recria usuário, banco e extensões)…"
  $COMPOSE up -d --wait postgres

  echo "[restore] restaurando o dump…"
  gunzip -c "$DUMP" | $COMPOSE exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -d "$DB" >/dev/null

  echo "[restore] restaurando os anexos no volume…"
  docker run --rm \
    -v "${PROJETO}_storage_data:/storage" \
    -v "${BACKUP_DIR}:/backup:ro" \
    alpine:3.21 tar xzf "/backup/$(basename "$ANEXOS")" -C /storage

  echo "[restore] subindo a stack completa…"
  $COMPOSE up -d --wait

  echo "[restore] OK — central restaurada. Confira a UI antes de liberar o atendimento."
  exit 0
fi

echo "uso: restore.sh [--verificar | --producao]" >&2
exit 1
