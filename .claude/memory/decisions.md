# Decisões Arquiteturais — Inbox Flash Capital

> Condensado de `docs/architecture.md` (AD-1..AD-15). NÃO violar durante a implementação.
> Mudar exige atualizar o AD no doc, não uma decisão de sessão.

- **AD-1 — Chatwoot é espelho, nunca fonte da verdade de dado de domínio.**
  A verdade de **conversa** é do Chatwoot; a verdade de **negócio** é do Twenty/Supabase.
  Proibido: criar/editar dado autoritativo (contato de domínio, contrato, operação, cobrança) só na central.

- **AD-2 — Enriquecimento unidirecional e assíncrono (domínio → central).**
  O domínio **só empurra** para o Chatwoot — hoje pelo `chatwoot_mirror.py` do monorepo, no instante
  do disparo (AD-13). A central **nunca** faz chamada síncrona aos bancos de domínio no caminho de
  atendimento. Domínio fora do ar degrada o enriquecimento, **não** o atendimento. **O inverso não
  vale:** central fora do ar perde o evento para sempre (AD-12).

- **AD-3 — Identidade de contato por chave dupla (E.164 + documento).**
  Telefone normalizado para E.164, documento só dígitos, **antes** de casar.
  A regra vive **num lugar só**: `chatwoot_mirror.py` (`_garantir_contato`/`_garantir_conversa`) no
  monorepo. A **sugestão de merge** era função do Serviço de Sync e **não existe** (AD-13): o contato
  é resolvido pelo E.164 que a Twilio devolve no disparo.

- **AD-4 — Um número = uma Inbox; provider é adapter plugável.**
  Cada canal entra por seu provider (Twilio/Gmail) como Inbox distinta. O modelo
  Conversa/Contato do hub é **agnóstico de provider**. Proibido: lógica de canal vazando para o hub
  ou para o domínio.

- **AD-5 — ~~Fan-out no número de prospecção~~** `[SUPERSEDED 2026-09-02 — ver AD-11]`
  A Evolution saiu dos dois repos e o EPIC-2 foi cancelado. Nada de fan-out, nada de segundo número.

- **AD-6 — Disparo em massa origina no monorepo; a central recebe o outbound por push.**
  O pipeline do monorepo, ao disparar, **também registra a mensagem outbound** na conversa via API do
  Chatwoot. Proibido: a central virar motor de campanha (fica com histórico parcial — só a resposta).

- **AD-7 — Chatwoot Community Edition, sem fork.**
  Imagem oficial com **tag fixa**. Extensão só via API/webhook/automação/atributo custom.
  Proibido: forkar; habilitar features da pasta `enterprise/` (licença comercial); usar `latest`.

- **AD-8 — Segredos fora do repo; webhooks autenticados; TLS sempre.**
  Tokens (Twilio/Chatwoot/Gmail) no `.env`, nunca versionados; lidos por `env_get` de
  `scripts/lib/env.sh` — **nunca `source`**, para segredo não entrar no ambiente do processo.
  A assinatura `X-Twilio-Signature` é validada **no monorepo**, dono do webhook; o relay para a
  central leva `X-Relay-Token`. O TLS do tráfego externo é terminado pela **borda** (hoje o túnel da
  `CENTRAL_URL_PUBLICA`, amanhã o ingresso da Fase 4), nunca pelo Chatwoot — por isso `FORCE_SSL`
  segue `false`.

- **AD-9 — Banco da central isolado dos bancos de domínio.**
  Postgres próprio do Chatwoot. Proibido: cross-DB com Twenty/Supabase — verificado por
  `verificar-invariantes.sh` (sem `dblink`/`postgres_fdw`, usuário não-superusuário, nenhuma
  credencial de banco de domínio no `.env`). O `identity_map`/`merge_suggestion` do Sync **não
  existe** (AD-13).

## Guardrail de negócio (não é AD, mas é inegociável)

**Segmentação de risco de número.** Prospecção fria sai por **e-mail**, nunca por WhatsApp. Cold
outreach queima reputação — e um número queimado levaria o canal de dinheiro junto. Foi para
proteger isso que existiu o número de prospecção com a Evolution; com o EPIC-2 cancelado o guardrail
fica pela via mais simples: **a central só tem o número oficial**.

**Service account não pluga no canal de e-mail (2026-07-14).** O Chatwoot só sabe o fluxo OAuth de
**usuário** (`grant_type=refresh_token`); service account usa JWT-bearer e nunca emite
`refresh_token`. Não há caminho de código. Ver `docs/runbook-canal-email.md`.

- **AD-10 — Infra é só `docker compose`; nada publica além de loopback.** `[2026-09-02]`
  `compose.yaml`/`.env`/`scripts/` na raiz; seed por `rails runner` encadeado com
  `service_completed_successfully`; `docker compose up -d --wait` é o comando único.
  **Nenhum serviço em `0.0.0.0`** — só `chatwoot-web` em `127.0.0.1:3001`.
  Proibido: Makefile, Caddy, `/etc/hosts`, rede `flash-canais`, proxy compartilhado com o CRM.
  Ingresso remoto = um `cloudflared` no compose **deste** repo.

