#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# verificar-operacao.sh — invariantes da operação de atendimento (EPIC-6)
# ═══════════════════════════════════════════════════════════════════
# O EPIC-6 é quase todo CONFIGURAÇÃO, e configuração é justamente o que
# apodrece sem ninguém ver: um clique na tela desfaz o que o seed montou e nada
# avisa. Este script cobra, ao vivo, o que o gate do épico afirma.
#
# O que ele recusa, e por quê cada um dói:
#   1. Agente sem inbox. Ele loga, a tela abre vazia, e ninguém entende por quê:
#      `assigned_inboxes` de um agente é a interseção com `inbox_members`.
#   2. Label fora do dicionário, ou com `show_on_sidebar` nulo. A coluna é
#      nullable SEM default: a label existe, é aplicável, e não aparece na barra
#      lateral. Mesma classe de falha silenciosa do AD-13.
#   3. Atribuição automática ligada sem membro. `enable_auto_assignment=true`
#      com `inbox_members` vazio faz a tela prometer distribuição que o
#      `AutoAssignment::AssignmentService` nunca executa (ele sai em 0 quando
#      `available_agents` é vazio).
#   4. Janela de 24h desligada. Ela vem do `medium` do canal: criado como `sms`,
#      a atendente escreve texto livre depois das 24h e a Meta REJEITA — falha
#      silenciosa no canal de cobrança.
#   5. Cron sumido — os QUATRO. Sem o expurgo, a central guarda conversa de
#      cobrança para sempre; sem o monitor, ninguém sabe que um canal caiu; sem
#      o backup, não há de onde restaurar E a poda 7+4 nunca roda (é o próprio
#      backup.sh que poda); sem o ensaio, o backup é esperança, não backup.
#
# NÃO substitui os outros verificadores: `verificar-invariantes.sh` cobre o
# EPIC-1, os `verificar-canal-*.sh` cobrem os canais, e `monitorar-canais.sh`
# cobre liveness. Este cobre a OPERAÇÃO.
#
# Uso: bash scripts/verificar-operacao.sh
# ═══════════════════════════════════════════════════════════════════
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

DB="$(env_get POSTGRES_DATABASE)"
CONTA="$(env_get CENTRAL_ACCOUNT_ID)"; CONTA="${CONTA:-1}"
consultar() { $COMPOSE exec -T postgres psql -tAX -U postgres -d "$DB" -c "$1" 2>/dev/null | tr -d '[:space:]'; }

FALHAS=0
ok()    { echo "  ✓ $1"; }
falha() { echo "  ✗ $1"; FALHAS=$((FALHAS + 1)); }
aviso() { echo "  ⚠ $1"; }

if ! $COMPOSE ps --status running --services 2>/dev/null | grep -q '^chatwoot-web$'; then
  echo "❌ a central não está de pé. Rode: docker compose up -d --wait"
  exit 1
fi

echo "── FR-15 — cockpit e papéis (STORY-6.1) ───────────────────────"

# O Chatwoot CE tem DOIS papéis: agent(0) e administrator(1). Papel customizado
# é premium e está desligado na imagem — não existe granularidade além disto.
ADMINS="$(consultar "SELECT count(*) FROM account_users WHERE account_id=${CONTA} AND role=1;")"
AGENTES="$(consultar "SELECT count(*) FROM account_users WHERE account_id=${CONTA} AND role=0;")"
if [ "${ADMINS:-0}" -ge 1 ]; then
  ok "${ADMINS} administrador(es) e ${AGENTES:-0} agente(s) na conta ${CONTA}"
else
  falha "a conta não tem administrador — crie em /installation/onboarding"
fi

if [ "${AGENTES:-0}" -eq 0 ]; then
  aviso "nenhum agente ainda: os papéis não são demonstráveis. Rode: bash scripts/criar-agente.sh --nome N --email E --inbox 'E-mail'"
