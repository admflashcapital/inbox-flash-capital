#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# verificar-invariantes.sh — o gate do EPIC-1, executável
# ═══════════════════════════════════════════════════════════════════
# Falha se alguma decisão de arquitetura tiver sido violada. Rode antes de
# todo commit de infra e no gate do épico (`bash scripts/verificar-invariantes.sh`).
#
#   AD-7 / FR-2 — imagem com tag FIXA (nunca `latest`)          [STORY-1.3]
#   AD-9        — banco da central ISOLADO do Twenty/Supabase   [STORY-1.2]
#   AD-8        — só o Caddy publica porta; segredos fora do git [STORY-1.1]
#
# Nenhum VALOR de variável é impresso — só nomes de chave e veredito.
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

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
#   ❌ TWENTY_*, SUPABASE_*, *_DB_*, *_CONNECTION_URI  → cross-DB (AD-9)
#   ✅ TWILIO_ACCOUNT_SID, GOOGLE_OAUTH_*              → adapter de canal (AD-4)
# A central FALA com provedor de canal por HTTP; o que ela não pode é abrir
# conexão em banco de domínio nenhum. O padrão EVOLUTION_* segue no regex de
# propósito: é guarda barata contra alguém ressuscitar a integração pelo banco.
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
  echo "  … stack parada: pulei as checagens que precisam do banco no ar (docker compose up -d --wait)"
fi

echo
echo "── AD-8 — superfície e segredos (STORY-1.1) ───────────────────"
# AD-10: nada publica em 0.0.0.0. Só `chatwoot-web`, e só em 127.0.0.1 — é o
# navegador do colaborador, e mais ninguém. A asserção é sobre o IP de bind,
# não sobre o nome do serviço: publicar em 0.0.0.0 sem TLS é o erro que ela
# existe para pegar.
EXPOSTOS="$($COMPOSE config --format json 2>/dev/null \
  | python3 -c "
