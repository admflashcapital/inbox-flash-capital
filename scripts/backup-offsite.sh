#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# backup-offsite.sh — a cópia que sobrevive à morte da máquina
# ═══════════════════════════════════════════════════════════════════
# O `backup.sh` grava só em disco local. Host morre = backup morre junto.
# Este script cifra os artefatos e os espelha num bucket S3-compatível
# (Supabase Storage).
#
# ── Por que a credencial NÃO é a `service_role` ────────────────────
# O `verificar-invariantes.sh` proíbe `SUPABASE_*` no .env desta central
# (AD-9, sem cross-DB), e não é burocracia: a `service_role` fura RLS no
# projeto INTEIRO, então guardá-la aqui daria à central leitura e escrita
# no banco de domínio. A chave usada aqui é a de **S3 Access Keys**
# (Supabase → Storage → S3 Access Keys), escopada a storage e incapaz de
# tocar o banco. Por isso o prefixo é BACKUP_S3_, não SUPABASE_.
#
# ── Por que cifrar ANTES de subir ──────────────────────────────────
# O dump tem CPF/CNPJ, valor em aberto e conteúdo de conversa — e ainda o
# `refresh_token` do Gmail em TEXTO PURO (o Chatwoot não criptografa o
# `provider_config`). Subir isso em claro moveria a base de PII mais densa
# da Flash para um bucket de terceiro.
# ⚠️ A frase secreta mora no `.env`, na mesma máquina que o backup protege.
#    Se a máquina morrer e a frase só existir nela, o offsite é ilegível.
#    GUARDE-A NO GERENCIADOR DE SENHAS. Está dito no runbook e no .env.example.
#
# ── Por que `sync` e não `copy` ────────────────────────────────────
# O remoto vira espelho do BACKUP_DIR, que o `backup.sh` já poda em 7
# diários + 4 semanais. A retenção offsite sai de graça e idêntica — sem
# uma segunda política para divergir em silêncio. E um dia que falhou é
# recuperado na rodada seguinte, porque o sync olha o conjunto, não o dia.
#
# Uso:
#   bash scripts/backup-offsite.sh --simular    # não sobe nada (default seguro)
#   bash scripts/backup-offsite.sh --executar   # cifra e sobe
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
. "${RAIZ}/scripts/lib/env.sh"

MODO="simular"
case "${1:-}" in
  --executar) MODO="executar" ;;
  --simular|"") MODO="simular" ;;
  *) echo "[offsite] uso: $0 [--simular|--executar]"; exit 2 ;;
esac

log() { echo "[offsite] $*"; }

BACKUP_DIR="${BACKUP_DIR:-$(env_get BACKUP_DIR)}"
BACKUP_DIR="${BACKUP_DIR:-${RAIZ}/backups}"

ENDPOINT="$(env_get BACKUP_S3_ENDPOINT)"
REGIAO="$(env_get BACKUP_S3_REGION)"
BUCKET="$(env_get BACKUP_S3_BUCKET)"
CHAVE_ID="$(env_get BACKUP_S3_ACCESS_KEY_ID)"
CHAVE_SEC="$(env_get BACKUP_S3_SECRET_ACCESS_KEY)"
FRASE="$(env_get BACKUP_OFFSITE_PASSPHRASE)"

# ── 0. Pré-condições. Não configurado NÃO é falha: é opt-in. ───────
FALTAM=""
for par in ENDPOINT:BACKUP_S3_ENDPOINT BUCKET:BACKUP_S3_BUCKET \
           CHAVE_ID:BACKUP_S3_ACCESS_KEY_ID CHAVE_SEC:BACKUP_S3_SECRET_ACCESS_KEY \
           FRASE:BACKUP_OFFSITE_PASSPHRASE; do
  var="${par%%:*}"; nome="${par##*:}"
  [ -n "${!var}" ] || FALTAM="${FALTAM} ${nome}"
done
if [ -n "$FALTAM" ]; then
  log "não configurado — faltam no .env:${FALTAM}"
  log "o backup LOCAL segue funcionando; só a cópia offsite está desligada."
  log "como ligar: docs/runbook-backup.md §Cópia offsite"
  exit 0
fi

# `gpg` é o que cifra. Ausente = falha, não silêncio: um offsite que sobe
# em claro seria pior do que não subir.
command -v gpg >/dev/null 2>&1 || { log "ERRO: gpg não instalado — não subo nada em claro."; exit 1; }
# Resolver o rclone por CAMINHO, não só por `command -v`. O cron roda com um
# PATH mínimo (tipicamente /usr/bin:/bin) e NÃO tem ~/.local/bin — então um
# rclone instalado sem sudo funciona no terminal e some no cron. Esse é
# exatamente o tipo de falha que só aparece semanas depois, no dia do incidente.
RCLONE=""
for c in "$(command -v rclone 2>/dev/null)" "$HOME/.local/bin/rclone" \
         /usr/local/bin/rclone /usr/bin/rclone /snap/bin/rclone; do
  [ -n "$c" ] && [ -x "$c" ] && { RCLONE="$c"; break; }