else
  ORFAOS="$(consultar "
    SELECT count(*) FROM account_users au
    WHERE au.account_id=${CONTA} AND au.role=0
      AND NOT EXISTS (SELECT 1 FROM inbox_members im WHERE im.user_id = au.user_id);")"
  if [ "${ORFAOS:-0}" -eq 0 ]; then
    ok "todo agente pertence a pelo menos uma inbox (senão a tela abre vazia)"
  else
    falha "${ORFAOS} agente(s) sem nenhuma inbox — logam e não veem conversa nenhuma. Use --inbox no criar-agente.sh"
  fi
fi

MARCA="$($COMPOSE exec -T chatwoot-web bundle exec rails runner \
  'puts "MARCA_RESULT=#{InstallationConfig.find_by(name: "INSTALLATION_NAME")&.value}"' 2>/dev/null \
  | sed -n 's/^MARCA_RESULT=//p')"
if [ "$MARCA" = "Flash Capital" ]; then
  ok "a central se apresenta como 'Flash Capital', não como 'Chatwoot'"
else
  falha "INSTALLATION_NAME='${MARCA:-vazio}' — a aba do navegador e o rodapé dos e-mails ainda dizem Chatwoot"
fi

# `accounts.locale` é enum inteiro; pt_BR = 16. Não é o idioma do dashboard (esse
# vem do usuário): é o que o `ApplicationMailer` usa para escolher o locale de
# TODO e-mail que a central envia, inclusive a resposta ao cliente. A conta nasce
# 'en' e nenhuma tela do CE oferece a troca — só o seed.
LOCALE="$(consultar "SELECT locale FROM accounts WHERE id=${CONTA};")"
if [ "${LOCALE:-}" = "16" ]; then
  ok "locale da conta é pt_BR — o e-mail que a central envia sai em português"
else
  falha "locale da conta = ${LOCALE:-vazio} (pt_BR = 16): o e-mail enviado ao cliente sai com envelope em inglês. Rode: docker compose run --rm chatwoot-seed"
fi

# O espelho fala pelo token de um ADMINISTRADOR da conta — decidido em
# 2026-09-04: não se inventa conta de máquina; o e-mail root é o do admin.
# Checagem estrutural de propósito: comparar o VALOR do token exigiria passá-lo
# no argv do psql, e argv é legível por qualquer usuário via /proc.
ADMIN_COM_TOKEN="$(consultar "
  SELECT count(*) FROM users u
    JOIN account_users au ON au.user_id=u.id AND au.account_id=${CONTA} AND au.role=1
    JOIN access_tokens t  ON t.owner_type='User' AND t.owner_id=u.id;")"
if [ "${ADMIN_COM_TOKEN:-0}" -ge 1 ]; then
  ok "há administrador com access_token — é por ele que o espelho entra (consequência aceita: revogá-lo derruba o acesso da pessoa junto)"
else
  falha "nenhum administrator desta conta tem access_token: o espelho do monorepo não tem por onde entrar. Rode: docker compose run --rm chatwoot-seed"
fi

echo
echo "── FR-16 — atribuição, labels, respostas rápidas (STORY-6.2) ──"

LABELS_ESPERADAS="aguardando-comprovante contato-errado contestacao escalar-alcada negociacao promessa-pagamento sem-retorno"
LABELS_ATUAIS="$(consultar "SELECT string_agg(title, ' ' ORDER BY title) FROM labels WHERE account_id=${CONTA};" | tr ',' ' ')"
FALTANDO=""
for l in $LABELS_ESPERADAS; do
  case " $LABELS_ATUAIS " in *"$l"*) ;; *) FALTANDO="${FALTANDO} ${l}";; esac
done
if [ -z "$FALTANDO" ]; then
  ok "as 7 labels do dicionário existem"
else
  falha "faltam labels:${FALTANDO} — rode: docker compose run --rm chatwoot-seed"
fi

INVISIVEIS="$(consultar "SELECT count(*) FROM labels WHERE account_id=${CONTA} AND show_on_sidebar IS NOT TRUE;")"
if [ "${INVISIVEIS:-0}" -eq 0 ]; then
  ok "toda label aparece na barra lateral (show_on_sidebar)"