import sys, json
s = json.load(sys.stdin)['services']
ruins = []
for nome, cfg in s.items():
    for p in cfg.get('ports') or []:
        ip = p.get('host_ip') if isinstance(p, dict) else None
        if ip != '127.0.0.1':
            ruins.append(f\"{nome}:{ip or '0.0.0.0'}\")
print(' '.join(ruins))
" 2>/dev/null)"
PUBLICADORES="$($COMPOSE config --format json 2>/dev/null \
  | python3 -c "import sys,json; s=json.load(sys.stdin)['services']; print(' '.join(n for n,v in s.items() if v.get('ports')))" 2>/dev/null)"
if [ -n "$EXPOSTOS" ]; then
  falha "publicando fora de 127.0.0.1: ${EXPOSTOS} (AD-10: sem TLS, nada de LAN)"
elif [ "$PUBLICADORES" = "chatwoot-web" ]; then
  ok "só chatwoot-web publica porta, e só em 127.0.0.1 (Postgres/Redis na rede interna)"
else
  falha "serviços publicando porta: ${PUBLICADORES:-nenhum} (esperado: só 'chatwoot-web')"
fi

# O .env não pode estar versionado.
if git -C "$RAIZ" ls-files --error-unmatch .env .env >/dev/null 2>&1; then
  falha ".env está VERSIONADO no git — revogue os segredos e remova do índice"
else
  ok ".env não está versionado"
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
CHAVES_EX="$(grep -oE '^[A-Z_0-9]+=' "${RAIZ}/.env.example" 2>/dev/null | tr -d '=' | sort -u)"

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

# ── Valor com espaço/CR nas pontas: o erro mais traiçoeiro do .env ──
# Invisível na tela e mortal na prática: um espaço sobrando em POSTGRES_PASSWORD
# é uma falha de autenticação sem pista nenhuma; num SID, é uma URL inválida.
# Os NOSSOS scripts aparam (env_get), mas o Docker Compose NÃO — ele passa o valor
# cru para o container. Então a checagem tem que existir aqui.
#
# Só nomes de chave são impressos.
SUJAS="$(grep -nE '^[A-Z_0-9]+=([[:space:]]+.*|.*[[:space:]]+)$' "$ENV_FILE" 2>/dev/null \
  | sed 's/^[0-9]*://' | cut -d= -f1 | tr '\n' ' ')"
# `grep -c` já imprime 0 e sai com 1 quando não acha; o `|| true` evita que o
# `echo 0` de um fallback grude um segundo "0" na variável.
CRLF="$(grep -cE $'\r$' "$ENV_FILE" 2>/dev/null || true)"; CRLF="${CRLF:-0}"
if [ -n "${SUJAS// /}" ]; then
  falha "chaves cujo VALOR tem espaço/tab nas pontas (o Compose não apara — falha calada): ${SUJAS}"
elif [ "${CRLF:-0}" -gt 0 ]; then
  falha "o .env tem ${CRLF} linha(s) com CR (fim de linha Windows) — o \\r entra no valor. Rode: dos2unix .env"
else
  ok "nenhum valor do .env tem espaço ou CR nas pontas"
fi

# ── A central serve UMA conta, e o .env aponta para ELA ───────────
# Aprendido do jeito difícil: o smoke test deixou uma conta ("Flash Capital
# (smoke)") no banco. Ela virou a conta 1; o `.env` dizia CENTRAL_ACCOUNT_ID=1;
# e todo o trabalho dos canais foi criado dentro da conta de TESTE, enquanto o
# operador logava na conta real e via uma central vazia — sem nenhum erro.
if $COMPOSE ps --status running --services 2>/dev/null | grep -q '^postgres$'; then
  DB="$(env_get POSTGRES_DATABASE)"
  conta_sql() { $COMPOSE exec -T postgres psql -tAX -U postgres -d "$DB" -c "$1" 2>/dev/null | tr -d '[:space:]'; }

  TESTE="$(conta_sql "SELECT count(*) FROM accounts WHERE name ILIKE '%smoke%' OR name ILIKE '%test%';")"
  if [ "${TESTE:-0}" -eq 0 ] 2>/dev/null; then
    ok "nenhuma conta de teste no banco"
  else
    falha "há ${TESTE} conta(s) de TESTE no banco — elas roubam o id 1 e os canais acabam criados nelas"
  fi

  QTD="$(conta_sql "SELECT count(*) FROM accounts;")"
  ID_ENV="$(env_get CENTRAL_ACCOUNT_ID)"
  EXISTE="$(conta_sql "SELECT count(*) FROM accounts WHERE id = ${ID_ENV:-0};")"
  if [ "${QTD:-0}" -eq 1 ] && [ "${EXISTE:-0}" -eq 1 ]; then
    ok "CENTRAL_ACCOUNT_ID=${ID_ENV} é a única conta da central"
  elif [ "${EXISTE:-0}" -ne 1 ]; then
    falha "CENTRAL_ACCOUNT_ID=${ID_ENV} não existe no banco — os canais seriam criados no vazio"
  else
    falha "há ${QTD} contas no banco. A central serve UMA empresa; conta extra significa canal criado na conta errada"
  fi
fi

# ── A API da central responde autenticada ─────────────────────────
# Prova viva, não inspeção de config: o monorepo espelha os disparos por esta
# mesma API (AD-6), com este mesmo token. Se ela não responde 200, o espelho
# fica mudo — e ele falha em SILÊNCIO por design (AD-12), então esta é a única
# chance de o problema aparecer.
TOKEN="$(env_get CENTRAL_ACCESS_TOKEN)"
CONTA="$(env_get CENTRAL_ACCOUNT_ID)"
PORTA="$(env_get CHATWOOT_HOST_PORT)"; PORTA="${PORTA:-3001}"
if [ -n "$TOKEN" ] && [ -n "$CONTA" ] && $COMPOSE ps --status running --services 2>/dev/null | grep -q '^chatwoot-web$'; then
  CODIGO="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
    -H "api_access_token: ${TOKEN}" "http://127.0.0.1:${PORTA}/api/v1/accounts/${CONTA}/inboxes" 2>/dev/null)"
  if [ "$CODIGO" = "200" ]; then
    ok "a API da central responde 200 em 127.0.0.1:${PORTA} (é por aqui que o espelho entra)"
  else
    falha "a API da central em 127.0.0.1:${PORTA} devolveu HTTP ${CODIGO} — com isso o espelho do monorepo fica mudo"
  fi
else
  falha "não deu para provar a API ao vivo (stack parada, ou CENTRAL_ACCESS_TOKEN/CENTRAL_ACCOUNT_ID vazios)"
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ invariantes do EPIC-1 OK."
  exit 0
fi
echo "❌ ${FALHAS} invariante(s) violada(s) — NÃO comite."
exit 1