done
if [ -z "$RCLONE" ]; then
  log "ERRO: rclone não encontrado. É o cliente S3 deste fluxo."
  log "  sem sudo : curl -fsSL -o /tmp/r.zip https://downloads.rclone.org/rclone-current-linux-amd64.zip \\"
  log "             && unzip -oq /tmp/r.zip -d /tmp && install -m0755 /tmp/rclone-v*/rclone ~/.local/bin/rclone"
  log "  com sudo : curl https://rclone.org/install.sh | sudo bash"
  exit 1
fi

ARTEFATOS=$(find "$BACKUP_DIR" -maxdepth 1 -type f \
              \( -name 'db_*.sql.gz' -o -name 'storage_*.tar.gz' \) | wc -l)
if [ "$ARTEFATOS" -eq 0 ]; then
  log "ERRO: nenhum artefato em ${BACKUP_DIR} — rode scripts/backup.sh antes."
  exit 1
fi
log "${ARTEFATOS} artefato(s) locais em ${BACKUP_DIR}"

# ── 1. Cifrar num staging descartável ──────────────────────────────
# `mktemp -d` sob o próprio BACKUP_DIR: mesmo disco (o mv/cp não cruza
# filesystem) e mesma permissão restrita. `trap` apaga mesmo em erro —
# staging com PII em claro sobrevivendo a uma falha é vazamento.
STAGING="$(mktemp -d "${BACKUP_DIR}/.offsite.XXXXXX")"
chmod 700 "$STAGING"
FRASE_FILE="${STAGING}/.p"
( umask 077; printf '%s' "$FRASE" > "$FRASE_FILE" )
trap 'rm -rf "$STAGING"' EXIT INT TERM

CIFRADOS=0
while IFS= read -r arq; do
  base="$(basename "$arq")"
  # `--batch --yes` para não perguntar nada no cron; a frase vai por ARQUIVO,
  # nunca em argv — argv é legível por qualquer usuário via /proc.
  gpg --symmetric --cipher-algo AES256 --batch --yes --quiet \
      --passphrase-file "$FRASE_FILE" --pinentry-mode loopback \
      --output "${STAGING}/${base}.gpg" "$arq"
  CIFRADOS=$((CIFRADOS + 1))
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db_*.sql.gz' -o -name 'storage_*.tar.gz' \))
rm -f "$FRASE_FILE"
log "${CIFRADOS} artefato(s) cifrados (AES256) no staging"

# ── 2. Espelhar no bucket ──────────────────────────────────────────
# Config do rclone por VARIÁVEL, não por arquivo: nenhum segredo é gravado
# em ~/.config/rclone/rclone.conf, que ninguém lembraria de proteger.
export RCLONE_CONFIG_OFFSITE_TYPE=s3
export RCLONE_CONFIG_OFFSITE_PROVIDER=Other
export RCLONE_CONFIG_OFFSITE_ENDPOINT="$ENDPOINT"
export RCLONE_CONFIG_OFFSITE_REGION="${REGIAO:-auto}"
export RCLONE_CONFIG_OFFSITE_ACCESS_KEY_ID="$CHAVE_ID"
export RCLONE_CONFIG_OFFSITE_SECRET_ACCESS_KEY="$CHAVE_SEC"
export RCLONE_CONFIG_OFFSITE_NO_CHECK_BUCKET=true

DESTINO="offsite:${BUCKET}/central"
EXTRA=""
[ "$MODO" = "simular" ] && EXTRA="--dry-run"

log "sync ${STAGING} → ${DESTINO}${EXTRA:+ (SIMULAÇÃO)}"
if ! "$RCLONE" sync "$STAGING" "$DESTINO" $EXTRA --stats-one-line --stats 0 2>&1 | sed 's/^/[offsite] rclone: /'; then
  log "ERRO: o sync falhou. O backup LOCAL está intacto; só a cópia offsite não subiu."
  exit 1
fi

if [ "$MODO" = "simular" ]; then
  log "SIMULAÇÃO — nada subiu. Rode com --executar no cron."
  exit 0
fi

# ── 3. Conferir do outro lado ──────────────────────────────────────
# Sem isto, "sync OK" é a palavra do cliente. O que vale é o que o bucket
# devolve quando perguntado de novo.
REMOTOS="$("$RCLONE" lsf "$DESTINO" 2>/dev/null | grep -c '\.gpg$' || true)"
if [ "${REMOTOS:-0}" -eq "$CIFRADOS" ]; then
  log "✅ ${REMOTOS} objeto(s) confirmados no bucket, cifrados"
else
  log "ERRO: subi ${CIFRADOS} e o bucket devolve ${REMOTOS:-0} — não confie neste offsite."
  exit 1
fi

log "para restaurar: gpg --decrypt --output db.sql.gz db_AAAA-MM-DD.sql.gz.gpg"
log "               (a frase é BACKUP_OFFSITE_PASSPHRASE — ver runbook-backup.md)"
