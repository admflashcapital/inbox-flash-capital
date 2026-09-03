# ═══════════════════════════════════════════════════════════════════
# chatwoot_seed.rb — deixa a central pronta para uso, a cada `up` (AD-10)
# ═══════════════════════════════════════════════════════════════════
# Roda como one-shot (`chatwoot-seed`) DEPOIS do `chatwoot-init` e ANTES de web
# e sidekiq. É idempotente: rodar de novo não duplica nem sobrescreve.
#
# Por que `rails runner` e não a API HTTP: falando direto com o model, o seed
# não precisa do web de pé, nem de token de API, nem de um container `curl`
# numa rede compartilhada. Foi o que permitiu apagar as três coisas.
#
# ── O QUE ESTE SEED NÃO FAZ, DE PROPÓSITO: a conta e o admin ───────
# No Chatwoot os dois nascem JUNTOS, pelo `AccountBuilder`, no onboarding
# (`Installation::OnboardingController`), atrás de uma flag no Redis. Pré-criar
# a conta aqui faria o onboarding criar uma SEGUNDA conta — e "existe
# exatamente uma conta" é invariante verificada (verificar-invariantes.sh).
# Além disso, o admin tem senha: é escolha humana, não valor de arquivo.
# Então: primeiro boot = um passo manual em /installation/onboarding; deste
# ponto em diante a stack sobe inteira sozinha.
#
# NUNCA imprime valor de segredo — só se a chave está presente ou ausente.
# ═══════════════════════════════════════════════════════════════════

def env(chave)
  v = ENV[chave].to_s.strip
  v.empty? ? nil : v
end

def log(msg) = puts("[seed] #{msg}")

conta_id = env("CENTRAL_ACCOUNT_ID")
conta = conta_id && Account.find_by(id: conta_id)

if conta.nil?
  log("nenhuma conta com id=#{conta_id || '(CENTRAL_ACCOUNT_ID vazio)'}.")
  log("primeiro boot? abra http://localhost:#{env('CHATWOOT_HOST_PORT') || 3001}/installation/onboarding,")
  log("crie o admin, ajuste CENTRAL_ACCOUNT_ID no .env e rode `docker compose up -d` de novo.")
  exit 0
end
log("conta #{conta.id} (#{conta.name})")

# ── Canal oficial — Twilio (Channel::TwilioSms, medium whatsapp) ───
# Replica o que o TwilioChannelsController faz em `build_inbox`, MENOS duas
# coisas de propósito:
#   • `authenticate_twilio` — bate na API da Twilio ao vivo. Um seed de boot
#     não pode depender de rede de terceiro para a stack subir.
#   • `setup_webhooks` — o controller só chama quando medium == sms. Aqui é
#     whatsapp, então nem lá roda: quem é dono do webhook do número oficial é
#     o MONOREPO, que valida a assinatura e faz o fan-out (AD-11).
# O sync de templates continua fora daqui (precisa da Twilio no ar):
#   bash scripts/conectar-twilio.sh --templates
nome_oficial = env("INBOX_OFICIAL_NOME") || "WhatsApp Oficial"
numero       = env("TWILIO_NUMERO_OFICIAL")
sid          = env("TWILIO_ACCOUNT_SID")
token        = env("TWILIO_AUTH_TOKEN")

if (inbox = conta.inboxes.find_by(name: nome_oficial))
  log("inbox '#{nome_oficial}' já existe (id #{inbox.id}) — não recrio")
elsif numero.nil? || sid.nil? || token.nil?
  faltando = { TWILIO_NUMERO_OFICIAL: numero, TWILIO_ACCOUNT_SID: sid, TWILIO_AUTH_TOKEN: token }
             .reject { |_, v| v }.keys.join(", ")
  log("pulei '#{nome_oficial}': faltam #{faltando} no .env")
else
  canal = conta.twilio_sms.create!(
    account_sid: sid, auth_token: token,
    phone_number: "whatsapp:#{numero}", medium: :whatsapp
  )
  inbox = conta.inboxes.create!(name: nome_oficial, channel: canal)
  log("inbox '#{nome_oficial}' criada (id #{inbox.id}, Channel::TwilioSms, medium=whatsapp)")
end

# ── Canal de e-mail (Channel::Email + OAuth do Google) ─────────────
# A inbox é PRÉ-CRIADA com o nome exato porque o OauthCallbackController usa
# `find_channel_by_email`: achando o canal, ele só anexa os tokens; não achando,
# cria uma inbox com nome derivado do e-mail. O consent em si segue humano.
nome_email = env("INBOX_EMAIL_NOME") || "E-mail"
caixa      = env("GMAIL_CAIXA_ATENDIMENTO")

if (inbox = conta.inboxes.find_by(name: nome_email))
  log("inbox '#{nome_email}' já existe (id #{inbox.id}) — não recrio")
elsif caixa.nil?
  log("pulei '#{nome_email}': falta GMAIL_CAIXA_ATENDIMENTO no .env")