- **AD-11.1 — Responder pelo WhatsApp exige `FRONTEND_URL` pública.** `[MEDIDO 2026-09-02]`
  `Channel::TwilioSms#send_message` anexa `status_callback` **sem condição**, e a Twilio valida a
  URL na CRIAÇÃO: em loopback o envio morre com **21609** e a mensagem nem sai. Sem toggle; omitir
  exigiria fork (AD-7). Por isso o `FRONTEND_URL` do container vem de `CENTRAL_URL_PUBLICA`
  (o `compose.yaml` falha o boot sem ela). **Toda exposição tem de negar `/twilio/callback` e deixar
  `/twilio/delivery_status` aberto** — `verificar-canal-oficial.sh` cobra os dois ao vivo.
  Medido: a Twilio aceita callback que devolve **404** (valida o host, não o path); e rotacionar a
  URL **não** quebra o e-mail já autorizado (o refresh usa `grant_type=refresh_token`, sem
  `redirect_uri`).

- **AD-11 — A central nunca é site público.** `[2026-09-02]`
  A Twilio fala com o **monorepo**, não com a central; o e-mail é **polling IMAP de saída**.
  Só dois consumidores: navegador do colaborador (autenticado) e monorepo (máquina-a-máquina).
  O `Twilio::CallbackController` não valida assinatura → o gate do relay é obrigatório em qualquer
  exposição. "Nunca público" = **nenhuma superfície anônima de conversa**; não "nenhum pacote entra"
  (ver AD-11.1).

- **AD-12 — O painel é tão completo quanto o uptime de quem o alimenta.** `[2026-09-02]`
  O espelho **não tem retry, fila nem backfill**. Central inalcançável = **buraco permanente**, não
  atraso. Onde a central roda decide a completude do painel; sem uptime garantido, o painel é
  declarado **amostral** por escrito.

- **AD-13 — Sem Serviço de Sync: contexto carimbado no instante do disparo.** `[2026-09-02]`
  **EPIC-5 cancelado.** O conjunto fechado de 8 — `titulo_id`, `cnpj`, `cedente`, `numero_nf`,
  `data_vencimento`, `valor_em_aberto`, `dias_atraso`, `link_boleto` — vive em
  `atributos.py::CHAVES` (monorepo) e precisa das 8 `CustomAttributeDefinition` do
  `chatwoot_seed.rb`, senão o valor é gravado e fica **invisível**. Só atributo do TÍTULO entra:
  estado da régua seria apagado pelo disparo seguinte. Vai nos `custom_attributes` da conversa, por
  `chatwoot_mirror.py::_carimbar_atributos` — etapa **separada**, depois que `conversa_id` foi
  resolvido. **Não** dentro de `_garantir_conversa`: ele tem duas saídas (reuso e criação) e o reuso
  é o caminho comum, então carimbar na criação passa no teste e não entrega nada. O endpoint
  **substitui** o hash inteiro, não mescla. Supersede a premissa do AD-2/AD-3 de que a regra vive no
  Sync.

- **AD-14 — Quem restringe acesso é a INBOX, não o papel.** `[MEDIDO 2026-09-03]`
  O CE tem **dois** papéis (`agent`, `administrator`); `custom_roles` é premium, está desligado e o
  modelo **não existe na imagem** — ligar exigiria fork (AD-7). E o CPF/CNPJ é atributo da
  **conversa**, liberado pela policy para `administrator? || agent?`: **quem abre a conversa vê o
  documento**. Logo não existe "agente que atende sem ver o CPF". O escopo real é `inbox_members`
  (`User#assigned_inboxes` → `InboxPolicy::Scope` → `ConversationFinder`); `destroy?` de conversa é
  só de admin; e **não há trilha de auditoria** (`audit_logs` é premium). Um agente entra apenas nas
  inboxes de que precisa (`criar-agente.sh --inbox`), e `verificar-operacao.sh` cobra isso. O gate do
  EPIC-6 foi reescrito de "restrito por papel" para "restrito por inbox".

- **AD-15 — A fronteira pública é um Cloudflare Tunnel sobre a máquina do escritório.** `[2026-09-03]`
  A central roda **na máquina do escritório**, 24h, e é alcançada por um `cloudflared` **no compose
  deste repo**, num **domínio novo** cuja zona vive na Cloudflare (plano gratuito).
  `flashcapital.com.br` **não é tocado**: a zona serve o site institucional e os hosts do Railway, e a
  delegação de NS que o Tunnel exige é exclusiva. Descartados com número: Partial Setup por CNAME =
  **US$ 200/mês**; zona filha só em Enterprise; VPS com proxy próprio reintroduz o proxy que o AD-10
  cortou; PaaS perde a base de configuração dos scripts Docker. **Isto não decide disponibilidade** —
  máquina de escritório cai, e cada minuto fora é buraco permanente (AD-12); o tratamento é
  `docs/plano-resiliencia.md`. **Decidido e especificado, NÃO executado**: falta comprar o domínio e
  conferir os seis limites do plano gratuito. A especificação da borda **não muda** com a troca de
  túnel: negar `/twilio/callback`, deixar `/twilio/delivery_status` alcançável (AD-11.1) e cobrar a
  identidade do relay na entrada.

- **A janela de 24h é NATIVA — e protege a tela, não a API.** `[MEDIDO 2026-09-03]`
  `Conversations::MessageWindowService` devolve 24h para `Channel::TwilioSms` **se e somente se**
  `medium == 'whatsapp'`: passadas 24h o editor fecha, aparece banner em pt-BR e a UI só oferece os
  Content Templates. Mas `Base::SendOnChannelService` e o `MessagesController` **não** consultam
  `can_reply?`, e o `Twilio::SendOnTwilioService` não tem o fallback-para-template do canal WhatsApp
  Cloud. Quem posta pela API passa fora da janela e só falha na Twilio. **Regra: o chamador checa
  antes.** (O `PROGRESS.md` afirmou por semanas que a janela "não estava modelada em ponto nenhum";
  era falso para a tela.)
