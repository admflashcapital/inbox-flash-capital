#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# parear-chip.sh — pareia o chip de prospecção na Evolution (STORY-2.1)
# ═══════════════════════════════════════════════════════════════════
# Puxa o QR pela API da Evolution e o grava num ARQUIVO PNG. Não usa a UI
# (`evolution.localhost`) — e, em produção, a Evolution NÃO deve ser exposta.
#
# ── Por que o QR vai para arquivo, e nunca para o terminal ────────
# O QR (e o pairing code) é uma CREDENCIAL de vinculação de dispositivo: quem o
# tiver, dentro da validade, linka o PRÓPRIO aparelho ao WhatsApp do chip. Impresso
# no terminal, ele entra no scroll, no log da sessão e em qualquer transcript —
# ou seja, vaza. Por isso só o CAMINHO do arquivo é impresso (AD-8).
#
# ── Qual chip ─────────────────────────────────────────────────────
# O PRÉ-PAGO de prospecção. NUNCA o número oficial de cobrança — a segmentação de
# risco existe para que um número queimado não leve o canal de dinheiro junto.
#
# ── Duas formas de parear ─────────────────────────────────────────
#   QR      → escaneia com a câmera do celular.
#   CÓDIGO  → 8 caracteres que você DIGITA no celular. Não precisa de câmera.
#             Exige NUMERO_PROSPECCAO (E.164) no .env, porque a Evolution precisa
#             saber para qual número emitir o código.
# Os dois produzem a MESMA vinculação. O código é o caminho para câmera quebrada.
#
# Uso:
#   deploy/scripts/parear-chip.sh            # QR (grava PNG e abre)
#   deploy/scripts/parear-chip.sh --codigo   # código de 8 caracteres (sem câmera)
#   deploy/scripts/parear-chip.sh --status   # só mostra o estado da instância
#   deploy/scripts/parear-chip.sh --logout   # desconecta o número (NÃO apaga a instância)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${RAIZ}/deploy/.env"
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"; }

EV_URL="$(env_get EVOLUTION_URL)";        EV_URL="${EV_URL:-http://evolution-api:8080}"
EV_INST="$(env_get EVOLUTION_INSTANCE)";  EV_INST="${EV_INST:-crm}"
EV_KEY="$(env_get EVOLUTION_API_KEY)"     # SEGREDO — só entra em ENV de container
REDE="${REDE_CANAIS:-flash-canais}"
IMAGEM_CURL="curlimages/curl:8.11.1"
QR_PNG="${RAIZ}/deploy/.qr-pareamento.png"       # gitignored
COD_TXT="${RAIZ}/deploy/.qr-codigo-pareamento.txt" # gitignored (mesmo padrão .qr-*)
NUM_CHIP="$(env_get NUMERO_PROSPECCAO)"

if [ -z "$EV_KEY" ]; then
  echo "[chip] ERRO: EVOLUTION_API_KEY ausente no deploy/.env"
  exit 1
fi

# A apikey é expandida DENTRO do container — nunca no argv do host (`ps` a veria).
ev() {  # ev <método> <caminho>
  EV_KEY="$EV_KEY" docker run --rm -e EV_KEY --network "$REDE" \
    --entrypoint sh "$IMAGEM_CURL" -c "
      curl -sS -X ${1} -H \"apikey: \$EV_KEY\" '${EV_URL}${2}'
    " 2>/dev/null
}

