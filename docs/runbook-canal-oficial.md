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

Então o monorepo continua dono do webhook e faz **fan-out**:

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
`.env` da central:

```
TWILIO_ACCOUNT_SID=…            # = TWILIO_ACCOUNT_SID do monorepo
TWILIO_AUTH_TOKEN=…             # = TWILIO_AUTH_TOKEN do monorepo
TWILIO_NUMERO_OFICIAL=+55…      # = TWILIO_OFFICIAL_PHONE_NUMBER, em E.164, SEM `whatsapp:`
```

**2. O token do fan-out** (`openssl rand -hex 32`), o **mesmo** nos dois repos:

```
# central:  .env
RELAY_TOKEN=…
# monorepo: .env
CHATWOOT_RELAY_TOKEN=…          # idêntico
```

**3. Templates aprovados na Meta.** Os `HX…` que o monorepo já usa (lembrete de vencimento, alerta de
vencidos, protesto, confirmação). A central **não cria template** — ela sincroniza os que já existem.

## Conectar

```bash
bash scripts/conectar-twilio.sh          # cria a inbox `WhatsApp Oficial` + sincroniza os Content Templates
bash scripts/conectar-twilio.sh --status   # mostra o que está valendo (nunca imprime o auth_token)
bash scripts/verificar-canal-oficial.sh         # valida as invariantes do canal
```

O `conectar-twilio.sh` cria a inbox como `Channel::TwilioSms` com **`medium: whatsapp`**.

> **O `medium` é o detalhe que importa.** É ele que faz o Chatwoot aplicar a **janela de 24h**
> (`Conversations::MessageWindowService`). Criado como `sms`, não haveria janela: a atendente
> escreveria texto livre depois das 24h e a **Meta rejeitaria o envio** — falha silenciosa, no canal
> de cobrança. O `bash scripts/verificar-canal-oficial.sh` recusa qualquer medium que não seja `whatsapp`.
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

Os templates vêm da Content API da Twilio via `bash scripts/conectar-twilio.sh` (job assíncrono no Sidekiq). Aprovou um
template novo na Meta? Rode `scripts/conectar-twilio.sh --templates` para re-sincronizar.

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

Telefone fora de E.164 = thread partida. O `bash scripts/verificar-canal-oficial.sh` recusa número que não case
`^whatsapp:\+[0-9]{10,15}$`.

## Segurança do callback (AD-8)

**O `/twilio/callback` do Chatwoot NÃO valida a assinatura da Twilio.** O `Twilio::CallbackController`
só filtra os params e enfileira o job. Alcançável sem gate, qualquer um forja uma mensagem inbound na
conversa de um cliente real — e a central tem PII de verdade.

**Hoje** o inbound legítimo não passa por esse caminho de fora: ele chega ao monorepo (que valida
`X-Twilio-Signature`) e é relayado container-a-container pela rede `flash-espelho`, sem tocar em
porta publicada nem em túnel. Por isso negar o path na borda não custa funcionalidade nenhuma.

⚠️ **Isso muda com o monorepo no Railway.** Com a plataforma fora desta máquina, o relay passa a vir
**de fora**, e um Block incondicional mataria o espelho do inbound. A regra vira "só o espelho passa",
implementada como **Access Service Auth** — nunca como token literal numa expressão de WAF, que seria
uma quarta cópia do segredo. Ver `docs/fase-4-premissas.md` §2.1 e `docs/runbook-cloudflare.md` §2.2.

**Quem barra hoje:** o `deploy/ngrok-policy.yml`, na borda do túnel — `/twilio/callback` responde
**403** para qualquer origem externa. Verificado no plano free em 2026-09-02. Enquanto a central só
publicava em loopback a proteção era topológica (ninguém alcançava a porta); com o túnel da
`CENTRAL_URL_PUBLICA` ligado, ela passou a ser explícita, e é assim que fica.

