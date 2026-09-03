# Runbook — LGPD na central de atendimento

> **O que este documento resolve:** a central guarda conversa de **cobrança**, com CPF/CNPJ, valor em
> aberto e inadimplência. Isso é dado pessoal de terceiro (o sacado), tratado por interesse legítimo na
> execução de um crédito. Este runbook diz por quanto tempo guardamos, como apagamos, quem alcança o
> quê — e onde o Chatwoot Community **não** nos ajuda, para ninguém prometer o que não existe.

## Retenção — decidida e agendada

| | |
|---|---|
| Política | conversas **resolvidas** com mais de **1825 dias (5 anos)** são apagadas |
| Onde vive | `RETENCAO_CONVERSAS_DIAS` no `.env` · `scripts/retencao-conversas.sh` |
| Agendamento | cron do host, **domingo 04:10**, com `flock`, log em `backups/retencao.log` |
| Aprovação | os 5 anos foram aprovados por escrito pelo operador em 2026-09-02 |

O prazo segue a prescrição civil comum de dívida: apagar antes destrói a prova da negociação de um
crédito em disputa; depois viola a minimização. **Conversa aberta ou pendente nunca é tocada por
idade** — só `status = resolved`.

O expurgo usa `destroy_all`, não `delete_all`: são os callbacks do ActiveRecord que removem os
**anexos** do volume `storage_data`. `delete_all` deixaria o arquivo órfão no disco — dado apagado do
banco e presente em disco é o pior dos dois mundos.

```bash
bash scripts/retencao-conversas.sh --simular    # conta, não apaga
bash scripts/retencao-conversas.sh --executar   # apaga
```

> ⚠️ **Esta máquina não fica ligada às 4h de domingo.** O cron existe e está correto; o que não existe é
> a garantia de que ele dispara. Trate como **passo que pode nunca rodar** até a central sair para um
> host que fica de pé. O `verificar-operacao.sh` cobra o cron *registrado*, não o cron *executado* — o
> `backups/retencao.log` é quem prova execução.

## Direito de exclusão do titular

Um titular (o sacado) pode pedir a exclusão dos seus dados. **A central é só uma das pontas** — o dado
de cobrança nasce no monorepo e pode existir no CRM. Apagar só aqui não atende o pedido e ainda dá
falsa sensação de conformidade.

### Passo 1 — localizar, sem apagar nada ainda

```bash
docker compose exec -T chatwoot-web bundle exec rails runner '
  doc = "12345678000199"     # CNPJ/CPF só dígitos, ou use o telefone E.164
  contatos = Contact.where("phone_number = ? OR email = ?", "+55...", "fulano@...")
  contatos.each do |c|
    convs = c.conversations
    puts "contato #{c.id} (#{c.name}) — #{convs.count} conversa(s), #{Message.where(conversation_id: convs.ids).count} mensagem(ns)"
  end
'
```

Também procure por documento nos atributos carimbados pelo disparo (AD-13):

```sql
SELECT id, inbox_id, custom_attributes->>'cnpj'
FROM conversations
WHERE custom_attributes->>'cnpj' = '12345678000199';
```

### Passo 2 — decidir, com quem tem alçada

A exclusão **não é automática**. Se houver cobrança viva, protesto ou disputa, a conservação pode ser
obrigação legal — e nesse caso a resposta ao titular é a recusa fundamentada, não o silêncio. Registre
quem decidiu e quando.

### Passo 3 — apagar na central

```bash
docker compose exec -T chatwoot-web bundle exec rails runner '
  c = Contact.find(123)
  c.conversations.find_each(&:destroy!)   # leva mensagens e anexos junto
  c.destroy!
'
```

`Conversation#destroy` também registra os `source_id` das mensagens de e-mail no
`Imap::DeletedMessageTracker` — sem isso o poller reimportaria a conversa apagada na próxima varredura,
e o dado voltaria sozinho.

### Passo 4 — as outras pontas

- **monorepo** (`internal.boletos`, contatos, régua): fonte da verdade do crédito. A exclusão lá é
  decisão separada e normalmente **não** procede enquanto o título existir.
- **CRM (Twenty)**: se o titular também for lead/contato comercial.
- **Twilio e Google**: a mensagem também existe no provedor. A Twilio retém logs de mensagem conforme a
  política dela; a caixa do Gmail guarda a thread. Apagar aqui não apaga lá.

### Passo 5 — os backups

O `backup.sh` mantém **7 diários + 4 semanais**. Um dado apagado hoje continua nos backups por até
**~4 semanas**, e isso é aceitável e esperado — restaurar um backup antigo, porém, **ressuscita o dado
apagado**. Se um restore acontecer depois de uma exclusão de titular, **refaça a exclusão**. Anote a
data da exclusão junto ao registro da decisão, exatamente para permitir essa conferência.

## Quem alcança o quê — e o teto do Community Edition

**Não existe papel customizado.** O Chatwoot CE tem dois papéis: `agent` e `administrator`
(`custom_roles` é premium e está desligado na imagem). Não há como criar "agente que atende mas não vê
o documento".

**O CPF/CNPJ é atributo da CONVERSA**, e a policy de atributos libera para `administrator? || agent?`.
Consequência direta e sem rodeio: **quem consegue abrir a conversa vê o documento.**

O único controle de acesso real é a **inbox**:

| Controle | Como funciona |
|---|---|
| Escopo de leitura | `inbox_members` — o agente só lista e abre conversas das inboxes de que participa |
| Exclusão de conversa | `ConversationPolicy#destroy?` = **administrator** apenas |
| Telas de configuração | escondidas para quem não é administrador |

Então: **um agente só deve entrar na inbox de que precisa.** `bash scripts/criar-agente.sh --inbox` é o
ponto onde essa decisão é tomada, e `verificar-operacao.sh` avisa quando um agente tem acesso a todas.

**Não há trilha de auditoria.** `audit_logs` é premium e está desligado: não é possível saber quem leu
o CPF de quem. Corrigir exigiria forkar o Chatwoot, o que o **AD-7** proíbe. Fica registrado como
limite conhecido, não como pendência.

**O `refresh_token` do Gmail fica em texto puro** no `provider_config` (jsonb, que o Chatwoot não
criptografa nem com `ACTIVE_RECORD_ENCRYPTION_*` ligado). Ele dá leitura e envio na caixa inteira e não
expira. Está no Postgres e **dentro de todo backup** — por isso o `BACKUP_DIR` é tratado como segredo.
Ao menor sinal, revogue em `myaccount.google.com/permissions`.

## Checagem

```bash
bash scripts/verificar-operacao.sh    # cobra os quatro crons e o escopo por inbox
bash scripts/monitorar-canais.sh --simular
```
