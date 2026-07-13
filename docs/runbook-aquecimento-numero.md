# Runbook — Aquecimento e Proteção do Número de Prospecção

> **Story:** 2.3 · **FR-6** · Guardrail de negócio (não é um AD, mas é inegociável)

## Por que isto existe

O WhatsApp bloqueia número que se comporta como spammer. Os dois sinais mais fortes são **volume alto
num chip novo** e **iniciar conversa com quem nunca falou com você**.

A Flash tem **dois** números. Se o de prospecção for bloqueado, perdemos um canal de leads —
chato, recuperável. O perigo real é a contaminação: **número queimado leva o canal de dinheiro
junto** se os dois estiverem no mesmo padrão de comportamento. Por isso a segmentação é rígida:

| Número | Papel | Pode iniciar conversa? |
|---|---|---|
| **Prospecção** (chip pré-pago) | recepciona o lead pescado, manda o link do Jotform | **NÃO — só inbound** |
| **Oficial** (Meta/Twilio) | cobrança e transacional | sim, dentro das regras da Meta (template aprovado fora da janela de 24h) |

**Prospecção fria da Flash sai por E-MAIL.** Nunca por WhatsApp. Essa é a regra que protege os dois
números — e não tem exceção "só dessa vez".

## A rampa de aquecimento

Chip novo não sai disparando. A rampa abaixo é o teto de **mensagens enviadas por dia** (a maioria
delas sendo resposta do Agente a quem chegou):

| Semana | Teto diário de mensagens enviadas |
|---|---|
| 1 | 20 |
| 2 | 40 |
| 3 | 60 |
| 4 | 80 |
| 5+ | 100 (regime) |

Isso é folgado para o volume real da Flash (**5–20 leads/mês**): a rampa nunca vai ser o gargalo do
negócio. Ela existe para proteger o chip, não para acelerar a operação.

Registre a data do pareamento no `deploy/.env` — é dela que sai a semana atual:

```
NUMERO_PROSPECCAO_DESDE=2026-07-20
```

## A verificação (rode toda semana no início, depois todo mês)

```bash
make aquecimento     # = deploy/scripts/verificar-aquecimento.sh
```

Ele **falha** — e falhar aqui é o ponto — se:

1. **Alguma conversa foi iniciada por nós.** O script olha a primeira mensagem de cada conversa da
   inbox `WhatsApp Prospecção`: se for nossa, alguém puxou conversa com quem não nos procurou. Isso é
   outbound frio, e é o comportamento que queima o número.
2. **Existe campanha configurada na inbox.** A central **não** é motor de disparo (AD-6) — quem
   origina disparo em massa é o monorepo, e pelo número **oficial**.
3. **O volume enviado em 24h passou do teto da semana.**

## Boas práticas de operação (o que o Meta lê como "humano")

- **Responda rápido, mas não instantaneamente em massa.** O Agente já responde no fluxo natural.
- **Nunca** mande a mesma mensagem, copiada e colada, para muitos contatos em sequência.
- Mantenha uma **taxa de resposta alta**: número que fala muito e recebe pouca resposta é sinalizado.
- **Zero listas compradas.** O lead chega por prospecção pescada (e o primeiro contato é por e-mail).
- Peça ao lead para salvar o contato — conversa com número salvo tem outro peso.

## Se o número for bloqueado

1. **Não pareie o chip queimado em outra instância** e não migre a conversa para o número oficial —
   isso é a rota de contaminação que estamos tentando evitar.
2. Peça revisão no WhatsApp Business (o próprio app oferece o recurso).
3. Enquanto isso, a prospecção **continua por e-mail** — que é o canal frio de direito.
4. Chip novo = **rampa reinicia da semana 1**. Atualize `NUMERO_PROSPECCAO_DESDE`.
5. Registre o episódio aqui embaixo — padrão de bloqueio é informação operacional valiosa.

## Saúde da conexão

O chip cai (o Baileys reconecta, mas a sessão expira de tempos em tempos — é um risco assumido no
ADR-003 do CRM). Se a instância sair de `open`, a central para de receber **e** o Agente para de
responder:

```bash
# estado da instância (do host do CRM)
docker compose exec evolution-api sh -c 'wget -qO- --header="apikey: $AUTHENTICATION_API_KEY" \
  http://127.0.0.1:8080/instance/connectionState/crm'
```

O CRM já tem alerta de saúde do WhatsApp (`scripts/saude_whatsapp.py`, STORY-026 de lá). O
monitoramento da central entra na **STORY-6.3**.

## Registro de incidentes do número

| Data | O que aconteceu | Ação |
|---|---|---|
| — | — | — |