else
  canal = Channel::Email.create!(account: conta, email: caixa, forward_to_email: caixa)
  inbox = conta.inboxes.create!(name: nome_email, channel: canal)
  log("inbox '#{nome_email}' criada (id #{inbox.id}, Channel::Email) — falta autorizar:")
  log("  bash scripts/conectar-gmail.sh --url")
end

# ── Atribuição: MANUAL, por decisão (STORY-6.2) ────────────────────
# O Chatwoot cria inbox com `enable_auto_assignment = true` por default — e esse
# flag MENTE enquanto não houver membro: `available_agents` é a interseção de
# `inbox_members` com agentes ONLINE, e o `AutoAssignment::AssignmentService`
# devolve 0 de cara quando a lista é vazia. Ficar `true` sem membro é a tela
# dizer que distribui quando não distribui.
#
# Com um operador só, round robin é ruído. Então o flag passa a dizer a verdade.
# Ligar depois é trocar este `false` e povoar `inbox_members` — lembrando que o
# `periodic_assignment_job` roda `*/30`: a atribuição automática leva ATÉ 30 min.
conta.inboxes.each do |ibx|
  next unless ibx.enable_auto_assignment?

  ibx.update!(enable_auto_assignment: false)
  log("inbox '#{ibx.name}': atribuição automática desligada — a fila é manual")
end

# ── Credenciais OAuth no installation_configs ──────────────────────
# A env var sozinha NÃO basta: o Chatwoot semeia essas linhas VAZIAS e o
# GlobalConfigService devolve o vazio do banco, não o ENV. Sem isto, a URL de
# consentimento sai sem client_id e o erro só aparece na tela do Google.
%w[GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET].each do |chave|
  valor = env(chave)
  if valor.nil?
    log("pulei #{chave}: ausente no .env")
    next
  end
  cfg = InstallationConfig.find_or_initialize_by(name: chave)
  if cfg.value == valor
    log("#{chave} já gravado")
  else
    cfg.value = valor
    cfg.locked = false
    cfg.save!
    log("#{chave} gravado no installation_configs")
  end
end
# ── Identidade da instalação (STORY-6.1) ───────────────────────────
# Sem isto a central se apresenta como "Chatwoot" na aba do navegador, no
# título das telas e no rodapé do que ela manda. Quem atende é a Flash Capital.
# Valor literal, não `.env`: é identidade do produto, não configuração de
# ambiente — e mudar por ambiente só criaria divergência entre dev e produção.
{
  "INSTALLATION_NAME" => "Flash Capital",
  "BRAND_NAME" => "Flash Capital"
}.each do |chave, valor|
  cfg = InstallationConfig.find_or_initialize_by(name: chave)
  if cfg.value == valor
    log("#{chave} já é '#{valor}'")
  else
    cfg.value = valor
    cfg.locked = false
    cfg.save!
    log("#{chave} = '#{valor}'")
  end
end

GlobalConfig.clear_cache if defined?(GlobalConfig) && GlobalConfig.respond_to?(:clear_cache)

# ── Atributos de conversa que o espelho carimba (AD-13) ────────────
# SEM ESTA DEFINIÇÃO O DADO FICA INVISÍVEL. O monorepo grava os valores no jsonb
# `conversations.custom_attributes` e a API os devolve, mas a barra lateral do
# Chatwoot só renderiza atributo que tem uma linha em
# `custom_attribute_definitions` — o front itera sobre as DEFINIÇÕES, não sobre
# as chaves gravadas. Medido em 2026-09-02: os quatro valores estavam no banco e
# a tela não mostrava nenhum.
#
# `attribute_key` casa exatamente o que `api/integrations/chatwoot/atributos.py`
# monta no monorepo. Divergiu = atributo órfão, gravado e nunca exibido.
ATRIBUTOS_DA_CONVERSA = [
  { chave: "titulo_id",       nome: "Título",          tipo: :text,     desc: "Id do boleto em internal.boletos. Vazio quando o disparo cobre um LOTE — o id de um título só descreveria parte dele" },
  { chave: "cnpj",            nome: "CNPJ/CPF",        tipo: :text,     desc: "Documento do sacado (CPF quando pessoa física)" },
  { chave: "cedente",         nome: "Cedente",         tipo: :text,     desc: "De quem é o título — a primeira pergunta de quem atende" },
  { chave: "numero_nf",       nome: "Nota fiscal",     tipo: :text,     desc: "A referência que o cliente cita. Vazio em lote" },
  { chave: "data_vencimento", nome: "Vencimento",      tipo: :text,     desc: "Vencimento do título. Vazio em lote" },
  { chave: "valor_em_aberto", nome: "Valor em aberto", tipo: :currency, desc: "Soma do lote disparado, com multa e mora quando já calculados" },
  { chave: "dias_atraso",     nome: "Dias de atraso",  tipo: :number,   desc: "Dias úteis; 0 significa vence hoje. Só o disparo da régua preenche" },
  { chave: "link_boleto",     nome: "Boleto (PDF)",    tipo: :link,     desc: "A mesma URL que a Twilio entregou como anexo ao cliente" }
]

