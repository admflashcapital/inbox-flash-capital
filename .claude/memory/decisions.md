# Decisões Arquiteturais — Inbox Flash Capital

> Condensado de `docs/architecture.md` (AD-1..AD-13). NÃO violar durante a implementação.
> Mudar exige atualizar o AD no doc, não uma decisão de sessão.

- **AD-1 — Chatwoot é espelho, nunca fonte da verdade de dado de domínio.**
  A verdade de **conversa** é do Chatwoot; a verdade de **negócio** é do Twenty/Supabase.
  Proibido: criar/editar dado autoritativo (contato de domínio, contrato, operação, cobrança) só na central.

- **AD-2 — Enriquecimento unidirecional e assíncrono (domínio → central).**
  O Serviço de Sync **só empurra** para o Chatwoot. A central **nunca** faz chamada síncrona aos bancos
  de domínio no caminho de atendimento. Domínio fora do ar degrada o enriquecimento, **não** o atendimento.

- **AD-3 — Identidade de contato por chave dupla (E.164 + documento).**
  Telefone normalizado para E.164, documento só dígitos, **antes** de casar.
  **Merge automático só quando telefone E documento casam.** Casando só uma chave → **sugestão de
  merge** (`pending`) para revisão humana; não altera o contato até aprovação.
  Essa regra vive **num lugar só**: o Serviço de Sync.

- **AD-4 — Um número = uma Inbox; provider é adapter plugável.**
  Cada canal entra por seu provider (Evolution/Twilio/Gmail) como Inbox distinta. O modelo
  Conversa/Contato do hub é **agnóstico de provider**. Proibido: lógica de canal vazando para o hub
  ou para o domínio.

- **AD-5 — Convivência multi-consumidor no número de prospecção via fan-out.**
  A instância Evolution **permanece no CRM** e faz fan-out: **N8N e Chatwoot recebem cada mensagem**.
  Não é fila competida. Entrega at-least-once; **consumidores idempotentes**.
  Proibido: um consumidor que "consome" o evento e some com ele.

- **AD-6 — Disparo em massa origina no monorepo; a central recebe o outbound por push.**
  O pipeline do monorepo, ao disparar, **também registra a mensagem outbound** na conversa via API do
  Chatwoot. Proibido: a central virar motor de campanha (fica com histórico parcial — só a resposta).

- **AD-7 — Chatwoot Community Edition, sem fork.**
  Imagem oficial com **tag fixa**. Extensão só via API/webhook/automação/atributo custom.
  Proibido: forkar; habilitar features da pasta `enterprise/` (licença comercial); usar `latest`.

- **AD-8 — Segredos fora do repo; webhooks autenticados; TLS sempre.**
  Tokens (Evolution/Twilio/Chatwoot/Gmail) em `.env`/secret store, nunca versionados.
  Todo webhook valida origem (assinatura `X-Twilio-Signature` no inbound Twilio; token compartilhado
  nos webhooks Evolution/Chatwoot). Tráfego externo só por TLS.

- **AD-9 — Banco da central isolado dos bancos de domínio.**
  Postgres próprio do Chatwoot; o Serviço de Sync tem seu próprio store de mapeamento de identidade
  (`identity_map`, `merge_suggestion`). Proibido: cross-DB com Twenty/Supabase.

## Guardrail de negócio (não é AD, mas é inegociável)

**Segmentação de risco de número.** Prospecção fria sai por **e-mail**. O número de prospecção é
**só inbound** (recepciona o lead pescado, manda o link do Jotform). Cobrança fica isolada no número
oficial. Cold outreach queima reputação — e um número queimado leva o canal de dinheiro junto.

**Modo espelho na prospecção (decisão de operação, 2026-07-13).** Na inbox `WhatsApp Prospecção`
quem responde o lead é o **Agente N8N**; a central **só espelha** (a atendente acompanha, não digita).
Enquanto não existir handoff, uma resposta digitada ali chegaria **em dobro** ao lead. Não é só
combinado: `MODO_ESPELHO_PROSPECCAO=true` faz `make aquecimento` **falhar** se aparecer resposta
digitada nessa inbox. O AC da STORY-2.1 ("responder pela central chega no lead") continua sendo a
capacidade técnica a provar — mas **só em contato de teste**.

**Service account não pluga no canal de e-mail (2026-07-14).** O Chatwoot só sabe o fluxo OAuth de
**usuário** (`grant_type=refresh_token`); service account usa JWT-bearer e nunca emite
`refresh_token`. Não há caminho de código. Ver `docs/runbook-canal-email.md`.

- **AD-10 — Infra é só `docker compose`; nada publica além de loopback.** `[2026-09-02]`
  `compose.yaml`/`.env`/`scripts/` na raiz; seed por `rails runner` encadeado com
  `service_completed_successfully`; `docker compose up -d --wait` é o comando único.
  **Nenhum serviço em `0.0.0.0`** — só `chatwoot-web` em `127.0.0.1:3001`.
  Proibido: Makefile, Caddy, `/etc/hosts`, rede `flash-canais`, proxy compartilhado com o CRM.
  Ingresso remoto = um `cloudflared` no compose **deste** repo.

- **AD-11 — A central nunca é site público.** `[2026-09-02]`
  A Twilio fala com o **monorepo**, não com a central; o e-mail é **polling IMAP de saída**.
  Só dois consumidores: navegador do colaborador (autenticado) e monorepo (máquina-a-máquina).
  O `Twilio::CallbackController` não valida assinatura → o gate do relay é obrigatório em qualquer
  exposição.

- **AD-12 — O painel é tão completo quanto o uptime de quem o alimenta.** `[2026-09-02]`
  O espelho **não tem retry, fila nem backfill**. Central inalcançável = **buraco permanente**, não
  atraso. Onde a central roda decide a completude do painel; sem uptime garantido, o painel é
  declarado **amostral** por escrito.

- **AD-13 — Sem Serviço de Sync: contexto carimbado no instante do disparo.** `[2026-09-02]`
  **EPIC-5 cancelado.** `titulo_id`/CNPJ/valor/atraso vão nos `custom_attributes` da conversa em
  `chatwoot_mirror.py::_garantir_conversa`. Supersede a premissa do AD-2/AD-3 de que a regra vive no
  Sync.