O `RELAY_TOKEN` viaja no header `X-Relay-Token` a cada relay e é conferido por
`verificar-canal-oficial.sh` — mas **nada o exige na entrada**. Isso é aceitável só porque o path
está negado na borda. Um ingresso que abra o `/twilio/callback` sem exigir o header reabre o buraco:
o controller do Chatwoot não barra nada sozinho. Ver a especificação do ingresso em
`docs/runbook-deploy.md`.

O **`/twilio/delivery_status`** é o oposto e **precisa** ficar aberto — ver a seção seguinte. É a
própria Twilio que o chama, sem identidade, para as mensagens que a *central* envia. Forjá-lo só
altera o status de entrega de uma mensagem existente: sem leitura de dado, sem PII no corpo.

## Responder PELA central: o 21609 e o que o destravou

**O sintoma, medido em 2026-09-02 respondendo pela UI com a central em loopback:**

```
[HTTP 400] 21609 : The StatusCallback URL http://localhost:3001/twilio/delivery_status
                   is not a valid URL
```

**Por que acontece.** `Channel::TwilioSms#send_message` (`app/models/channel/twilio_sms.rb:66`) faz,
**sem condição nenhuma**:

```ruby
params[:status_callback] = twilio_delivery_status_index_url
```

Esse helper monta a URL a partir de `Rails.application.routes.default_url_options`, que o Chatwoot
preenche com **`FRONTEND_URL`**. A Twilio valida o callback **na criação da mensagem**: URL que ela
não alcança derruba o `messages.create` inteiro. Não é o callback que falha depois — **a mensagem nem
chega a sair**. Não há env var nem toggle para omitir o callback, e mexer no model exigiria fork
(proibido, AD-7).

**Como está resolvido.** O `FRONTEND_URL` do container é alimentado pela chave `CENTRAL_URL_PUBLICA`
do `.env`, que o `tuneis-manha.sh` do monorepo preenche com um túnel para a porta 3001 — o terceiro,
ao lado do da API e do Supabase. Com uma URL pública o `messages.create` passa e **a atendente
responde pela tela**. Verificado ao vivo em 2026-09-02, com o número oficial real.

Dois fatos que essa montagem depende, e que foram **medidos**, não supostos:

1. **A Twilio aceita um StatusCallback que devolve 404.** Ela valida se o host é publicamente
   alcançável, não se o path existe. Por isso o `ngrok-policy.yml` pode negar `/twilio/callback` sem
   tocar no `/twilio/delivery_status` — e por isso o item 2 da especificação do ingresso
   (`docs/runbook-deploy.md`) manda deixar esse path aberto.
2. **Rotacionar a `CENTRAL_URL_PUBLICA` NÃO quebra o canal de e-mail já autorizado.** O refresh do
   Gmail usa `grant_type=refresh_token`, que não passa `redirect_uri`. Trocamos a URL e os 9 checks
   do `verificar-canal-email.sh` seguiram verdes. O Google Cloud só precisa ser tocado de novo num
   **consent novo** — ver `docs/runbook-canal-email.md`, que traz a receita de localhost para isso.