ATRIBUTOS_DA_CONVERSA.each do |a|
  d = CustomAttributeDefinition.find_or_initialize_by(
    attribute_key: a[:chave],
    attribute_model: :conversation_attribute,
    account_id: conta.id
  )
  novo_registro = d.new_record?
  d.attribute_display_name = a[:nome]
  d.attribute_display_type = a[:tipo]
  d.attribute_description = a[:desc]
  d.save!
  log("atributo de conversa '#{a[:chave]}' #{novo_registro ? 'criado' : 'já existia'} (#{a[:tipo]})")
end

# ── Labels (STORY-6.2) — dicionário fechado, aplicação MANUAL ──────
# NINGUÉM empurra label para a central. O AD-13 carimba ATRIBUTOS no instante do
# disparo, e o Serviço de Sync — que aplicaria labels de segmento — foi
# cancelado (EPIC-5). Então toda label aqui é marcação da atendente.
#
# O critério que define o dicionário: label descreve o que a CONVERSA apurou,
# nunca o estado do TÍTULO. Estado de título é do monorepo (AD-1); repetir aqui
# criaria duas verdades que divergem no primeiro pagamento não conciliado.
#
# ⚠️ `Label#title` é forçado a minúsculas e RECUSA espaço (validação do model).
# ⚠️ `show_on_sidebar` é nullable SEM default: não setar = a label existe, é
#    aplicável, e NÃO aparece na barra lateral. Mesma classe de falha silenciosa
#    que o AD-13 (atributo sem definição).
# Renomear depois dispara `Labels::UpdateJob` para reescrever todas as taggings:
# acerte o dicionário na primeira vez.
LABELS = [
  { titulo: "promessa-pagamento",     cor: "#2e7d32", desc: "O sacado se comprometeu com uma data" },
  { titulo: "negociacao",             cor: "#1f93ff", desc: "Pede parcelamento ou desconto — decisão não é da atendente" },
  { titulo: "contestacao",            cor: "#ef6c00", desc: "Contesta mercadoria, nota ou valor. Vai para o cedente antes de cobrar de novo" },
  { titulo: "aguardando-comprovante", cor: "#6a1b9a", desc: "Diz que pagou; falta o comprovante para conferir com a conciliação" },
  { titulo: "contato-errado",         cor: "#607d8b", desc: "Quem respondeu não é o responsável financeiro — o contato precisa ser trocado na rede" },
  { titulo: "sem-retorno",            cor: "#f9a825", desc: "Mandamos e não responde. É o que justifica escalar o canal" },
  { titulo: "escalar-alcada",         cor: "#c62828", desc: "Precisa de decisão acima da operação (recompra, protesto, jurídico)" }
]

LABELS.each do |l|
  lbl = Label.find_or_initialize_by(title: l[:titulo], account_id: conta.id)
  novo_registro = lbl.new_record?
  lbl.description = l[:desc]
  lbl.color = l[:cor]
  lbl.show_on_sidebar = true
  lbl.save!
  log("label '#{l[:titulo]}' #{novo_registro ? 'criada' : 'já existia'}")
end

# ── Respostas rápidas (STORY-6.2) ──────────────────────────────────
# Sem variável de propósito. O Chatwoot substitui `{{contact.name}}` no momento
# em que a atendente insere a resposta pelo `/` (`editorHelper.js:489`), então o
# cliente nunca receberia a chave crua — mas o NOME do contato aqui vem do canal
# e é heterogêneo (medido: "comercial", "Financeiro lokaforte", um rótulo de
# número). "Olá comercial," sai pior do que não saudar.
#
# O que NÃO entra aqui: dados de pagamento (chave PIX, conta). São dado de
# negócio, mudam sem aviso, e uma chave errada versionada no repo vira dinheiro
# no lugar errado. Essa resposta o operador cria na tela — ver
# docs/runbook-operacao.md.
RESPOSTAS_RAPIDAS = [
  { atalho: "prazo",
    texto: "Perfeito, anotei o pagamento para o dia informado. Vou registrar aqui e retorno se houver qualquer divergência na baixa." },
  { atalho: "comprovante",
    texto: "Consegue nos enviar o comprovante por aqui, por favor? Com ele conseguimos dar baixa hoje mesmo e encerrar a cobrança." },
  { atalho: "2via",
    texto: "Claro, já providencio a segunda via do boleto atualizado e envio por aqui em seguida." },
  { atalho: "responsavel",
    texto: "Consegue nos indicar o contato do setor financeiro responsável por este pagamento? Assim falamos direto com quem resolve e paramos de incomodar você." },
  { atalho: "encerrar",
    texto: "Pagamento confirmado e baixado aqui. Obrigado pelo retorno — qualquer coisa, é só chamar por este mesmo número." }
]

RESPOSTAS_RAPIDAS.each do |r|
  cr = CannedResponse.find_or_initialize_by(short_code: r[:atalho], account_id: conta.id)
  novo_registro = cr.new_record?
  cr.content = r[:texto]
  cr.save!
  log("resposta rápida '/#{r[:atalho]}' #{novo_registro ? 'criada' : 'já existia'}")
end

log("pronto.")
