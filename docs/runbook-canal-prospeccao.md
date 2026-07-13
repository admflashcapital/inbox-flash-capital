# Runbook — Canal WhatsApp Prospecção (Evolution)

> **Stories:** 2.1 (inbox espelhada) · **FR-4** · **AD-4** (um número = uma inbox) · **AD-5** (fan-out)
> A instância Evolution **mora no CRM** (`crm-flash-capital`) e continua sendo dele. A central só
> pede para ser espelhada.

## Como as peças se ligam

```
   lead (WhatsApp)
        │
        ▼
   Evolution (instância `crm`, no CRM)
        ├──────────────► N8N ........... o Agente: identifica o lead, manda o Jotform
        └──────────────► Chatwoot ...... a central: a atendente vê e responde
                            │
                            └── resposta ──► webhook /chatwoot/webhook/crm ──► WhatsApp do lead
```

**Não é fila competida (AD-5).** A Evolution dispara os dois no mesmo handler de mensagem: primeiro
`chatwootService.eventWhatsapp`, depois `sendDataWebhook`. O envio ao Chatwoot tem `try/catch`
próprio — **central fora do ar não impede o evento de chegar ao N8N**.

## Pré-requisitos (uma vez)

**1. A rede compartilhada** — é por ela que Evolution e Chatwoot se falam sem que nenhuma das duas
seja exposta na internet:

```bash
docker network create flash-canais
```

**2. No CRM** (`crm-flash-capital`): `CHATWOOT_ENABLED=true` no serviço `evolution-api` (já está no
compose) e `EVOLUTION_SERVER_URL` alcançável pelos consumidores. Suba a stack de lá.

**3. Na central:** `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` no `deploy/.env`.

> Sem esse último flag o canal **não funciona**, e o erro é silencioso na UI: o Chatwoot recusa
> chamar webhook e baixar mídia em host sem IP público (proteção anti-SSRF do `SafeFetch`), e a
> Evolution vive numa rede privada. A mensagem do atendente fica com status `failed` e o log diz
> `Invalid webhook URL ... has no public ip addresses`. O trade-off é consciente: a alternativa
> seria expor a Evolution na internet, o que é bem pior.

## Passo manual 1 — parear o chip (QR)

Ninguém automatiza isto: é um telefone físico.

```bash
# dev: a UI da Evolution está em https://evolution.localhost (vhost dev-only do Caddy do CRM)
# prod: NÃO exponha a Evolution. Use um túnel SSH:
ssh -L 8080:evolution-api:8080 usuario@host-do-crm
# e abra http://localhost:8080 no navegador
```

Crie/conecte a instância e leia o QR com o **chip de prospecção** (o pré-pago novo, nunca o número
oficial de cobrança). Confirme que ficou `open`:

```bash
docker compose exec evolution-api sh -c 'wget -qO- --header="apikey: $AUTHENTICATION_API_KEY" \
  http://127.0.0.1:8080/instance/connectionState/crm'
```

## Passo manual 2 — token de admin da central

A Evolution cria a inbox e posta as mensagens **como um admin do Chatwoot**. Na UI da central:
**Perfil → Access Token** → copie. Depois, no `deploy/.env` (nunca no chat, nunca no git):

```
CENTRAL_ACCESS_TOKEN=<o token>
CENTRAL_ACCOUNT_ID=1          # id da conta (a primeira criada costuma ser 1)
EVOLUTION_API_KEY=<a mesma AUTHENTICATION_API_KEY do CRM>
```

## Conectar

```bash
deploy/scripts/conectar-evolution.sh            # aplica a integração
deploy/scripts/conectar-evolution.sh --status   # confere o que está valendo
```

O script chama `POST /chatwoot/set/crm` com `autoCreate: true` — a **própria Evolution** cria a inbox
`WhatsApp Prospecção` no Chatwoot, do tipo `api`, com o `webhook_url` apontando de volta para ela.

Confira na central: **Configurações → Caixas de entrada** → `WhatsApp Prospecção`.

> **`importMessages` e `importContacts` ficam DESLIGADOS de propósito.** Esse recurso exige que a
> Evolution abra conexão **direta no Postgres da central** — violaria o AD-8 e o AD-9. O espelho
> começa do zero, daqui para a frente.

## Teste de aceite (o que fecha a STORY-2.1)

De **outro celular**, mande uma mensagem para o número de prospecção:

1. a conversa aparece na inbox `WhatsApp Prospecção`;
2. responda pela central → a resposta chega no WhatsApp do lead;
3. mande uma **foto ou PDF** → o anexo aparece na conversa;
4. o Agente N8N continua respondendo (saudação + link do Jotform) — e essas mensagens dele também
   aparecem na conversa da central (é o fan-out da STORY-2.2).

## ⚠️ Risco conhecido antes de pôr o número real no ar

**Dupla resposta.** O `WF-04-004` (N8N) responde automaticamente toda mensagem inbound com o LLM. Se
a atendente **também** responder pela central, o lead recebe **duas respostas** — uma do robô, uma da
humana. Isso não é um bug da integração: são dois cérebros no mesmo número.

O handoff (o Agente calar a boca quando um humano assume a conversa) é a **STORY-2.2**. Até lá, ou o
número fica em modo espelho (a atendente **só observa**), ou o Agente é desligado. **Não deixe os
dois ativos com tráfego real.**

## Diagnóstico

| Sintoma | Causa provável |
|---|---|
| Mensagem do atendente fica `failed`, log diz `has no public ip addresses` | falta `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` na central |
| A inbox não é criada | token da central sem permissão de admin, ou `CENTRAL_ACCOUNT_ID` errado |
| `contact not found` no log da Evolution | o contato não existe no lado dela — normal se a conversa nasceu na central; o fluxo real começa com o lead mandando mensagem |
| A resposta não sai no WhatsApp | a instância não está `open` — o chip desconectou, refaça o QR |
| A central não vê nada, mas o N8N vê | `CHATWOOT_ENABLED` desligado no CRM, ou a integração não foi aplicada nesta instância |
| Anexo não aparece | `EVOLUTION_SERVER_URL` inalcançável pela central (era `localhost:8080`?) — é dele que sai o link da mídia |

## Estado de verificação (2026-07-13, dev)

Verificado ao vivo, **sem o chip**: a rede compartilhada liga os dois (Evolution 2.3.7 ↔ Chatwoot
4.15.1); `conectar-evolution.sh` criou a inbox `WhatsApp Prospecção` (`Channel::Api`, webhook
`/chatwoot/webhook/crm`); a resposta digitada na central **chega** na Evolution; e a Evolution
**escreve de volta** na conversa da central usando o token (postou o aviso de falha de envio).

**Não verificável sem o número físico:** mensagem real do lead entrando, resposta chegando no
WhatsApp e mídia anexada. É o que o **Passo manual 1** destrava.
