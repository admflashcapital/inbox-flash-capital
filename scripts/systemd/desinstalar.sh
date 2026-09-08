#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# desinstalar.sh — desfaz o instalar.sh, e diz o preço de desfazer
# ═══════════════════════════════════════════════════════════════════
# Existe para que "desfazer" seja UM comando, e não três nomes de unidade
# digitados de memória às 3h da manhã. Um nome errado ali desliga metade dos
# jobs e deixa a outra metade rodando — o pior dos dois mundos, e em silêncio.
#
#   sudo bash scripts/systemd/desinstalar.sh --pausar    # desliga, mantém os arquivos
#   sudo bash scripts/systemd/desinstalar.sh --remover   # desliga e apaga as unidades
#
# ⚠️ A `wsl-ancora.service` NUNCA é tocada por este script, nem no --remover.
#    Ela é o que mantém a VM do WSL viva; derrubá-la desliga o servidor
#    inteiro — containers, cron e timers junto. Para mexer nela, é à mão e
#    de propósito (docs/runbook-wsl-autostart.md).
set -euo pipefail

MODO="${1:-}"
TIMERS=(central-backup.timer central-retencao.timer central-restore-check.timer)
SERVICES=(central-backup.service central-offsite.service central-restore-check.service central-retencao.service)

[ "$(id -u)" -eq 0 ] || { echo "precisa de root: sudo bash scripts/systemd/desinstalar.sh ${MODO:---pausar}"; exit 1; }

case "$MODO" in
  --pausar|--remover) ;;
  *) echo "uso: sudo bash scripts/systemd/desinstalar.sh --pausar | --remover"; exit 1 ;;
esac

echo "── desligando os timers ─────────────────────────────────────"
for t in "${TIMERS[@]}"; do
  systemctl disable --now "$t" >/dev/null 2>&1 || true
  echo "  ✓ $t desligado"
done

if [ "$MODO" = "--remover" ]; then
  echo "── apagando as unidades ─────────────────────────────────────"
  for u in "${TIMERS[@]}" "${SERVICES[@]}"; do
    rm -f "/etc/systemd/system/${u}"
    echo "  ✓ ${u} removida"
  done
  systemctl daemon-reload
  echo "  (wsl-ancora.service preservada de propósito)"
fi

cat <<'AVISO'

⚠️  ISTO NÃO É NEUTRO. A partir de agora, nesta máquina:

    • nenhum backup do banco+anexos é gerado — e a poda 7+4 também para,
      porque quem poda é o próprio backup.sh no fim da rodada;
    • nada sobe para o bucket offsite;
    • o ensaio de restore não roda: ninguém mais sabe se o backup abre;
    • o expurgo da LGPD não roda: a central passa a guardar CPF/CNPJ e
      histórico de cobrança para sempre.

    O monitor de canais CONTINUA rodando — ele está no cron, não aqui.

    Enquanto estiver desligado, rode à mão o que importa:

      bash scripts/backup.sh
      bash scripts/backup-offsite.sh --executar
      bash scripts/restore.sh --verificar

    Para religar tudo:  sudo bash scripts/systemd/instalar.sh
    Para conferir:      bash scripts/verificar-operacao.sh

    Voltar para o cron NÃO é a saída: foi medido em 08/09/2026 que os quatro
    jobs tinham ZERO execuções ali, porque esta máquina nunca está acordada
    de madrugada. Ver docs/runbook-operacao.md.
AVISO
