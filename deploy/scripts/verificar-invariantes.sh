#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# verificar-invariantes.sh — o gate do EPIC-1, executável
# ═══════════════════════════════════════════════════════════════════
# Falha se alguma decisão de arquitetura tiver sido violada. Rode antes de
# todo commit de infra e no gate do épico (`make check`).
#
#   AD-7 / FR-2 — imagem com tag FIXA (nunca `latest`)          [STORY-1.3]
#   AD-9        — banco da central ISOLADO do Twenty/Supabase   [STORY-1.2]
#   AD-8        — só o Caddy publica porta; segredos fora do git [STORY-1.1]
#
# Nenhum VALOR de variável é impresso — só nomes de chave e veredito.
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
COMPOSE="docker compose -f ${RAIZ}/deploy/docker-compose.yml --env-file ${ENV_FILE}"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/^"\(.*\)"$/\1/'; }

FALHAS=0
ok()    { echo "  ✓ $1"; }
falha() { echo "  ✗ $1"; FALHAS=$((FALHAS + 1)); }

echo
echo "── AD-7 / FR-2 — versão fixada (STORY-1.3) ────────────────────"
IMAGENS="$($COMPOSE config --images 2>/dev/null | sort -u)"
if echo "$IMAGENS" | grep -qE ':latest$|^[^:]+$'; then
  falha "há imagem com 'latest' ou SEM tag: $(echo "$IMAGENS" | grep -E ':latest$|^[^:]+$' | tr '\n' ' ')"
else
  ok "todas as imagens têm tag explícita: $(echo "$IMAGENS" | tr '\n' ' ')"
fi
CW_TAG="$(env_get CHATWOOT_TAG)"
case "$CW_TAG" in
  *-ce) ok "Chatwoot em Community Edition (${CW_TAG}) — sem fork, sem enterprise/" ;;
  "")   falha "CHATWOOT_TAG não definida no .env" ;;
  *)    falha "CHATWOOT_TAG=${CW_TAG} não é uma tag '-ce' (AD-7: só Community Edition)" ;;
esac

echo
echo "── AD-9 — banco da central isolado (STORY-1.2) ────────────────"
# 1. Nenhuma credencial de BANCO de domínio mora no .env da central.
#
# A linha é entre BANCO e API de canal, e não no nome do sistema:
#   ❌ EVOLUTION_DB_PASSWORD, TWENTY_*, SUPABASE_*, *_CONNECTION_URI  → cross-DB (AD-9)
#   ✅ EVOLUTION_URL / EVOLUTION_API_KEY                              → adapter de canal (AD-4)
# A central FALA com a Evolution por HTTP (é assim que o WhatsApp entra); o que
# ela não pode é abrir conexão em banco de domínio nenhum.
VAZADAS="$(grep -oE '^[A-Z_0-9]*(TWENTY|SUPABASE)[A-Z_0-9]*=|^[A-Z_0-9]*(EVOLUTION|N8N|CHATWOOT)[A-Z_0-9]*(DB|DATABASE|CONNECTION_URI|POSTGRES)[A-Z_0-9]*=' "$ENV_FILE" 2>/dev/null | tr -d '=' | tr '\n' ' ')"
if [ -n "$VAZADAS" ]; then
  falha "o .env da central tem credencial de BANCO de domínio: ${VAZADAS}(AD-9: sem cross-DB)"
else
  ok "nenhuma credencial de banco de domínio no .env da central (API de canal é permitida — AD-4)"
fi

# 2. O Chatwoot aponta para o Postgres DESTE compose, não para um banco de domínio.
PG_HOST="$(env_get POSTGRES_HOST)"
if [ "$PG_HOST" = "postgres" ]; then
  ok "POSTGRES_HOST=postgres — o serviço do próprio compose (banco dedicado)"
else
  falha "POSTGRES_HOST=${PG_HOST} — deveria ser 'postgres' (banco próprio da central)"
fi

