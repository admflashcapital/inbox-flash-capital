# Runbook — Canal WhatsApp Oficial (Twilio/Meta)

> **Stories:** 3.1 (inbox oficial espelhada) · 3.2 (espelho dos disparos) · **FR-7, FR-8** · **AD-4**
> (um número = uma inbox) · **AD-6** (o disparo em massa origina no monorepo) · **AD-8** (webhook
> autenticado)
>
> Este é o canal de **dinheiro**: cobrança e transacional. O número, as credenciais Twilio e os
> templates aprovados na Meta **já existem e são do monorepo**. A central só **espelha**.

## Quem é dono de quê — e por que o webhook fica no monorepo

O ponto que decide toda a arquitetura deste épico: **um número Twilio tem UM único webhook de
inbound**, e ele **já tem dono**.

O monorepo recebe o inbound em `POST /webhooks/twilio/inbound` (`api/routers/twilio_webhooks_router.py`),
valida o `X-Twilio-Signature` e usa a resposta do cliente para a **confirmação de sacado**
(`confirmado` / `recusado` → `internal.confirmacoes_disparos`). Apontar o Twilio para o Chatwoot
**quebraria a confirmação de cobrança**.

A alternativa oposta — o Chatwoot receber e avisar o monorepo — seria pior: colocaria a confirmação
de **dinheiro** refém da disponibilidade de uma ferramenta de **chat**. É exatamente o que a regra de
ouro proíbe.

Então o monorepo continua dono do webhook e faz **fan-out**, no mesmo padrão do canal de prospecção:

```
   cliente (WhatsApp)
        │
        ▼
   Twilio ──webhook──► MONOREPO  /webhooks/twilio/inbound
                          │  (valida a assinatura — AD-8)
                          ├──► confirmação de sacado ....... como sempre foi
                          └──► relay ──► CENTRAL /twilio/callback   (espelho)

   disparo de cobrança:
   MONOREPO ──Twilio──► cliente          (o motor de disparo continua aqui — AD-6)
        └──push API──► CENTRAL           (espelha o outbound na conversa certa)
```

**Assimetria proposital:** central fora do ar → o espelho perde mensagens; a **cobrança não para**.
O inverso nunca acontece.

## Pré-requisitos

**1. As credenciais Twilio são as MESMAS do monorepo.** Não crie conta nova nem gere token novo —
dois tokens para a mesma conta só multiplicam o que precisa ser rotacionado. Copie de lá para o
`deploy/.env` da central:

```
TWILIO_ACCOUNT_SID=…            # = TWILIO_ACCOUNT_SID do monorepo
TWILIO_AUTH_TOKEN=…             # = TWILIO_AUTH_TOKEN do monorepo
TWILIO_NUMERO_OFICIAL=+55…      # = TWILIO_OFFICIAL_PHONE_NUMBER, em E.164, SEM `whatsapp:`
```

**2. O token do fan-out** (`openssl rand -hex 32`), o **mesmo** nos dois repos:

```
# central:  deploy/.env
RELAY_TOKEN=…
# monorepo: .env
CHATWOOT_RELAY_TOKEN=…          # idêntico
```

**3. Templates aprovados na Meta.** Os `HX…` que o monorepo já usa (lembrete de vencimento, alerta de
vencidos, protesto, confirmação). A central **não cria template** — ela sincroniza os que já existem.

## Conectar

```bash
make twilio          # cria a inbox `WhatsApp Oficial` + sincroniza os Content Templates
make twilio-status   # mostra o que está valendo (nunca imprime o auth_token)
make oficial         # valida as invariantes do canal
```

O `conectar-twilio.sh` cria a inbox como `Channel::TwilioSms` com **`medium: whatsapp`**.

> **O `medium` é o detalhe que importa.** É ele que faz o Chatwoot aplicar a **janela de 24h**
> (`Conversations::MessageWindowService`). Criado como `sms`, não haveria janela: a atendente
> escreveria texto livre depois das 24h e a **Meta rejeitaria o envio** — falha silenciosa, no canal
> de cobrança. O `make oficial` recusa qualquer medium que não seja `whatsapp`.
>
> Efeito colateral bem-vindo: o `TwilioChannelsController` do Chatwoot só reconfigura o webhook do
> número quando o canal é `sms` (`setup_webhooks if @twilio_channel.sms?`). Com `whatsapp`, **ele não
> encosta no webhook** — o do monorepo continua intacto.

## A janela de 24h e os templates (FR-7)

Comportamento **nativo** do Chatwoot, nada foi construído:

| Situação | O que a central faz |
|---|---|
| última mensagem do cliente há **< 24h** | `can_reply? = true` → a atendente responde **texto livre** |
| **> 24h** sem mensagem do cliente | `can_reply? = false` → o campo de texto fecha; a UI só oferece os **Content Templates** aprovados |

Os templates vêm da Content API da Twilio via `make twilio` (job assíncrono no Sidekiq). Aprovou um
template novo na Meta? Rode `deploy/scripts/conectar-twilio.sh --templates` para re-sincronizar.