else
  falha "${INVISIVEIS} label(s) com show_on_sidebar nulo/falso — existem, são aplicáveis e NÃO aparecem na tela"
fi

RESPOSTAS="$(consultar "SELECT count(*) FROM canned_responses WHERE account_id=${CONTA};")"
if [ "${RESPOSTAS:-0}" -ge 5 ]; then
  ok "${RESPOSTAS} respostas rápidas disponíveis na composição (atalho '/')"
else
  falha "só ${RESPOSTAS:-0} resposta(s) rápida(s) — o seed semeia 5"
fi

MENTINDO="$(consultar "
  SELECT count(*) FROM inboxes i
  WHERE i.account_id=${CONTA} AND i.enable_auto_assignment
    AND NOT EXISTS (SELECT 1 FROM inbox_members im WHERE im.inbox_id = i.id);")"
if [ "${MENTINDO:-0}" -eq 0 ]; then
  AUTO="$(consultar "SELECT count(*) FROM inboxes WHERE account_id=${CONTA} AND enable_auto_assignment;")"
  if [ "${AUTO:-0}" -eq 0 ]; then
    ok "atribuição automática desligada nas duas inboxes — a fila é manual, por decisão"
  else
    ok "${AUTO} inbox(es) com atribuição automática ligada e com membros para distribuir"
  fi
else
  falha "${MENTINDO} inbox(es) com atribuição automática ligada e ZERO membro: a tela promete distribuir e o serviço sai em 0"
fi

echo
echo "── FR-7 — a janela de 24h protege a atendente ─────────────────"

# Comportamento NATIVO do Chatwoot, e ele depende de um campo só: o `medium`.
# `Conversations::MessageWindowService#twilio_messaging_window` devolve 24h
# apenas quando medium == whatsapp; com `sms` devolve nil e a janela some.
JANELA="$($COMPOSE exec -T chatwoot-web bundle exec rails runner '
  ibx = Inbox.find_by(channel_type: "Channel::TwilioSms")
  if ibx.nil?
    puts "JANELA_RESULT=SEM_INBOX"
  else
    conv = Conversation.where(inbox_id: ibx.id).last
    if conv.nil?
      puts "JANELA_RESULT=SEM_CONVERSA|#{ibx.channel.medium}"
    else
      j = Conversations::MessageWindowService.new(conv).send(:messaging_window)
      puts "JANELA_RESULT=#{j.nil? ? "NENHUMA" : j.to_i}|#{ibx.channel.medium}|#{conv.can_reply?}"
    end
  end' 2>/dev/null | sed -n 's/^JANELA_RESULT=//p')"

case "$JANELA" in
  86400*)
    MEDIUM="$(printf '%s' "$JANELA" | cut -d'|' -f2)"
    PODE="$(printf '%s' "$JANELA" | cut -d'|' -f3)"
    ok "janela de 24h ativa no canal oficial (medium=${MEDIUM}); conversa mais recente can_reply=${PODE}" ;;
  SEM_CONVERSA*)
    MEDIUM="$(printf '%s' "$JANELA" | cut -d'|' -f2)"
    if [ "$MEDIUM" = "whatsapp" ]; then
      aviso "sem conversa para medir, mas medium=whatsapp — a janela vale quando a primeira chegar"
    else
      falha "medium=${MEDIUM}: SEM janela. A atendente escreve texto livre após 24h e a Meta rejeita, em silêncio"
    fi ;;
  NENHUMA*)
    falha "o canal oficial não aplica janela de 24h (medium≠whatsapp) — recrie a inbox" ;;
  SEM_INBOX)
    falha "não há inbox Twilio" ;;
  *)
    falha "não consegui medir a janela de 24h (resposta: ${JANELA:-vazia})" ;;
esac

echo
echo "── STORY-6.3 — observabilidade e LGPD ─────────────────────────"

LOGRAGE="$($COMPOSE exec -T chatwoot-web printenv LOGRAGE_ENABLED 2>/dev/null | tr -d '[:space:]')"
if [ "$LOGRAGE" = "true" ]; then
  ok "log estruturado ligado (JSON com remote_ip, user_id e params)"
