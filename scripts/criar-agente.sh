#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# criar-agente.sh — põe uma pessoa para atender na central (STORY-6.1)
# ═══════════════════════════════════════════════════════════════════
# O seed não cria gente, e é de propósito: usuário tem SENHA, e senha é escolha
# humana, não valor de arquivo (mesma razão pela qual o admin nasce no
# /installation/onboarding). Este script é a porta por onde uma pessoa entra.
#
# Por que não usar o convite nativo do Chatwoot: o `AgentBuilder` gera uma senha
# aleatória e conta com um e-mail de convite para a pessoa trocá-la. **Não há
# SMTP configurado** nesta instalação — o convite não chega, e o agente nasce
# inutilizável. Então a senha é definida aqui, na criação.
#
# ── A SENHA NUNCA APARECE ──────────────────────────────────────────
# Lida com `read -s` (não ecoa), entregue ao container por STDIN para um arquivo
# com `umask 077`, lida pelo Ruby e apagada em seguida. Nunca em `argv`, nunca
# em variável de ambiente, nunca no `.env`, nunca no terminal, nunca no log.
# Um segredo exibido é um segredo comprometido.
#
# ── Papéis ─────────────────────────────────────────────────────────
# O Chatwoot CE tem DOIS papéis e só: `agent` e `administrator`. Papel
# customizado é premium e está desligado na imagem — não existe "agente que vê
# tudo menos o CPF". O que restringe um agente é a INBOX a que ele pertence:
# sem `--inbox`, ele entra e não vê conversa nenhuma.
#
# Uso:
#   scripts/criar-agente.sh --nome "Fulana" --email fulana@flashcapital.com.br --inbox "E-mail"
#   scripts/criar-agente.sh --nome "Beltrano" --email b@flashcapital.com.br --admin
#   scripts/criar-agente.sh --listar
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${RAIZ}/.env"
COMPOSE="docker compose -f ${RAIZ}/compose.yaml --env-file ${ENV_FILE}"
. "${RAIZ}/scripts/lib/env.sh"

CONTA="$(env_get CENTRAL_ACCOUNT_ID)"
CONTA="${CONTA:-1}"
ARQ_SENHA="/tmp/.senha-agente"

NOME=""; EMAIL=""; INBOX=""; PAPEL="agent"; LISTAR="nao"

while [ $# -gt 0 ]; do
  case "$1" in
    --nome)   NOME="${2:-}";  shift 2 ;;
    --email)  EMAIL="${2:-}"; shift 2 ;;
    --inbox)  INBOX="${2:-}"; shift 2 ;;
    --admin)  PAPEL="administrator"; shift ;;
    --listar) LISTAR="sim"; shift ;;
    *) echo "argumento desconhecido: $1" >&2
       echo "uso: criar-agente.sh --nome N --email E [--inbox NOME] [--admin] | --listar" >&2
       exit 1 ;;
  esac
done

if ! $COMPOSE ps --status running --services 2>/dev/null | grep -q '^chatwoot-web$'; then
  echo "[agente] a central não está de pé. Rode: docker compose up -d --wait" >&2
  exit 1
fi

# ── Listar quem já atende ──────────────────────────────────────────
if [ "$LISTAR" = "sim" ]; then
  $COMPOSE exec -T -e CONTA="$CONTA" chatwoot-web bundle exec rails runner "
    conta = Account.find(ENV.fetch('CONTA'))
    puts \"[agente] conta #{conta.id} (#{conta.name})\"
    AccountUser.where(account_id: conta.id).includes(:user).order(:id).each do |v|
      caixas = InboxMember.where(user_id: v.user_id).joins(:inbox).pluck('inboxes.name')
      escopo = caixas.empty? ? (v.administrator? ? 'todas (é admin)' : 'NENHUMA — não vê conversa') : caixas.join(', ')
      puts \"  #{v.user.email}  papel=#{v.role}  inboxes=#{escopo}\"
    end
  " 2>/dev/null | grep '^\[agente\]\|^  '
  exit 0
fi

if [ -z "$NOME" ] || [ -z "$EMAIL" ]; then
  echo "uso: criar-agente.sh --nome N --email E [--inbox NOME] [--admin] | --listar" >&2
  exit 1
