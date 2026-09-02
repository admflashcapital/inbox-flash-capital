#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# backup.sh — backup da central (STORY-1.4 / FR-3)
# ═══════════════════════════════════════════════════════════════════
# Copia as DUAS metades da central — perder qualquer uma quebra o restore:
#   1. banco (chatwoot_production) .... conversas, contatos, labels, config
#   2. volume storage_data ............ ANEXOS das conversas (PDF, imagem)
# Um dump sem os anexos restaura conversas com anexo quebrado. Por isso os
# dois artefatos são gerados no mesmo par, com o mesmo timestamp.
#
# Uso (cron do host, ex.: 3h da manhã):
#   cd /caminho/inbox-flash-capital && scripts/backup.sh
#
# Retenção: 7 diários + 4 semanais (domingo → sufixo _weekly), por artefato.
# ⚠️ Os arquivos contêm PII (CPF/CNPJ, conteúdo de conversa): diretório fora
#    do repo em produção, permissão restrita, e criptografe antes de mandar
#    para qualquer storage remoto. Ver docs/runbook-backup.md.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
PROJETO="inbox-flash-capital"   # = `name:` do compose (prefixo dos volumes)

# Lê UMA chave do .env. Não damos `source`: nenhum segredo precisa entrar no
# ambiente deste script — o pg_dump roda dentro do container, pelo socket local.
. "${RAIZ}/scripts/lib/env.sh"

BACKUP_DIR="${BACKUP_DIR:-$(env_get BACKUP_DIR)}"
BACKUP_DIR="${BACKUP_DIR:-${RAIZ}/backups}"
DB="$(env_get POSTGRES_DATABASE)"
DB_USER="$(env_get POSTGRES_USERNAME)"
[ -n "$DB" ] && [ -n "$DB_USER" ] || { echo "[backup] ERRO: POSTGRES_DATABASE/POSTGRES_USERNAME ausentes no .env"; exit 1; }

DATA="$(date -u +%Y-%m-%d)"
SUFIXO=""
[ "$(date -u +%u)" = "7" ] && SUFIXO="_weekly"   # 7 = domingo

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# ── 1. Banco ───────────────────────────────────────────────────────
# pg_dump roda DENTRO do container (tem o cliente e o socket local);
# a senha não trafega em linha de comando.
DUMP="${BACKUP_DIR}/db_${DATA}${SUFIXO}.sql.gz"
echo "[backup] banco ${DB} → ${DUMP}"
$COMPOSE exec -T postgres pg_dump -U "$DB_USER" -d "$DB" | gzip > "$DUMP"

# ── 2. Anexos (volume storage_data) ────────────────────────────────
ANEXOS="${BACKUP_DIR}/storage_${DATA}${SUFIXO}.tar.gz"
echo "[backup] anexos (volume ${PROJETO}_storage_data) → ${ANEXOS}"
# O tar roda como root dentro do container (para ler todo o volume), mas o
# arquivo resultante é devolvido ao dono do host — senão o chmod abaixo falha
# e o backup fica com um artefato root-only na pasta do operador.
docker run --rm \
  -v "${PROJETO}_storage_data:/storage:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine:3.21 sh -c "tar czf '/backup/$(basename "$ANEXOS")' -C /storage . && chown $(id -u):$(id -g) '/backup/$(basename "$ANEXOS")'"

chmod 600 "$DUMP" "$ANEXOS"

# ── 3. Retenção: 7 diários + 4 semanais, por artefato ──────────────
# `find` e não `ls`: com `set -e`, um `ls` sem match retorna 2 e derruba o
# script — e um backup que aborta na poda é um backup que ninguém percebe
# que parou de rodar. O glob de data separa diário de semanal pelo nome.
podar() {
  local padrao="$1" manter="$2"
  find "$BACKUP_DIR" -maxdepth 1 -type f -name "$padrao" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | tail -n +$((manter + 1)) | cut -d' ' -f2- | while read -r velho; do
        rm -f "$velho"
        echo "[backup] removido (retenção): $(basename "$velho")"
      done
}
podar 'db_????-??-??.sql.gz'              7   # diários
podar 'storage_????-??-??.tar.gz'         7
podar 'db_????-??-??_weekly.sql.gz'       4   # semanais (domingo)
podar 'storage_????-??-??_weekly.tar.gz'  4

echo "[backup] OK — ${DATA}${SUFIXO:+ (semanal)}"
echo "[backup] valide o par com: scripts/restore.sh --verificar"