else
  falha "LOGRAGE_ENABLED=${LOGRAGE:-vazio} no container — o log é texto puro e ninguém filtra um incidente. Recrie: docker compose up -d --force-recreate chatwoot-web"
fi

# Os jobs do host. Agendamento que some não dá erro: dá silêncio — e cada um
# destes silêncios custa uma coisa diferente. Desde 08/09/2026 há dois tipos,
# e a diferença é deliberada: o monitor é sonda de LIVENESS e fica no cron
# (recuperar uma verificação de saúde atrasada não faz sentido — só interessa
# o estado de agora). Os quatro jobs de DADO viraram timers do systemd, porque
# só o systemd recupera hora perdida, e esta máquina passa a madrugada e o fim
# de semana desligada. Ver scripts/systemd/ e docs/runbook-operacao.md.
verificar_cron() {
  local rotulo="$1" padrao="$2" dor="$3"
  if crontab -l 2>/dev/null | grep -q -- "$padrao"; then
    ok "cron de ${rotulo} registrado no host"
  else
    falha "cron de ${rotulo} não registrado — ${dor}. Ver docs/runbook-operacao.md"
  fi
}
verificar_cron "monitor de canais" "monitorar-canais.sh" \
  "um canal cai e ninguém fica sabendo"

# Três asserções por timer, e a terceira é a que dói: um timer sem Persistent
# volta a ser cron com outro nome — perde toda hora em que a máquina estiver
# desligada, que é exatamente o defeito que ele nasceu para corrigir.
verificar_timer() {
  local rotulo="$1" unidade="$2" dor="$3"
  if ! systemctl is-enabled --quiet "$unidade" 2>/dev/null; then
    falha "timer de ${rotulo} (${unidade}) não habilitado — ${dor}. Instale: sudo bash scripts/systemd/instalar.sh"
  elif ! systemctl is-active --quiet "$unidade" 2>/dev/null; then
    falha "timer de ${rotulo} (${unidade}) habilitado mas parado — nada dispara até o próximo boot"
  elif ! systemctl show "$unidade" -p Persistent 2>/dev/null | grep -q "Persistent=yes"; then
    falha "timer de ${rotulo} sem Persistent=true — perde de novo toda hora com a máquina desligada"
  else
    ok "timer de ${rotulo} ativo e com recuperação de hora perdida (${unidade})"
  fi
}
verificar_timer "backup"           "central-backup.timer" \
  "o par banco+anexos para de ser gerado, e a poda 7+4 só acontece quando o script roda"
verificar_timer "expurgo LGPD"     "central-retencao.timer" \
  "a central passa a guardar conversa de cobrança para sempre"
verificar_timer "ensaio de restore" "central-restore-check.timer" \
  "backup que ninguém testou não é backup, é esperança"

# ── A asserção que faltava: EXECUÇÃO, não registro ────────────────────────
# Entre 17/08 e 08/09 este verificador ficou verde enquanto quatro jobs tinham
# ZERO execuções. A pergunta era "a linha existe?" — e existia. A pergunta que
# pega o defeito é "ela alguma vez rodou, e faz quanto tempo?".
# Os limites são folgados de propósito: a máquina é de expediente e some no fim
# de semana, então 5 dias cabem um feriado emendado sem dar falso vermelho. Mas
# nenhum limite deixa passar o caso real, que era log INEXISTENTE.
# Recebe um PADRÃO, não um arquivo: para o backup a evidência certa é o
# artefato mais novo, não o log. Um `bash scripts/backup.sh` rodado à mão
# produz o dump e NÃO escreve no log (quem redireciona é a unidade) — cobrar
# o log diria "nunca executou" com o par banco+anexos ali, do lado. E a
# pergunta que interessa não é "o log cresceu?", é "existe backup recente?".
# Para expurgo e ensaio de restore não há artefato — eles apagam e destroem —
# então nesses o log É a única evidência que sobra.
verificar_execucao() {
  local rotulo="$1" padrao="$2" limite="$3" dor="$4"
  local arquivo
  # sem aspas de propósito: o padrão pode ser um glob
  arquivo="$(ls -1t $padrao 2>/dev/null | head -1)"
  if [ -z "$arquivo" ] || [ ! -f "$arquivo" ]; then
    falha "${rotulo}: nunca executou (nada casa ${padrao}) — ${dor}"
    return
  fi
  local idade=$(( ( $(date +%s) - $(stat -c %Y "$arquivo") ) / 86400 ))
  if [ "$idade" -gt "$limite" ]; then
    falha "${rotulo}: última execução há ${idade} dias (limite ${limite}) — ${dor}"
  else
    ok "${rotulo}: executou há ${idade} dia(s) (${arquivo##*/})"
  fi
}
verificar_execucao "backup"            "${RAIZ}/backups/db_*.sql.gz"          5 \
  "não há par banco+anexos recente para restaurar"
