#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# aguardar-stack.sh — segura o job até o Docker e a central responderem
# ═══════════════════════════════════════════════════════════════════
# Existe por causa do `Persistent=true` dos timers. Quando a máquina passa
# a noite (ou o fim de semana) desligada, o timer que perdeu a hora dispara
# LOGO no boot — e nessa hora o Docker (o docker.service, aqui dentro da VM)
# ainda está subindo: os timers entram no ar antes dele.
#
# Sem esta espera o backup falharia com "cannot connect to the Docker
# daemon" exatamente nos dias em que ele é mais necessário: os que vieram
# depois de um apagão. A recuperação viraria a falha.
#
# Uso:  bash scripts/lib/aguardar-stack.sh [segundos]   (padrão 300)
#
# Sai 0 quando o daemon responde E o Postgres da central está healthy.
# Sai 1 no estouro do limite — e aí o job NÃO roda, que é melhor do que
# rodar contra um banco meio de pé e gravar um dump truncado.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIMITE="${1:-300}"
INICIO=$SECONDS

esgotou() { (( SECONDS - INICIO > LIMITE )); }

while ! docker info >/dev/null 2>&1; do
  esgotou && { echo "[aguardar] daemon do Docker não respondeu em ${LIMITE}s — job cancelado"; exit 1; }
  sleep 5
done
echo "[aguardar] daemon do Docker respondeu em $((SECONDS - INICIO))s"

# O nome do container não é chumbado: sai do próprio compose, que é a fonte
# da verdade. Renomear o serviço não quebra esta espera em silêncio.
CID=""
while [ -z "$CID" ]; do
  CID="$(docker compose -f "${RAIZ}/compose.yaml" --env-file "${RAIZ}/.env" ps -q postgres 2>/dev/null || true)"
  [ -n "$CID" ] && break
  esgotou && { echo "[aguardar] container do Postgres da central não apareceu em ${LIMITE}s — job cancelado"; exit 1; }
  sleep 5
done

while [ "$(docker inspect -f '{{.State.Health.Status}}' "$CID" 2>/dev/null || echo indefinido)" != "healthy" ]; do
  esgotou && { echo "[aguardar] Postgres da central não ficou healthy em ${LIMITE}s — job cancelado"; exit 1; }
  sleep 5
done

echo "[aguardar] stack pronta em $((SECONDS - INICIO))s"
