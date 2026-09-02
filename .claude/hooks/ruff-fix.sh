#!/usr/bin/env bash
# PostToolUse(Write|Edit): formata + lint o arquivo Python editado. Nunca bloqueia.
# Prefere .venv/bin/ruff; cai para o ruff do PATH. Escopa ao arquivo editado.
RUFF=.venv/bin/ruff
[ -x "$RUFF" ] || RUFF=$(command -v ruff) || exit 0

input=$(cat)
file=$(printf '%s' "$input" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)

if [ -n "$file" ]; then
  # Só age em .py; outros arquivos (md/json/yml/sh) não são tocados.
  case "$file" in
    *.py)
      [ -f "$file" ] || exit 0
      "$RUFF" format "$file" --quiet 2>/dev/null
      "$RUFF" check "$file" --fix --quiet 2>/dev/null
      ;;
  esac
fi
exit 0