fi

echo "[agente] ${EMAIL} — papel ${PAPEL}${INBOX:+, inbox '${INBOX}'} (conta ${CONTA})"

# A senha só existe entre este `read` e o `File.delete` lá dentro.
printf 'senha para %s (não será exibida): ' "$EMAIL" >&2
read -rs SENHA
echo >&2
if [ -z "$SENHA" ]; then
  echo "[agente] senha vazia — abortado." >&2
  exit 1
fi

limpar() { $COMPOSE exec -T chatwoot-web sh -c "rm -f ${ARQ_SENHA}" >/dev/null 2>&1 || true; }
trap limpar EXIT

printf '%s' "$SENHA" | $COMPOSE exec -T chatwoot-web sh -c "umask 077; cat > ${ARQ_SENHA}"
unset SENHA

# `argv` do runner não carrega segredo: só nome, e-mail, papel e inbox, todos
# por ENV para não brigar com aspas. A senha vem do arquivo, e sai dele.
$COMPOSE exec -T \
  -e AGENTE_NOME="$NOME" -e AGENTE_EMAIL="$EMAIL" \
  -e AGENTE_PAPEL="$PAPEL" -e AGENTE_INBOX="$INBOX" -e CONTA="$CONTA" \
  chatwoot-web bundle exec rails runner "
    conta = Account.find(ENV.fetch('CONTA'))
    email = ENV.fetch('AGENTE_EMAIL').strip.downcase
    nome  = ENV.fetch('AGENTE_NOME').strip
    papel = ENV.fetch('AGENTE_PAPEL').to_sym
    caixa = ENV['AGENTE_INBOX'].to_s.strip

    convidante = AccountUser.where(account_id: conta.id, role: :administrator).first&.user
    if convidante.nil?
      puts '[agente] ERRO: a conta não tem administrador. Crie o admin em /installation/onboarding primeiro.'
      exit 1
    end

    usuario = User.from_email(email)
    if usuario.nil?
      usuario = AgentBuilder.new(
        email: email, name: nome, inviter: convidante, account: conta, role: papel
      ).perform
      puts \"[agente] usuário criado (id #{usuario.id})\"
    else
      vinculo = AccountUser.find_or_initialize_by(account_id: conta.id, user_id: usuario.id)
      vinculo.inviter_id = convidante.id if vinculo.new_record?
      vinculo.role = papel
      vinculo.save!
      usuario.update!(name: nome) if usuario.name != nome
      puts \"[agente] usuário já existia (id #{usuario.id}) — papel reconciliado para #{papel}\"
    end

    # A senha vive aqui e morre aqui.
    caminho = '${ARQ_SENHA}'
    if File.exist?(caminho)
      segredo = File.read(caminho)
      File.delete(caminho)
      begin
        usuario.update!(password: segredo, password_confirmation: segredo)
        puts '[agente] senha definida'
      rescue ActiveRecord::RecordInvalid => e
        puts \"[agente] ERRO ao definir a senha: #{e.record.errors.full_messages.join('; ')}\"
        exit 1
      ensure
        segredo = nil
      end
    end

    # Sem SMTP não há confirmação por e-mail; sem confirmação não há login.
    usuario.update!(confirmed_at: Time.current) if usuario.confirmed_at.nil?

    unless caixa.empty?
      ibx = conta.inboxes.find_by(name: caixa)
      if ibx.nil?
        nomes = conta.inboxes.pluck(:name).join(', ')
        puts \"[agente] AVISO: inbox '#{caixa}' não existe. Existem: #{nomes}\"
      else
        InboxMember.find_or_create_by!(inbox_id: ibx.id, user_id: usuario.id)
        puts \"[agente] vinculado à inbox '#{ibx.name}' (id #{ibx.id})\"
      end
    end

    membros = InboxMember.where(user_id: usuario.id).joins(:inbox).pluck('inboxes.name')
    escopo  = membros.empty? ? (papel == :administrator ? 'todas (é admin)' : 'NENHUMA — não verá conversa') : membros.join(', ')
    puts \"[agente] pronto: #{email} · papel #{papel} · inboxes: #{escopo}\"
  " 2>/dev/null | grep '^\[agente\]'