estado() { ev GET "/instance/connectionState/${EV_INST}" | python3 -c "
import sys, json
try: print(json.load(sys.stdin)['instance']['state'])
except Exception: print('desconhecido')
"; }

# Mostra o número pareado com o miolo mascarado (é PII, e basta conferir as pontas).
numero_pareado() { ev GET "/instance/fetchInstances" | python3 -c "
import sys, json
d = json.load(sys.stdin)
insts = d if isinstance(d, list) else d.get('data', [])
for i in insts:
    x = i.get('instance', i)
    if (x.get('instanceName') or x.get('name')) != '''${EV_INST}''':
        continue
    jid = (x.get('ownerJid') or '').split('@')[0]
    print(f'{jid[:5]}…{jid[-4:]}' if len(jid) > 9 else '(nenhum)')
    break
" 2>/dev/null; }

# ── --status ──────────────────────────────────────────────────────
if [ "${1:-}" = "--status" ]; then
  echo "[chip] instância '${EV_INST}' em ${EV_URL}"
  echo "  estado  $(estado)"
  echo "  número  $(numero_pareado)   (mascarado de propósito — é PII)"
  exit 0
fi

# ── --logout ──────────────────────────────────────────────────────
if [ "${1:-}" = "--logout" ]; then
  echo "[chip] desconectando o número da instância '${EV_INST}' (a instância PERMANECE)…"
  ev DELETE "/instance/logout/${EV_INST}" >/dev/null
  sleep 2
  echo "  estado agora: $(estado)"
  echo
  echo "  ⚠️ Re-parear reinicia a RAMPA DE AQUECIMENTO. Atualize NUMERO_PROSPECCAO_DESDE"
  echo "     no .env com a data do novo pareamento (STORY-2.3)."
  exit 0
fi

# ── Pareamento ────────────────────────────────────────────────────
ESTADO="$(estado)"
if [ "$ESTADO" = "open" ]; then
  echo "[chip] a instância '${EV_INST}' JÁ está conectada (número $(numero_pareado))."
  echo "       Para trocar de chip: parear-chip.sh --logout  e rode de novo."
  exit 0
fi

# ── Modo CÓDIGO: 8 caracteres digitados, sem câmera ───────────────
if [ "${1:-}" = "--codigo" ]; then
  if [ -z "$NUM_CHIP" ]; then
    echo "[chip] ERRO: NUMERO_PROSPECCAO está vazio no deploy/.env."
    echo "       O pareamento por código exige o número do chip em E.164, porque é"
    echo "       para ele que a Evolution emite o código. Ex.: NUMERO_PROSPECCAO=+5531999998888"
    exit 1
  fi
  if ! printf '%s' "$NUM_CHIP" | grep -qE '^\+[0-9]{10,15}$'; then
    echo "[chip] ERRO: NUMERO_PROSPECCAO não está em E.164 (precisa começar com + e só dígitos)."
    exit 1
  fi
  # A Evolution quer o número SEM o '+'.
  NUM_API="${NUM_CHIP#+}"
  echo "[chip] instância '${EV_INST}' está '${ESTADO}' — pedindo código para ${NUM_CHIP:0:5}…${NUM_CHIP: -4}"

  ev GET "/instance/connect/${EV_INST}?number=${NUM_API}" | COD_TXT="$COD_TXT" python3 -c "
import sys, json, os
d = json.load(sys.stdin)
cod = (d.get('pairingCode') or '').strip()
if not cod:
    print('[chip] a Evolution não devolveu pairingCode.')
    print('       Causas: número em formato errado, instância em estado transitório,')
    print('       ou a versão da Evolution não suporta pareamento por código.')
    print('       Tente de novo, ou use o QR: make chip')
    raise SystemExit(1)
destino = os.environ['COD_TXT']
with open(destino, 'w') as f:
    f.write(cod + '\n')
os.chmod(destino, 0o600)
print(f'[chip] código gravado em: {destino}')
" || exit 1

  echo
  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  echo "  │  PAREAMENTO POR CÓDIGO — não precisa de câmera                  │"
  echo "  └─────────────────────────────────────────────────────────────────┘"
  echo
  echo "  No celular do chip:"
  echo "    WhatsApp → Aparelhos conectados → Conectar aparelho"
  echo "    → toque em \"Conectar com número de telefone\" (embaixo, no lugar do QR)"
  echo "    → digite o código de 8 caracteres que está no arquivo"
  echo

  # Mesma disciplina do QR: o código é credencial de vinculação — vai para arquivo,
  # nunca para o terminal. Abrimos o arquivo no visualizador do sistema.
  if command -v explorer.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    explorer.exe "$(wslpath -w "$COD_TXT")" >/dev/null 2>&1 || true
    echo "  (arquivo aberto no Windows)"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$COD_TXT" >/dev/null 2>&1 || true
    echo "  (arquivo aberto)"
  else
    echo "  Abra manualmente:  cat '${COD_TXT}'"
  fi
  echo
  echo "  ⚠️  O código expira em ~60s. Expirou? rode de novo."
  echo
  echo "[chip] aguardando a conexão (até 180s)…"

  for i in $(seq 1 60); do
    sleep 3
    E="$(estado)"
    if [ "$E" = "open" ]; then
      echo
      echo "  ✅ CONECTADO — número $(numero_pareado)"
      rm -f "$COD_TXT" "$QR_PNG"
      echo "     (código apagado do disco)"
      echo
      echo "  Próximos passos:"
      echo "   1. NUMERO_PROSPECCAO_DESDE=$(date +%F)   no .env (rampa de aquecimento)"
      echo "   2. make evolution · 3. make fanout · 4. make aquecimento"
      exit 0
    fi
    printf '.'
  done
  echo
  echo "[chip] não conectou em 180s (estado: $(estado)). O código provavelmente expirou."
  rm -f "$COD_TXT"
  exit 1
fi

# ── Modo QR (default) ─────────────────────────────────────────────
echo "[chip] instância '${EV_INST}' está '${ESTADO}' — gerando o QR…"

ev GET "/instance/connect/${EV_INST}" | QR_PNG="$QR_PNG" python3 -c "
import sys, json, base64, os
d = json.load(sys.stdin)
b64 = (d.get('base64') or '')
if not b64:
    print('[chip] a Evolution não devolveu QR. Estado atual pode ser transitório — tente de novo.')
    raise SystemExit(1)
if ',' in b64:            # data URI: 'data:image/png;base64,....'
    b64 = b64.split(',', 1)[1]
destino = os.environ['QR_PNG']
with open(destino, 'wb') as f:
    f.write(base64.b64decode(b64))
os.chmod(destino, 0o600)
print(f'[chip] QR gravado em: {destino}')
"

echo
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │  ESCANEIE O QR COM O CHIP DE PROSPECÇÃO                         │"
echo "  │  No celular: WhatsApp → Aparelhos conectados → Conectar aparelho│"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo

# Abre o visualizador sozinho — senão o operador teria que abrir a imagem em
# OUTRO terminal, porque este fica bloqueado esperando a conexão.
abriu=""
if command -v wslview >/dev/null 2>&1; then
  wslview "$QR_PNG" >/dev/null 2>&1 && abriu="wslview"
elif command -v explorer.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
  explorer.exe "$(wslpath -w "$QR_PNG")" >/dev/null 2>&1 || true
  abriu="explorer.exe"   # o explorer.exe devolve exit != 0 mesmo quando funciona
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$QR_PNG" >/dev/null 2>&1 && abriu="xdg-open"
fi

if [ -n "$abriu" ]; then
  echo "  (imagem aberta com ${abriu})"
else
  echo "  Abra manualmente:"
  echo "    WSL/Windows:   explorer.exe \$(wslpath -w '${QR_PNG}')"
  echo "    Linux:         xdg-open '${QR_PNG}'"
fi
echo
echo "  ⚠️  O QR expira em ~60s. Expirou? rode de novo — leva 2 segundos."
echo "  ⚠️  Use o chip PRÉ-PAGO de prospecção. NUNCA o número oficial de cobrança."
echo
echo "[chip] aguardando a conexão (até 180s)…"

for i in $(seq 1 60); do
  sleep 3
  E="$(estado)"
  case "$E" in
    open)
      echo
      echo "  ✅ CONECTADO — número $(numero_pareado)"
      rm -f "$QR_PNG"      # a credencial não fica no disco depois de usada
      echo "     (QR apagado do disco)"
      echo
      echo "  Próximos passos:"
      echo "   1. grave a data do pareamento no .env (é dela que sai a rampa de aquecimento):"
      echo "        NUMERO_PROSPECCAO_DESDE=$(date +%F)"
      echo "   2. make evolution      # aplica a integração com a central"
      echo "   3. make fanout         # prova que N8N e central recebem o MESMO evento (AD-5)"
      echo "   4. make aquecimento    # só-inbound + rampa + zero campanha"
      exit 0
      ;;
    close)
      printf '.'
      ;;
    *)
      printf '%s' "${E:0:1}"
      ;;
  esac
done

echo
echo "[chip] não conectou em 180s (estado: $(estado))."
echo "       O QR provavelmente expirou. Rode de novo e escaneie mais rápido."
rm -f "$QR_PNG"
exit 1
