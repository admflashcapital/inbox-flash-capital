#!/usr/bin/env bash
# Stop: registra fim de sessão. Nunca bloqueia.
mkdir -p .claude
echo "[$(date +%Y-%m-%dT%H:%M)] session ended" >> .claude/session.log 2>/dev/null
exit 0