## ⚠️ O disparo não pode sair duas vezes (STORY-3.2)

O risco real deste épico: o monorepo dispara a cobrança pela Twilio **e** a central, ao espelhar o
outbound, dispara **de novo**. O cliente receberia a cobrança em dobro.

**O que impede:** `Base::SendOnChannelService#invalid_message?` pula o envio quando a mensagem já tem
`source_id`. O monorepo espelha o disparo **com o `MessageSid` que a Twilio devolveu** — a mensagem
aparece na conversa e **não é reenviada**.

Isso foi **provado ao vivo** (2026-07-13, dev), com credencial Twilio **falsa** de propósito:

| Mensagem | `source_id` | Resultado |
|---|---|---|
| espelho do disparo | `SM…` | `sent` — o Chatwoot **não chamou a Twilio** |
| digitada na central | nenhum | `failed` — `[HTTP 401] 20003 Authentication Error` |

A de controle **tentou** enviar e quebrou nas credenciais falsas; a espelhada passou intacta. É o
contraste que prova o guard. **Regra:** todo push de outbound do monorepo carrega o `source_id`. Sem
ele, a central reenvia.

## Identidade da thread — como disparo e resposta se encontram

O `contact_inbox.source_id` precisa ser **exatamente** `whatsapp:+E164` — é o formato que a Twilio usa
no `From`/`To`. O monorepo cria a conversa com esse `source_id`; quando o cliente responde, o
`Twilio::IncomingMessageService` resolve o mesmo `contact_inbox` e a resposta cai na **mesma
conversa**. Verificado ao vivo: disparo espelhado + resposta simulada aterrissaram na mesma thread.

Telefone fora de E.164 = thread partida. O `make oficial` recusa número que não case
`^whatsapp:\+[0-9]{10,15}$`.

## Segurança do callback (AD-8)

**O `/twilio/callback` do Chatwoot NÃO valida a assinatura da Twilio.** O `Twilio::CallbackController`
só filtra os params e enfileira o job. Exposto na internet, qualquer um forja uma mensagem inbound na
central.

Como o inbound legítimo chega pelo **relay do monorepo** (que já validou a assinatura), o Caddy barra
esse path para o mundo:

```
@callback_sem_token {
    path /twilio/callback*
    not header X-Relay-Token "{$RELAY_TOKEN:relay-token-nao-configurado}"
}
respond @callback_sem_token 403
```

Falha fechada: sem `RELAY_TOKEN` no `.env`, o default não casa com nada e todo POST leva 403.
Verificado: sem token → 403 · token errado → 403 · token certo → 204.

O **`/twilio/delivery_status` continua aberto** — é a própria Twilio que o chama, do IP dela, para as
mensagens que a *central* envia. Forjá-lo só altera o status de entrega de uma mensagem existente
(baixo impacto). Está registrado na dívida técnica.

## Teste de aceite (o que fecha o EPIC-3)

Com o número oficial real e o fan-out do monorepo no ar:

- [ ] cliente manda mensagem ao número oficial → aparece na inbox `WhatsApp Oficial`;
- [ ] a **confirmação de sacado** no monorepo **continua funcionando** (o fan-out não pode ter roubado
      o webhook — este é o teste de não-regressão mais importante do épico);
- [ ] responder pela central **dentro** da janela de 24h → chega no WhatsApp do cliente;
- [ ] **fora** da janela → o campo de texto fecha e a UI oferece os templates aprovados; o envio por
      template chega;
- [ ] disparo de cobrança pelo pipeline do monorepo → aparece como **outbound** na conversa certa,
      **uma vez só** (o cliente não recebe em dobro);
- [ ] a resposta do cliente ao disparo cai na **mesma thread**;
- [ ] `make oficial` verde.

## Diagnóstico

| Sintoma | Causa provável |
|---|---|
| A confirmação de sacado parou de funcionar | o webhook do número foi repontado para o Chatwoot. Ele deve apontar para o **monorepo** |
| Mensagem do cliente não aparece na central | o relay do monorepo não está entregando: `RELAY_TOKEN` diferente entre os dois `.env` (→ 403 no Caddy) |
| O cliente recebeu a cobrança **duas vezes** | o push do monorepo foi feito **sem `source_id`** — a central reenviou. Ver § "O disparo não pode sair duas vezes" |
| Fora das 24h a atendente escreve e a mensagem falha | a inbox foi criada com `medium: sms` — sem janela. Recrie com `whatsapp` |
| A UI não oferece template nenhum | templates não sincronizados: `conectar-twilio.sh --templates` |
| Resposta do cliente abre conversa NOVA em vez de cair na thread | `contact_inbox.source_id` fora do formato `whatsapp:+E164` no push do monorepo |
| `make twilio` falha com erro de credencial | o Chatwoot testa a credencial (`client.messages.list`) antes de criar a inbox — SID/token errados |
