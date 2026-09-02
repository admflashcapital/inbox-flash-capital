#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# env.sh — leitura de UMA chave do .env, sem colocar segredo no ambiente
# ═══════════════════════════════════════════════════════════════════
# Estava duplicada byte-a-byte em 14 scripts; virou biblioteca no achatamento
# da Fase 1.3 (AD-10).
#
# Por que NÃO `source .env`: isso jogaria TODOS os segredos no ambiente do
# processo — e daí no ambiente de todo comando que ele chamar, inclusive
# `docker run`. Um valor com `$`, backtick ou aspas ainda seria interpretado
# pelo shell. Aqui só sai a chave que se pede, e só para uma variável local.
#
# Uso:
#   ENV_FILE="${RAIZ}/.env"
#   . "${RAIZ}/scripts/lib/env.sh"
#   TOKEN="$(env_get CENTRAL_ACCESS_TOKEN)"
#
# Trata: CRLF, espaço nas pontas, e valor entre aspas simples ou duplas.
# Chave repetida no arquivo? Vale a PRIMEIRA (head -1) — mesma regra do
# docker compose.
env_get() {
  sed -n "s/^$1=//p" "$ENV_FILE" \
    | head -1 \
    | sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}
