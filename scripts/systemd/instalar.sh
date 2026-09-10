#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# instalar.sh — publica as unidades de host desta central no systemd
# ═══════════════════════════════════════════════════════════════════
# Estas unidades vivem em /etc/systemd/system, que não é versionado. Sem
# este diretório, a receita da máquina existiria só em prosa no runbook —
# e quem reinstalasse a central montaria os timers de memória, ou não
# montaria.
#
#   sudo bash scripts/systemd/instalar.sh
#
# Idempotente: rodar de novo sobrescreve as unidades e reenlaça os timers.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORIGEM="${RAIZ}/scripts/systemd"
DESTINO=/etc/systemd/system

[ "$(id -u)" -eq 0 ] || { echo "precisa de root: sudo bash scripts/systemd/instalar.sh"; exit 1; }

# O caminho está chumbado nas unidades (WorkingDirectory, Documentation). Se o
# repo foi clonado noutro lugar, instalar assim mesmo criaria unidades que
# apontam para um diretório inexistente e falham só na primeira madrugada.
ESPERADO=/home/flash/projects/inbox-flash-capital
if [ "$RAIZ" != "$ESPERADO" ]; then
  echo "⚠ este repo está em ${RAIZ}, mas as unidades apontam para ${ESPERADO}."
  echo "  Ajuste WorkingDirectory/Documentation em scripts/systemd/*.service antes de instalar."
  exit 1
fi

TIMERS=(central-backup.timer central-retencao.timer central-restore-check.timer)

echo "── instalando unidades ──────────────────────────────────────"
for u in "${ORIGEM}"/*.service "${ORIGEM}"/*.timer; do
  install -m 0644 -o root -g root "$u" "${DESTINO}/$(basename "$u")"
  echo "  ✓ $(basename "$u")"
done

systemctl daemon-reload

echo "── habilitando ──────────────────────────────────────────────"
# Os timers seguram o calendário. Os .service não são habilitados: quem os
# dispara são os timers (e a mão, quando se quer forçar).
for t in "${TIMERS[@]}"; do
  systemctl enable --now "$t" >/dev/null
  echo "  ✓ $t"
done

# ── a linha de cron do monitor ────────────────────────────────────
# O monitor NÃO virou timer de propósito: é sonda de liveness, e recuperar uma
# verificação de saúde atrasada não faz sentido. Mas ele é parte do mesmo passo
# de instalação, e deixá-lo de fora daqui significaria uma máquina nova subindo
# com backup agendado e nenhuma sonda — sem que nada acuse.
DONO="$(stat -c %U "$RAIZ")"
LINHA="0 * * * * cd ${RAIZ} && /usr/bin/flock -n /tmp/monitor-canais.lock bash scripts/monitorar-canais.sh --executar >> backups/monitor-canais.log 2>&1"

# O `cd` não é enfeite: cron roda com cwd=$HOME, e sem ele o log vai para o
# lugar errado. Esta asserção existe porque a linha JÁ foi instalada sem o cd
# mais de uma vez — falha silenciosa, que só aparece quando alguém procura o log.
case "$LINHA" in
  *"cd ${RAIZ} &&"*) ;;
  *) echo "linha de cron sem o cd — recusando instalar"; exit 1 ;;
esac

echo "── cron do monitor (sonda de liveness) ──────────────────────"
ATUAL="$(crontab -u "$DONO" -l 2>/dev/null || true)"
if printf '%s\n' "$ATUAL" | grep -q "monitorar-canais.sh"; then
  echo "  ✓ já registrado para ${DONO} — não duplico"
else
  printf '%s\n%s\n' "$ATUAL" "$LINHA" | sed '/^$/d' | crontab -u "$DONO" -
  echo "  ✓ instalado para ${DONO} (de hora em hora)"
fi

echo "── estado ───────────────────────────────────────────────────"
systemctl list-timers --no-pager "${TIMERS[@]}" 2>/dev/null | head -6
echo
echo "cron do monitor: $(crontab -u "$DONO" -l 2>/dev/null | grep -c monitorar-canais.sh) linha(s)"
echo
echo "Pronto. Confira com: bash scripts/verificar-operacao.sh"
