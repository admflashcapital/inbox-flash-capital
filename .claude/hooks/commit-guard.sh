#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia `git commit` se houver secret staged ou testes falhando.
# Degrada graciosamente: sem gitleaks → pula scan; sem pytest ou sem testes → pula testes.
# (Muitas stories deste repo são de configuração — não haverá suíte para rodar, e tudo bem.)
input=$(cat)
echo "$input" | grep -q "git commit" || exit 0

if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks protect --staged --no-banner 2>/dev/null; then
    echo "[HOOK] Secret detectado nos arquivos staged — commit bloqueado." >&2
    exit 2
  fi
fi

# Prefere o pytest do venv do projeto (os hooks rodam fora do venv ativado).
PYTEST=.venv/bin/pytest
[ -x "$PYTEST" ] || PYTEST=$(command -v pytest 2>/dev/null)

# Testes do Serviço de Sync (EPIC-5). Antes disso, não há suíte — o hook só passa reto.
if [ -n "$PYTEST" ] && find sync-service/tests -name '*.py' 2>/dev/null | grep -q .; then
  if ! "$PYTEST" -q --tb=short; then
    echo "[HOOK] Testes falhando — commit bloqueado." >&2
    exit 2
  fi
fi
exit 0