if $COMPOSE ps --status running --services 2>/dev/null | grep -q '^postgres$'; then
  # 3. O cluster da central hospeda SÓ o banco da central.
  BANCOS="$($COMPOSE exec -T postgres psql -tAX -U postgres -c \
    "SELECT string_agg(datname, ' ' ORDER BY datname) FROM pg_database WHERE datistemplate = false;" 2>/dev/null | tr -d '\r')"
  case "$BANCOS" in
    *twenty*|*n8n*|*evolution*|*supabase*)
      falha "o cluster da central hospeda banco de domínio: ${BANCOS}" ;;
    *) ok "cluster hospeda só os bancos da central: ${BANCOS}" ;;
  esac

  # 4. Sem extensão de cross-DB: dblink/postgres_fdw são a porta dos fundos do AD-9.
  CROSS="$($COMPOSE exec -T postgres psql -tAX -U postgres -d "$(env_get POSTGRES_DATABASE)" -c \
    "SELECT string_agg(extname, ' ') FROM pg_extension WHERE extname IN ('dblink','postgres_fdw');" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$CROSS" ]; then
    ok "sem dblink/postgres_fdw — nenhuma conexão cross-DB possível"
  else
    falha "extensão de cross-DB instalada: ${CROSS}"
  fi

  # 5. Menor privilégio: o usuário da aplicação não é superusuário.
  SUPER="$($COMPOSE exec -T postgres psql -tAX -U postgres -c \
    "SELECT rolsuper FROM pg_roles WHERE rolname = '$(env_get POSTGRES_USERNAME)';" 2>/dev/null | tr -d '[:space:]')"
  if [ "$SUPER" = "f" ]; then
    ok "usuário da aplicação não é superusuário"
  else
    falha "o usuário da aplicação é superusuário (rolsuper=${SUPER})"
  fi
else
  echo "  … stack parada: pulei as checagens que precisam do banco no ar (make up)"
fi

echo
echo "── AD-8 — superfície e segredos (STORY-1.1) ───────────────────"
# Só o Caddy pode publicar porta no host.
PUBLICADORES="$($COMPOSE config --format json 2>/dev/null \
  | python3 -c "import sys,json; s=json.load(sys.stdin)['services']; print(' '.join(n for n,v in s.items() if v.get('ports')))" 2>/dev/null)"
if [ "$PUBLICADORES" = "caddy" ]; then
  ok "só o Caddy publica porta no host (Postgres/Redis/Rails na rede interna)"
else
  falha "serviços publicando porta no host: ${PUBLICADORES:-nenhum} (esperado: só 'caddy')"
fi

# O .env não pode estar versionado.
if git -C "$RAIZ" ls-files --error-unmatch deploy/.env >/dev/null 2>&1; then
  falha "deploy/.env está VERSIONADO no git — revogue os segredos e remova do índice"
else
  ok "deploy/.env não está versionado"
fi

# ── .env e .env.example têm que ter EXATAMENTE o mesmo conjunto de chaves ──
# Comparação SIMÉTRICA, de propósito. A versão anterior só olhava uma direção e
# mesmo assim afirmava "mesmas chaves" — ficou verde enquanto 6 chaves da
# STORY-3.1 faltavam no .env. É a direção que faltava que dói de verdade: sem
# RELAY_TOKEN, por exemplo, o Caddy fecha /twilio/callback e TODO inbound do
# número oficial leva 403 — em produção, em silêncio.
#
# Só nomes de chave são lidos e impressos aqui. Nenhum valor, nunca.
CHAVES_ENV="$(grep -oE '^[A-Z_0-9]+=' "$ENV_FILE" 2>/dev/null | tr -d '=' | sort -u)"
CHAVES_EX="$(grep -oE '^[A-Z_0-9]+=' "${RAIZ}/deploy/.env.example" 2>/dev/null | tr -d '=' | sort -u)"

NAO_DOCUMENTADAS="$(comm -23 <(echo "$CHAVES_ENV") <(echo "$CHAVES_EX") | tr '\n' ' ')"
NAO_PREENCHIDAS="$(comm -13 <(echo "$CHAVES_ENV") <(echo "$CHAVES_EX") | tr '\n' ' ')"

if [ -n "${NAO_DOCUMENTADAS// /}" ]; then
  falha "chaves no .env que NÃO estão no .env.example (chave sem contrato): ${NAO_DOCUMENTADAS}"
fi
if [ -n "${NAO_PREENCHIDAS// /}" ]; then
  falha "chaves no .env.example AUSENTES do seu .env (o serviço sobe sem elas e falha calado): ${NAO_PREENCHIDAS}"
fi
if [ -z "${NAO_DOCUMENTADAS// /}" ] && [ -z "${NAO_PREENCHIDAS// /}" ]; then
  ok ".env e .env.example têm o mesmo conjunto de chaves ($(echo "$CHAVES_EX" | wc -l) chaves, nos dois sentidos)"
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ invariantes do EPIC-1 OK."
  exit 0
fi
echo "❌ ${FALHAS} invariante(s) violada(s) — NÃO comite."
exit 1