**O que a URL de túnel ainda não é.** Ela muda a cada rodada do `tuneis-manha.sh`, então o custo é
reconfigurar o `.env` todo dia — automatizado pelo script, mas real. E o subdomínio fixo do plano
free **não existe**: `--url` com subdomínio próprio devolve `ERR_NGROK_313` ("Only paid plans may
create endpoints with custom subdomains"), medido em 2026-09-02. A troca por um domínio estável é o
ingresso da Fase 4; até lá isto opera.

## ⚠️ O webhook do Twilio é a peça que mais apodrece

**Sintoma:** a mensagem chega na Twilio (`status=received`) mas **nada acontece** — nem no monorepo,
nem na central. Nenhum log, nenhum erro. Silêncio.

**Onde olhar:** a própria Twilio guarda o motivo. Erro **11200** = "falha ao chamar o webhook".

```bash
# Mensagens recentes (mostra o error_code do inbound):
curl -su "$SID:$TOKEN" "https://api.twilio.com/2010-04-01/Accounts/$SID/Messages.json?PageSize=10"
# O detalhe do erro — inclui a URL EXATA que a Twilio tentou chamar:
curl -su "$SID:$TOKEN" "https://monitor.twilio.com/v1/Alerts?PageSize=5"
```

Foi assim que descobrimos, em 13/07, que o webhook apontava para um túnel ngrok **morto desde 03/07**
— e que, portanto, a **confirmação de sacado por resposta de WhatsApp nunca funcionou em produção**.
E depois, que uma correção no console tinha **duplicado o caminho**
(`/webhooks/twilio/inbound/webhooks/twilio/inbound`).

**A URL do ngrok free muda a cada reinício do túnel** — e o subdomínio fixo **não é uma saída**:
`--url` com subdomínio próprio devolve `ERR_NGROK_313` ("Only paid plans may create endpoints with
custom subdomains"), medido em 2026-09-02.

O que fecha o laço hoje é o **`tuneis-manha.sh` do monorepo**: ele sobe os três túneis, grava a URL
nos `.env` dos repos que a consomem, recria os containers que precisam reler o ambiente e **escreve
o webhook no console da Twilio** (`scripts/tuneis_twilio.py`). O modo de falha que custou 10 dias em
silêncio deixou de depender de alguém lembrar.

### São DOIS webhooks no mesmo número, e o do WhatsApp é o que decide

O console da Twilio guarda **duas configurações independentes** para `+553123916846`:

| Recurso | Campos | Governa | Onde no console |
|---|---|---|---|
| `IncomingPhoneNumber` (`PN…`) | `SmsUrl` · `StatusCallback` | **SMS e voz** | Phone Numbers → o número |
| `Channels/Senders` (`XE…`) | `callback_url` · `status_callback_url` | **WhatsApp** | Messaging → Senders → WhatsApp senders |

**Medido em 2026-09-04:** o script escrevia só o primeiro. O número mostrava o túnel do dia e o
sender, um de dois dias antes — apontando para um ngrok morto. Como todo o tráfego da Flash é
`whatsapp:`, **é o sender que decide se a resposta do cliente chega**. O script passou a escrever os
dois e a **conferir por releitura**: sem reler, uma escrita que não pega vira um `✔` mentiroso, que
foi exatamente como o defeito passou despercebido.

Conferir a qualquer momento, sem escrever nada:

```bash
cd ../monorepo-flash-capital && TUNEIS_TWILIO=conferir python3 scripts/tuneis_twilio.py
```

Isso não elimina a causa, só a automatiza. O conserto de verdade é um **domínio estável** — o
ingresso da Fase 4.

## Testar o canal sem depender de um celular

Dá para provar tudo o que está sob nosso controle **sem enviar WhatsApp**: basta forjar a chamada da
Twilio com uma assinatura válida — é o mesmo HMAC que ela calcula.

```python
base = URL + "".join(k + params[k] for k in sorted(params))
assinatura = base64.b64encode(hmac.new(AUTH_TOKEN.encode(), base.encode(), hashlib.sha1).digest())
# POST para a URL PÚBLICA (a mesma do webhook), com o header X-Twilio-Signature
```

Isso exercita ngrok → monorepo → validação de assinatura → confirmação de sacado → relay → central.
Use um telefone **falso** no `From`: assim a confirmação de sacado não acha disparo correspondente e
vira no-op, sem tocar em dado real. O único elo que sobra sem prova é a Twilio conseguir chamar a URL
— e para isso os Alerts (acima) já dizem a verdade.

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
- [ ] `bash scripts/verificar-canal-oficial.sh` verde.

## ✅ Estado: gate verificado ao vivo (2026-07-13)

Com o número oficial real (`+55 31 2391-6846`) e a conta Twilio de produção:

- mensagem do cliente → inbox `WhatsApp Oficial` (`source_id` = SID da Twilio);
- resposta digitada na central → **entregue** no WhatsApp do cliente;
- espelho de um disparo → aparece na conversa do contato, e a **Twilio não recebeu nenhuma cópia**:
  o guard do `source_id` segurou **com credencial real**. Cobrança em dobro não acontece.
- inbound e espelho resolvem o **mesmo `contact_inbox`** (`whatsapp:+E164`) → mesma thread.

**Não exercitado:** envio por template **fora** da janela de 24h (o mecanismo está provado — o
`can_reply?` fecha sem inbound e reabre com ele, e os 10 templates estão sincronizados —, mas o envio
real exige 24h de silêncio do cliente).

> ⚠️ **O espelho ainda NÃO está no caminho de produção.** O `mirror_outbound` e o `relay_inbound`
> vivem na branch **`feat/espelho-chatwoot`** (commit `c3d5438`) do `monorepo-flash-capital` — **não
> mergeada na `main` de lá**. O gate acima foi provado ao vivo rodando essa branch. Enquanto não
> houver **merge + deploy no monorepo**, a central **não recebe** o inbound relayado nem o espelho dos
> disparos em produção. É a pendência que fecha o EPIC-3 de verdade.

## Identidade: telefone e BSUID convivem

O inbound real criou **dois** `contact_inbox` para o mesmo contato:

| `source_id` | origem |
|---|---|
| `whatsapp:+553182210297` | telefone (E.164) — é o que o **espelho do monorepo** usa |
| `whatsapp:BR.4456758834604506` | **BSUID**, o identificador novo da Meta (`ExternalUserId` da Twilio) |

Ambos apontam para o mesmo Contato, e o Chatwoot **prefere o do telefone**
(`twilio_whatsapp_primary_source_id`) — por isso disparo e resposta casam hoje.

O risco: a Meta está migrando para payloads **só com BSUID** (o Chatwoot já trata esse caso). Quando o
`From` vier sem telefone, o inbound resolveria o `contact_inbox` do BSUID enquanto o espelho continua
criando o do telefone — **mesmo contato, threads separadas**. Está na dívida técnica; se aparecer
conversa duplicada para o mesmo cliente, é aqui que se olha.

## Diagnóstico

| Sintoma | Causa provável |
|---|---|
| Mensagem chega na Twilio (`status=received`) e **nada acontece**, sem log em lugar nenhum | erro **11200**: a Twilio não conseguiu chamar o webhook. Veja os Alerts — eles dizem a URL exata que ela tentou |
| A confirmação de sacado parou de funcionar | o webhook do número foi repontado para o Chatwoot. Ele deve apontar para o **monorepo** |
| Mensagem do cliente não aparece na central | o relay do monorepo não está entregando. Com os dois na mesma máquina: confira se `fastapi_api` e `chatwoot-web` estão ambos na rede `flash-espelho`. Com o monorepo no Railway: confira o `CHATWOOT_URL` público e se o Access deixa o espelho passar (uma página de login HTML com **200** engana o `raise_for_status()`). Nos dois casos, confira `CHATWOOT_MIRROR_ENABLED` — o espelho falha em silêncio (AD-12) |
| O cliente recebeu a cobrança **duas vezes** | o push do monorepo foi feito **sem `source_id`** — a central reenviou. Ver § "O disparo não pode sair duas vezes" |
| Fora das 24h a atendente escreve e a mensagem falha | a inbox foi criada com `medium: sms` — sem janela. Recrie com `whatsapp` |
| A UI não oferece template nenhum | templates não sincronizados: `conectar-twilio.sh --templates` |
| Resposta do cliente abre conversa NOVA em vez de cair na thread | `contact_inbox.source_id` fora do formato `whatsapp:+E164` no push do monorepo |
| `bash scripts/conectar-twilio.sh` falha com erro de credencial | o Chatwoot testa a credencial (`client.messages.list`) antes de criar a inbox — SID/token errados |
| Chamada à API da central dá **401** com token válido | proxy no caminho descartando header com underscore. Falando direto com `127.0.0.1:${CHATWOOT_HOST_PORT}` isso não acontece |
| Webhook do Twilio devolve **403** no monorepo | `PUBLIC_BOLETO_BASE_URL` diferente da URL pública real (ngrok): a assinatura é validada contra a URL reconstruída dela |