verificar_execucao "expurgo LGPD"      "${RAIZ}/backups/retencao.log"        10 \
  "a política de 5 anos está escrita mas não está sendo aplicada"
verificar_execucao "ensaio de restore" "${RAIZ}/backups/restore-verificar.log" 10 \
  "ninguém sabe se o backup abre"

# A cópia offsite é CONDICIONAL, e é de propósito: é opt-in. Cobrá-la sempre
# daria vermelho em instalação que ainda não a ligou; não cobrá-la nunca
# deixaria passar o modo de falha real — alguém preenche as chaves do bucket,
# acha que está protegido, e nada nunca sobe porque ninguém agendou.
if [ -n "$(env_get BACKUP_S3_BUCKET)" ] && [ -n "$(env_get BACKUP_S3_ACCESS_KEY_ID)" ]; then
  # Não tem timer próprio: é puxada pelo Wants= do central-backup.service, para
  # que a cópia remota não possa divergir do dia que acabou de ser gerado.
  if systemctl show central-backup.service -p Wants 2>/dev/null | grep -q "central-offsite.service"; then
    ok "cópia offsite encadeada no backup (central-offsite.service)"
  else
    falha "central-backup.service não puxa central-offsite.service — o bucket está configurado mas nada sobe"
  fi
  verificar_execucao "cópia offsite" "${RAIZ}/backups/backup-offsite.log" 5 \
    "o backup segue morrendo junto com a máquina"
  [ -n "$(env_get BACKUP_OFFSITE_PASSPHRASE)" ] \
    || falha "BACKUP_S3_* preenchidas mas BACKUP_OFFSITE_PASSPHRASE vazia: o offsite recusa subir em claro (e faz bem)"
else
  ok "cópia offsite não configurada — opt-in; o backup LOCAL segue cobrado acima (docs/runbook-backup.md)"
fi

# Papel customizado não existe no CE: quem vê a conversa vê o CPF/CNPJ, porque
# o atributo é da CONVERSA e a policy libera para administrator OU agent. O que
# restringe é a inbox. Deixar isso explícito evita prometer o que não há.
SEM_ESCOPO="$(consultar "
  SELECT count(*) FROM account_users au
  WHERE au.account_id=${CONTA} AND au.role=0
    AND (SELECT count(*) FROM inbox_members im WHERE im.user_id=au.user_id)
        = (SELECT count(*) FROM inboxes i WHERE i.account_id=${CONTA});")"
if [ "${AGENTES:-0}" -eq 0 ]; then
  aviso "sem agente: o escopo por inbox — único controle de acesso a CPF/CNPJ no CE — não é demonstrável"
elif [ "${SEM_ESCOPO:-0}" -eq 0 ]; then
  ok "todo agente vê um subconjunto das inboxes — é o único controle de CPF/CNPJ que o CE oferece"
else
  aviso "${SEM_ESCOPO} agente(s) com acesso a TODAS as inboxes: sem papel customizado no CE, eles veem todo CPF/CNPJ carimbado"
fi

echo
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ operação de atendimento OK (EPIC-6)."
  exit 0
fi
echo "❌ ${FALHAS} violação(ões) — ver docs/runbook-operacao.md"
exit 1
