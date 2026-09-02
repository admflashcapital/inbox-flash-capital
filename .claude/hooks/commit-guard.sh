#!/usr/bin/env bash
# PreToolUse(Bash): bloqueia `git commit` se houver secret staged.
# Degrada graciosamente: sem gitleaks instalado, o scan é pulado.
#
# NÃO roda testes, e não é omissão: este repo não tem código de aplicação. O Chatwoot
# é imagem oficial sem fork (AD-7) e o Serviço de Sync foi cancelado (AD-13). O verde
# daqui são os verificadores em `scripts/`, rodados à mão — ver `.claude/commands/test.md`.
input=$(cat)
echo "$input" | grep -q "git commit" || exit 0

if command -v gitleaks >/dev/null 2>&1; then
  if ! gitleaks protect --staged --no-banner 2>/dev/null; then
    echo "[HOOK] Secret detectado nos arquivos staged — commit bloqueado." >&2
    exit 2
  fi
fi

exit 0
