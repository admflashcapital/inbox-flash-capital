# Inbox Flash Capital — Progress Tracker

> Para iniciar sessão: "Leia o CLAUDE.md e o PROGRESS.md, continue da próxima story pendente."
> Atualizado pelo Claude Code via `/done`. Detalhe de cada story em `docs/epics-and-stories.md`.

**Legenda:** `[ ]` pendente · `[~]` em andamento · `[x]` concluída · `[!]` bloqueada

**Milestones:** M1 = EPIC-1 · M2 = EPIC-2 + 3 + 4 (canais) · M3 = EPIC-5 (sync) · M4 = EPIC-6 (go-live).
O EPIC-1 bloqueia tudo. Os EPICs 2/3/4 podem correr em paralelo depois dele. O EPIC-5 precisa de ≥1 canal vivo.
Cada épico tem um gate de saída — use `/gate EPIC-N`.

**Progresso total:** 8 / 19 stories `[x]`, +2 em `[~]` e 1 em `[!]`.
**M1 (EPIC-1) concluído** — a central está no ar. **EPIC-3 concluído e verificado ao vivo** — o número
oficial recebe, responde e espelha os disparos, com o número real de produção. **STORY-4.1 concluída e
verificada ao vivo** — a caixa `operacional@` recebe e responde pela central, na mesma thread.

As 3 stories abertas estão travadas em coisas que **não são código**:

| Story | Espera |
|---|---|
| 2.1 · 2.2 `[~]` | **parear o chip físico** pelo QR (`docs/runbook-canal-prospeccao.md`) |
| 4.2 `[!]` | o **EPIC-5** — a resolução de identidade (AD-3) vive só no Serviço de Sync. Bloqueio de **desenho**, previsto desde o planejamento |

**Próximo trabalho real: EPIC-5 (Serviço de Sync).** É o que destrava a 4.2 (e portanto fecha o
EPIC-4), e é o **único componente construído do zero** — TDD obrigatório.

---

## EPIC-1 — Fundação da Plataforma

Chatwoot self-hosted na infra da Flash: deploy reproduzível, banco isolado, versão fixada, backup validado.

| # | Story | Status | Commit |
|---|---|---|---|
| 1.1 | Stack Docker da central sobe com um comando (FR-1) | [x] | |
| 1.2 | Banco da central isolado dos bancos de domínio (FR-1, AD-9) | [x] | |
| 1.3 | Versão fixada e procedimento de upgrade (FR-2) | [x] | |
| 1.4 | Backup e restore validados (FR-3) | [x] | |

**Gate EPIC-1:** `docker compose up -d` sobe web + Sidekiq + Postgres/pgvector + Redis + Caddy; UI do Chatwoot responde em HTTPS com cert válido; dados persistem após restart; imagem com **tag fixa** (nunca `latest`); Postgres próprio, sem credencial cruzada com Twenty/Supabase; restore de backup recompõe conversas e anexos num ambiente limpo.

**Gate verificado ao vivo em 2026-07-13 (dev):** `make up` sobe os 6 containers healthy com um
comando · `https://inbox.localhost` responde (HTTP→HTTPS 308; cert da CA interna em dev — o cert
público do Let's Encrypt depende do **DNS de produção**, ver abaixo) · `make smoke` prova que
conversa, mensagem e anexo sobrevivem ao restart · `make check` valida tag fixa `-ce`, banco próprio
sem credencial cruzada, usuário não-superusuário, sem dblink/fdw, só o Caddy publicando porta ·
`make backup` + `make restore-check` recompõem banco **e** anexos num ambiente limpo.

**Pendências de produção (passo manual do operador — `docs/runbook-deploy.md`):** apontar o DNS de
`inbox.<DOMAIN>` para o host antes do 1º boot (sem isso o Let's Encrypt não emite cert), preencher o
`.env` de produção com segredos próprios, criar o admin em `/installation/onboarding`, configurar o
SMTP transacional e agendar o cron de backup + cópia offsite criptografada.

---

## EPIC-2 — Canal WhatsApp Prospecção (Evolution)

Número novo pré-pago, **só inbound**, convivendo com o Agente N8N sem perda de mensagem.

| # | Story | Status | Commit |
|---|---|---|---|
| 2.1 | Inbox de prospecção espelhada no Chatwoot (FR-4) | [~] | 4bbccb5 |
| 2.2 | Convivência com o Agente N8N sem perda — fan-out (FR-5, AD-5) | [~] | |
| 2.3 | Aquecimento e proteção do número (FR-6) | [x] | |

> **O EPIC-2 está pronto até onde é automatizável.** As stories 2.1 e 2.2 só viram `[x]` depois de
> **parear o chip** e provar o gate com uma mensagem real — o checklist está em
> `docs/runbook-canal-prospeccao.md` (§ Checklist para fechar o gate do EPIC-2).
>
> **Decisão de operação (2026-07-13): modo espelho.** No número de prospecção quem responde o lead é
> o **Agente N8N**; a central **só espelha** (a atendente acompanha, não digita). É o que evita a
> resposta dupla enquanto não existe handoff. Não é só combinado: `MODO_ESPELHO_PROSPECCAO=true` faz
> o `make aquecimento` **falhar** se aparecer resposta digitada na central nessa inbox.

**STORY-2.2 — fan-out verificado na configuração e no código (2026-07-13, dev).** `make fanout`
prova que os dois consumidores estão vivos na mesma instância (webhook global → N8N **e** integração
Chatwoot aplicada). No código da Evolution 2.3.7: os dois disparos acontecem no mesmo handler de
mensagem (`chatwootService.eventWhatsapp` na linha 1331, `sendDataWebhook` na 1483) e o envio à
central tem `try/catch` próprio (linha 2525) — **não é fila competida, e central fora do ar não cega
o Agente**. A saudação do Agente aparece na central porque mensagem `fromMe` também é espelhada
(vira `outgoing`).
**Idempotência:** o dedup nativo da Evolution só roda com o import por Postgres direto (que
desligamos por AD-8/AD-9) e o Chatwoot não tem índice único em `source_id` — duplicata é possível no
replay do Baileys. Resolvido do lado da central por `dedup-mensagens.sh` (testado: 2 cópias → 1).
**Perda:** com a central fora do ar, o espelho perde as mensagens daquele intervalo (o N8N não). É
assimetria proposital; sem reenvio automático no MVP.

**STORY-2.3 — política do número, com guardrail executável.** `make aquecimento` **falha** se alguma
conversa da inbox de prospecção tiver sido **iniciada por nós** (assinatura de outbound frio), se
existir **campanha** na inbox (AD-6) ou se o volume enviado em 24h passar do teto da rampa
(20/40/60/80/100 por semana). Política e playbook de bloqueio em `docs/runbook-aquecimento-numero.md`.

**STORY-2.1 — integração ligada e verificada até onde dá sem o chip (2026-07-13, dev).**
Verificado ao vivo: rede `flash-canais` liga Evolution 2.3.7 ↔ Chatwoot 4.15.1 sem expor nenhuma das
duas; `make evolution` criou a inbox `WhatsApp Prospecção` (`Channel::Api`, webhook
`/chatwoot/webhook/crm`); a resposta digitada na central **chega** na Evolution; e a Evolution
**escreve de volta** na conversa usando o token de admin. **Falta o passo manual do operador:** parear
o chip pré-pago pelo QR (`docs/runbook-canal-prospeccao.md`) — só então dá para provar os CAs
(mensagem real do lead, resposta chegando no WhatsApp, mídia anexada). A story só vira `[x]` depois
disso.

**Dois achados que mudaram o desenho:**
1. **`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true` é obrigatório na central.** O Chatwoot recusa webhook e
   download de mídia em host sem IP público (anti-SSRF do `SafeFetch`), e a Evolution vive em rede
   privada. Sem o flag, a resposta do atendente falha em silêncio (`failed` + `has no public ip
   addresses`). Alternativa seria expor a Evolution na internet — pior.
2. **Um host = um Caddy.** Central e CRM não podem ambos publicar 80/443. O Caddy da central virou
   perfil `edge` (default em dev/staging); com as duas stacks no mesmo host, o Caddy do CRM serve o
   vhost `inbox.<DOMAIN>` pela rede compartilhada.

**Gate EPIC-2:** mensagem inbound no número novo aparece na inbox `WhatsApp Prospecção`; resposta pela central chega ao lead; mídia é anexada; **N8N e Chatwoot recebem cada evento** (fan-out at-least-once, sem mensagem engolida nem duplicada); a saudação + link Jotform do agente aparecem na conversa; limite de aquecimento documentado e zero outbound frio em massa.

> ⚠️ **Risco de engenharia do épico:** a instância Evolution tem **dois consumidores** (N8N + Chatwoot). Se virar fila competida, um engole o evento do outro. Fan-out é requisito, não detalhe.

---

## EPIC-3 — Canal WhatsApp Oficial (Twilio/Meta)

Número oficial como inbox de cobrança/transacional + espelho dos disparos originados no monorepo.

| # | Story | Status | Commit |
|---|---|---|---|
| 3.1 | Inbox oficial espelhada (FR-7) | [x] | b16dabc |
| 3.2 | Espelho dos disparos em massa — push do monorepo (FR-8, AD-6) | [x] | c3d5438 (monorepo) |

## ✅ Gate do EPIC-3 verificado AO VIVO (2026-07-13, número oficial real)

Com a conta Twilio de produção e o número `+55 31 2391-6846`:

| Critério do gate | Evidência |
|---|---|
| mensagem ao número oficial cai na inbox `WhatsApp Oficial` | `"Boa noite !"` de `+5531822…` → inbox 6, `source_id=SMbdf805…` |
| resposta dentro da janela de 24h sai pelo canal oficial | digitada na central → entregue no WhatsApp, `source_id=SMf14975…` |
| disparo do monorepo aparece como outbound na conversa correta | `mirror_outbound` chamado de dentro do `fastapi_api` → mensagem na conversa do contato |
| **a central NÃO reenvia o disparo** | a Twilio recebeu **zero** cópias da mensagem espelhada — o guard do `source_id` segurou **com credencial real** |
| a resposta do cliente cai na mesma thread | inbound e espelho resolveram o **mesmo `contact_inbox`** (`whatsapp:+E164`) e o mesmo contato |
| a central não origina disparo em massa | `make oficial`: zero campanhas na inbox (AD-6) |

**Ainda não exercitado:** o envio por **template fora da janela de 24h**. O mecanismo está provado
(`can_reply?` fecha sem inbound e reabre com ele; os 10 Content Templates aprovados estão
sincronizados), mas o envio real fora da janela exige 24h de silêncio do cliente.

**Fan-out provado com assinatura real.** Antes do teste com celular, a cadeia foi validada forjando
uma chamada da Twilio com **assinatura HMAC-SHA1 válida** pela URL pública: ngrok → monorepo
(assinatura validada) → confirmação de sacado (no-op, número sem disparo) → relay → central. Os dois
consumidores viram o mesmo evento.

**A descoberta que definiu o épico: o número oficial JÁ TEM dono do webhook.** O monorepo recebe o
inbound do Twilio em `/webhooks/twilio/inbound`, valida a assinatura e usa a resposta do cliente para
a **confirmação de sacado**. Um número Twilio tem **um único** webhook de inbound — apontá-lo para o
Chatwoot **quebraria a confirmação de cobrança**. E o inverso (Chatwoot recebe e avisa o monorepo)
colocaria a confirmação de **dinheiro** refém de uma ferramenta de **chat**. Então o desenho é
forçado, e é o mesmo do EPIC-2: **o monorepo continua dono do webhook e faz fan-out** para a central.

**STORY-3.1 — o que já está de pé (2026-07-13, dev).** `conectar-twilio.sh` cria a inbox como
`Channel::TwilioSms` com **`medium: whatsapp`** — é o `medium` que ativa a **janela de 24h** nativa
(`MessageWindowService`); criada como `sms` a atendente escreveria texto livre depois das 24h e a Meta
rejeitaria o envio, em silêncio, no canal de cobrança. Bônus: com `whatsapp` o Chatwoot **não encosta**
no webhook do número (`setup_webhooks if @twilio_channel.sms?`), então o do monorepo fica intacto.
Templates Meta e janela de 24h são **nativos** — nada construído, só sincronizados da Content API.

**Provado ao vivo com credencial Twilio FALSA de propósito** (ensaio removido depois): mensagem
outgoing **com** `source_id` → `sent`, o Chatwoot **não chamou a Twilio**; **sem** `source_id` →
`failed` com `[HTTP 401] 20003 Authentication Error`. O contraste prova o guard
(`Base::SendOnChannelService#invalid_message?`) que impede a central de **reenviar** um disparo que o
monorepo já mandou — sem ele, a STORY-3.2 cobraria o cliente **duas vezes**. Também provado: a
resposta simulada do cliente caiu na **mesma thread** do disparo espelhado (via `contact_inbox.source_id`
= `whatsapp:+E164`), e o `can_reply?` fecha sem inbound e reabre com ele.

**Segurança do callback:** o `Twilio::CallbackController` do Chatwoot **não valida** o
`X-Twilio-Signature`. Como o inbound legítimo chega pelo relay do monorepo (que já validou), o Caddy
barra `/twilio/callback` para a internet com um token compartilhado (`RELAY_TOKEN`). Verificado: sem
token → 403 · token errado → 403 · token certo → 204. Falha fechada se o token não estiver no `.env`.

**STORY-3.2 — o espelho, no monorepo** (branch `feat/espelho-chatwoot`, commit `c3d5438`; `main` de lá
intocada). É **código**, então TDD: 16 testes novos, suíte da API em **895 passed**, pyright limpo.

- `api/integrations/chatwoot/chatwoot_mirror.py` — `mirror_outbound` (o disparo que já saiu pela
  Twilio vira mensagem `outgoing` na conversa) e `relay_inbound` (fan-out do webhook). **Desligado por
  padrão** (`CHATWOOT_MIRROR_ENABLED=false`); auto-desliga se faltar chave.
- **O fan-out respeita a ordem:** a confirmação de sacado roda **primeiro**; o espelho depois, e sem
  poder quebrá-la. Toda falha do espelho é engolida e logada — central fora do ar degrada o espelho,
  **nunca** a cobrança. Há um teste dedicado a essa não-regressão.
- Espelho ligado no **choke point** `_process_dispatch_loop`, que cobre sacado, cedente e comissária
  de uma vez. Não espelha preview nem envio falho.
- O provider passou a devolver `delivered_to`, derivado do `effective_to`: o destino **efetivo**, não o
  pretendido. Enquanto o override de dev (`TWILIO_FLASH_CAPITAL_PHONE_NUMBER`) existir, a Twilio
  entrega tudo no número de teste — é de lá que vem a resposta, logo é lá que a thread existe.

### O que quase matou o épico em silêncio (e virou guard)

Nenhum destes dava erro. Todos falhavam **calados** — é o padrão de falha que mais custa neste projeto.

1. **O smoke test do EPIC-1 deixou uma conta para trás.** Ela virou a `Account` id 1; o `.env` dizia
   `CENTRAL_ACCOUNT_ID=1`; e as duas inboxes foram criadas **dentro da conta de teste**. O operador
   logava na conta real e via uma central vazia. → `smoke-test.sh` agora destrói a conta que cria e
   **falha se ela sobreviver**; `make check` recusa conta de teste e exige **uma única** conta.
2. **O Caddy 2.11 descarta header com underscore** (`dropping header containing underscore`, sem opção
   de desligar) — e o Chatwoot autentica com `api_access_token`. Cliente de API pela URL pública levava
   **401 com token válido**. A UI não sofria (cookie) e a rede interna também não — o bug só apareceria
   no dia em que a central e o monorepo ficassem em hosts separados, e aí **o espelho morreria calado**.
   → ponte hífen→underscore no Caddyfile + `make check` prova ao vivo (chama a API pública, exige 200).
3. **`env_get` não aparava espaço/`\r`** do valor lido do `.env`. Espaço sobrando num SID vira URL
   inválida; numa senha de banco, falha de autenticação sem pista. → aparado nos 10 scripts, e o
   `make check` detecta a sujeira (o Docker Compose **não** apara — passa o valor cru ao container).
4. **`make check` comparava `.env` e `.env.example` numa direção só**, e mesmo assim afirmava "mesmas
   chaves" — ficou verde com 6 chaves faltando. → comparação simétrica.
5. **O webhook do Twilio apontava para um túnel ngrok morto** (`a555-…`) desde **3 de julho**. Ou seja:
   a **confirmação de sacado por resposta de WhatsApp nunca funcionou em produção** — o código valida
   assinatura e grava em `confirmacoes_disparos`, mas a Twilio nunca conseguiu chamá-lo (erro 11200,
   HTTP 404). Achado colateral do EPIC-3; **é do monorepo, e o time precisa saber**.

**Gate EPIC-3:** mensagem ao número oficial cai na inbox `WhatsApp Oficial`; resposta dentro da janela de 24h sai pelo canal oficial e fora dela usa **template Meta aprovado**; disparo de cobrança do pipeline do monorepo aparece como outbound na conversa correta (push na API do Chatwoot); a resposta do cliente cai na **mesma thread**; a central **não origina** disparo em massa.

---

## EPIC-4 — Canal E-mail (Gmail)

Caixa Gmail de atendimento como inbox, com as threads unificadas ao mesmo contato dos WhatsApps.

| # | Story | Status | Commit |
|---|---|---|---|
| 4.1 | Inbox de e-mail espelhada (FR-9) | [x] | 28b6766 |
| 4.2 | Unificação sob o mesmo contato (FR-10) | [!] | |

## ✅ Gate da STORY-4.1 verificado AO VIVO (2026-07-14, caixa real de produção)

Com a caixa `operacional@flashcapital.com.br` (Google Workspace, OAuth):

| Critério do gate | Evidência |
|---|---|
| e-mail que chega na caixa vira conversa na inbox `E-mail` | **8 conversas reais** puxadas na 1ª sincronização (NF, boletos, Jotform, mailer-daemon) |
| resposta pela central volta ao remetente | resposta digitada na central → **entregue** na caixa do destinatário |
| a resposta cai na **mesma thread** | a mensagem inbound trouxe o `Message-ID` do Gmail (`CAL=_anO9…`); é dele que o mailer monta o `In-Reply-To` + `References`. `Reply-To` = a própria caixa |
| **o canal se renova sozinho** | forçamos `expires_on` para o passado: o refresher chamou o Google, renovou, **preservou o `refresh_token`** — e o IMAP **autenticou com o token renovado** |
| o canal vive sem o andaime do OAuth | `FRONTEND_URL` devolvida a `https://inbox.localhost` e a ponte derrubada: `make email` **continua verde** |

**Ainda não exercitado:** a janela de ~24h do IMAP (`SINCE hoje−1`) — o canal tolera o Sidekiq fora do ar
por horas, mas acima de ~24h o que chegou no buraco não é mais buscado. Não dá para provar sem esperar.

**Gate EPIC-4:** e-mail que chega na caixa vira conversa na inbox `E-mail`; resposta pela central volta ao remetente na mesma thread; conversas de e-mail e de WhatsApp do mesmo cliente aparecem sob o **mesmo Contato** quando e-mail/documento casam, sem duplicidade (fecha junto com o EPIC-5).

> **O EPIC-4 está pronto até onde é automatizável.** A 4.1 vira `[x]` depois do **passo manual do
> operador**: criar o OAuth Client no Google Cloud, preencher 3 chaves no `.env` e concluir a dança
> do OAuth. Checklist completo em `docs/runbook-canal-email.md`.
> A 4.2 está `[!]` **por desenho, não por atraso** — a resolução de identidade (telefone **E**
> documento, AD-3) vive num lugar só: o **Serviço de Sync (EPIC-5)**, que ainda não existe. Já estava
> assim em `docs/epics-and-stories.md` desde o planejamento ("depende de Epic 5").

**A descoberta que definiu o épico: a service account do Gmail NÃO pluga no Chatwoot.** Não é
preferência — é ausência de caminho de código. O `Imap::GoogleFetchEmailService` autentica XOAUTH2
com o `Google::RefreshOauthTokenService`, que renova por `grant_type=refresh_token` e faz
`raise 'A refresh_token is not available'` se ele faltar. Service account usa o grant **JWT-bearer**
(domain-wide delegation) e **nunca emite `refresh_token`**. Injetar um token de SA na marra faria o
canal viver **1 hora** e morrer **dentro de um job do Sidekiq**, calado. Rota escolhida: **OAuth de
usuário** (`provider=google`), com a tela de consentimento **Internal** (é Workspace) — o que dispensa
a revisão do Google para o escopo restrito `https://mail.google.com/`.

**STORY-4.1 — o que já está de pé (2026-07-14, dev).** `conectar-gmail.sh` (`make gmail`) **pré-cria**
a inbox `E-mail` (`Channel::Email`) e devolve a URL de autorização. A pré-criação não é detalhe: o
`OauthCallbackController` **cria a inbox sozinho** nomeando-a com o perfil do Google
(`users_data['name']`), o que violaria o nome fixo do glossário; pré-criada com o endereço certo, o
callback a **encontra** (`find_channel_by_email`) e só anexa os tokens. `verificar-canal-email.sh`
(`make email`) recusa as três falhas silenciosas do canal. Criptografia at-rest ligada
(`ACTIVE_RECORD_ENCRYPTION_*`) — sem regressão: o `auth_token` da Twilio, gravado antes em texto puro,
continua legível (`support_unencrypted_data = true`).

**A armadilha que quase custou horas: a env var do OAuth NÃO basta.** O controller que monta a URL de
consentimento não lê o ENV — lê `GlobalConfigService.load`, que consulta a tabela
`installation_configs`. Esse loader *tenta* cair para o ENV, mas faz
`InstallationConfig.where(name: k).first_or_create(...)` e **devolve `i.value`** — e como o
`installation_config.yml` do Chatwoot **semeia a linha vazia** no deploy, o `first_or_create`
**encontra** a linha vazia, não atualiza nada, e devolve o vazio. **O ENV é ignorado para sempre.**
Sintoma: a URL de consentimento sai com `client_id` **em branco** e o Google responde um erro
genérico — sem nada de errado no `.env`. Resolvido: `make gmail` grava os valores no
`installation_configs` e limpa o cache; `make email` reprova se estiverem vazios.
(De quebra: a coluna é `serialized_value` **jsonb com YAML dentro** — o próprio Chatwoot marca isso
com um `FIX ME` —, então a checagem **não pode** ser SQL; passa pelo model.)

**O ngrok foi descartado — e a razão importa.** O host já roda **dois túneis ngrok que são carga viva
do monorepo**: o do `fastapi_api` (webhook do **Twilio** + `PUBLIC_BOLETO_BASE_URL`) e o do Supabase.
Um terceiro agente esbarraria no limite de sessões do plano free, e o candidato a cair era justamente
o do Twilio — **a mesma falha que deixou a confirmação de sacado quebrada por 10 dias**. Em vez disso:
**ponte de loopback** (`socat`, só em `127.0.0.1:3000`, fora do compose) + redirect URI
`http://localhost:3000/google/callback`, que o Google **aceita** (a exigência de HTTPS isenta o
`localhost` **puro** — `inbox.localhost` é subdomínio e é recusado). Derrubada depois da dança.

**Três armadilhas as-built, todas silenciosas (detalhe em `docs/runbook-canal-email.md`):**
1. **Agendador parado ⇒ a atendente para de RESPONDER.** O SMTP de saída autentica com
   `provider_config['access_token']` **cru** (`ConversationReplyMailerHelper#base_smtp_settings`), sem
   passar pelo refresh. Quem mantém esse token fresco é o **job IMAP que roda a cada minuto**. Sidekiq
   parado → em 1h o envio quebra junto com o recebimento, com falha de auth SMTP dentro de um job.
2. **Re-autorizar sem revogar não devolve `refresh_token`.** O Google só o emite com
   `access_type=offline` + `prompt=consent` **e** consentimento ainda não dado. Re-autorizou por cima?
   volta sem refresh_token, e o canal nasce condenado a morrer em 1h. Revogar antes em
   `myaccount.google.com/permissions`.
3. **O `refresh_token` fica em texto puro** — ver dívida técnica.

**O ngrok aqui é seguro (≠ a dívida do Twilio).** O Google recusa `.localhost` como redirect URI, então
a dança do OAuth em dev sai por um túnel. Mas a URL do túnel só precisa existir **no momento do
clique**: o refresh usa `grant_type=refresh_token`, que **não usa `redirect_uri`**. Autorizou, pode
derrubar o túnel e devolver a `FRONTEND_URL`. É o oposto do webhook do Twilio, que é **permanente**
numa URL efêmera — e por isso apodreceu por 10 dias.

---

## EPIC-5 — Serviço de Sync (Enriquecimento de Contato)

A Ponte: identidade por telefone+documento e push unidirecional de labels e atributos.
**Único componente construído do zero** — aqui TDD é obrigatório.

| # | Story | Status | Commit |
|---|---|---|---|
| 5.1 | Resolução de identidade por telefone + documento (FR-11) | [ ] | |
| 5.2 | Regra de merge — automático vs. sugestão (FR-10, FR-11, AD-3) | [ ] | |
| 5.3 | Push de labels de segmento/estado (FR-12) | [ ] | |
| 5.4 | Push de atributos de domínio (FR-13) | [ ] | |
| 5.5 | Desacoplamento e degradação graciosa (FR-14, AD-2) | [ ] | |

**Gate EPIC-5:** contato reconhecido vira **um único** Contato no Chatwoot com `source_twenty_id`/`source_supabase_id`; desconhecido recebe a label `nao-identificado`; merge automático **só** com telefone **E** documento casando, senão **sugestão `pending`** sem alterar o contato; labels do **dicionário fechado** aplicadas na transição de estado; atributos (`cnpj`, `status_operacao`, `dias_atraso`, `valor_em_aberto`, `link_twenty`, `link_supabase`) visíveis na barra lateral com link abrindo o registro-fonte; **com Twenty/Supabase fora do ar o atendimento continua funcionando** (só o enriquecimento atrasa); push idempotente com retry e backoff; **zero chamada síncrona central→domínio**.

---

## EPIC-6 — Operação de Atendimento & Governança

Cockpit, papéis, atribuição, labels manuais, respostas rápidas, LGPD e observabilidade.

| # | Story | Status | Commit |
|---|---|---|---|
| 6.1 | Cockpit unificado e papéis de agente (FR-15) | [ ] | |
| 6.2 | Atribuição, labels manuais e respostas rápidas (FR-16) | [ ] | |
| 6.3 | Observabilidade e conformidade LGPD | [ ] | |

**Gate EPIC-6:** as 3 inboxes visíveis numa interface única; papéis (admin/agente) negam acesso indevido; atribuição manual e automática por inbox funcionando; respostas rápidas inseridas; labels manuais aplicáveis além das empurradas pelo Sync; log estruturado + alerta de saúde da conexão Evolution; retenção de conversas configurada e acesso a CPF/CNPJ restrito por papel.

---

## Dívida técnica conhecida

Itens levantados em code-review e desvios as-built. **Nenhum bloqueia o MVP** — mas os marcados
"antes do go-live" precisam ser resolvidos antes de a operação depender disto de verdade.

| Item | Risco | Alvo |
|---|---|---|
| **Handoff Agente ↔ humano não existe.** Contornado pela decisão de **modo espelho** (2026-07-13): no número de prospecção quem responde é o Agente N8N; a central só espelha, e `make aquecimento` falha se alguém digitar ali (`MODO_ESPELHO_PROSPECCAO=true`). O custo é que a atendente **não pode** intervir numa conversa de lead. O handoff real (o Agente pular a resposta quando a conversa tem `assignee` humano no Chatwoot — estado nativo, sem label nova) fica para quando a operação pedir. | atendente sem poder assumir a conversa do lead | fase 2 / quando doer |
| **Espelho pode duplicar e pode perder.** Duplicar: o dedup nativo da Evolution depende do import por Postgres direto (desligado por AD-8/AD-9) e o Chatwoot não tem índice único em `source_id` — o replay do Baileys reinsere. Mitigado *a posteriori* por `dedup-mensagens.sh` (precisa estar no cron). Perder: central fora do ar = mensagens só no N8N e no WhatsApp, sem reenvio automático. | espelho incompleto/duplicado (não afeta o Agente nem o lead) | reenvio vira trabalho do Serviço de Sync se doer (EPIC-5) |
| **Anti-SSRF do Chatwoot desligado para rede privada** (`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`). Necessário para falar com a Evolution e baixar mídia; em troca, um webhook malicioso configurado na central poderia alcançar serviço interno. Mitigação atual: só admin configura webhook, e a rede `flash-canais` tem apenas Evolution, Chatwoot e o Caddy. | SSRF a partir da central | revisar no EPIC-6 (governança) |
| **Retenção de conversa sem aval jurídico — e agora ela está ACUMULANDO.** `RETENCAO_CONVERSAS_DIAS=1825` (5 anos) é um default técnico, não uma decisão. O expurgo existe (`retencao-conversas.sh`) mas **não está no cron**. Desde 2026-07-14 isto deixou de ser hipotético: com o canal de e-mail ligado à caixa **real** (`operacional@`), a central passou a ingerir **PII de cliente de verdade** a cada minuto (CNPJ, valores, NF, boletos, dados de lead do Jotform) — e todo `make backup` a carrega junto. Decisão do operador (2026-07-14): **seguir, porque este host vira produção**. | LGPD / prova em disputa de dívida | **cron da retenção: antes do go-live** · aval jurídico: STORY-6.3 |
| **Identidade dupla no canal Twilio: telefone e BSUID.** O inbound real criou **dois** `contact_inbox` para o mesmo contato: `whatsapp:+553182210297` (telefone) e `whatsapp:BR.4456758834604506` (o **BSUID**, identificador novo da Meta que a Twilio manda em `ExternalUserId`). Hoje o Chatwoot prefere o do telefone (`twilio_whatsapp_primary_source_id`) e é ele que o espelho do monorepo usa — então disparo e resposta casam. Mas a Meta está migrando para payloads **só com BSUID** (o próprio código do Chatwoot já trata esse caso). No dia em que o `From` vier sem telefone, o inbound resolveria o `contact_inbox` do BSUID e o espelho continuaria criando o do telefone: **mesmo contato, threads separadas**. | disparo e resposta em conversas diferentes (dado não se perde; a thread racha) | monitorar; revisar quando a Meta forçar BSUID |
| **Webhook do Twilio depende de URL de ngrok efêmera — E JÁ QUEBROU DE NOVO.** Em 2026-07-14 o webhook do número oficial estava apontando para **`https://demo.twilio.com/welcome/sms/reply`** (a URL de exemplo da própria Twilio), não para o monorepo. O número não recebia nada e não alimentava a confirmação de sacado. Reapontado para o túnel atual (`https://7c2d-…ngrok-free.app/webhooks/twilio/inbound`) — **que vai apodrecer de novo no próximo restart do ngrok**. É a segunda ocorrência do mesmo modo de falha (a primeira custou 10 dias em silêncio). O conserto real é reservar o **domínio estático** que o ngrok dá de graça (o plano free inclui 1) ou publicar a API. Decisão do operador (2026-07-14): seguir com a URL efêmera por ora. | webhook apodrece em silêncio a cada restart — e ninguém percebe, porque a Twilio entrega em 200 no demo | **antes do go-live — é reincidente** |
| **Sem monitoramento do webhook do Twilio.** As duas quebras (ngrok morto, depois demo.twilio.com) só foram descobertas por acaso, dias depois. Não há nada que reclame quando o número oficial para de entregar inbound. Um check simples (comparar o `sms_url` do número com a URL esperada) fecharia esse buraco. | a cobrança quebra e ninguém sabe | antes do go-live |
| **Rota de disparo em massa do monorepo sem autenticação.** O router `/whatsapp-dispatch` (`api/api_main.py:256`) não declara nenhuma dependência de auth — nem no `include_router`, nem nas rotas. A única guarda é o limite de 50 boletos por lote. São os endpoints que **disparam cobrança em massa** pela Twilio. Achado de passagem no EPIC-3; **fora do escopo desta central** (é código do monorepo), mas registrado porque o risco é alto e o dono é o mesmo time. Confirmar se há middleware global de auth antes de concluir que está aberto. | disparo de cobrança em massa por terceiro; custo Twilio; reputação do número oficial | monorepo — avaliar assim que possível |
| **`/twilio/delivery_status` da central aceita chamada não assinada.** O Chatwoot não valida o `X-Twilio-Signature` em nenhum dos dois callbacks. O `/twilio/callback` nós fechamos com o `RELAY_TOKEN` (o inbound vem do monorepo), mas o `delivery_status` **precisa** ficar público — é a Twilio que o chama direto, para as mensagens que a central envia. Forjá-lo só altera o status de entrega de uma mensagem existente. Mitigação possível: allowlist dos IPs da Twilio no Caddy. | status de entrega forjado (sem leitura nem envio de dados) | revisar no EPIC-6 (governança) |
| **O `refresh_token` do Gmail fica em TEXTO PURO no banco.** O `Channel::Email` criptografa só `imap_password`/`smtp_password`. Com OAuth, a credencial real vive no `provider_config` — **jsonb, que o Chatwoot não criptografa**, mesmo com `ACTIVE_RECORD_ENCRYPTION_*` ligado (ligamos: protege o `Hook#access_token` e habilita MFA, mas **não** cobre este caso). O token dá **leitura e envio na caixa inteira** (`https://mail.google.com/`) e **não expira**. Está no Postgres e dentro de **todo backup**. Corrigir exigiria forkar o Chatwoot — proibido (AD-7). Mitigação: `BACKUP_DIR` tratado como segredo; revogar em `myaccount.google.com/permissions` ao menor sinal. | quem tiver o backup tem a caixa de atendimento inteira | aceito no MVP; revisar no EPIC-6 (governança) |
| **Envio de e-mail acoplado ao poller de recebimento.** O SMTP de saída usa o `provider_config['access_token']` **cru**; quem o mantém fresco é o job IMAP que roda a cada minuto. Agendador do Sidekiq parado ⇒ em até 1h a atendente **para de conseguir responder**, com falha de auth SMTP **dentro de um job** (sem erro na tela). `make email` checa o registro do cron. | resposta ao cliente some em silêncio | monitorar (alerta de saúde entra na STORY-6.3) |
| **O espelho do canal oficial não está na `main` do monorepo.** `mirror_outbound`/`relay_inbound` vivem na branch `feat/espelho-chatwoot` (`c3d5438`). O gate do EPIC-3 foi provado ao vivo **rodando essa branch** — mas até **merge + deploy** no monorepo, a central **não recebe** o inbound relayado nem o espelho em produção. | o EPIC-3 parece fechado e não está, em produção | monorepo — antes do go-live |
| **Cópia offsite do backup é manual.** O `backup.sh` grava só local; host morre = backup morre junto. A cópia criptografada para fora do host está documentada, não automatizada. | perda total em falha de host | antes do go-live |
| **Staging não existe ainda.** O runbook de upgrade exige validar em staging antes de produção (FR-2); hoje só há o ambiente dev local. | upgrade sem rede de proteção | antes do 1º upgrade em prod |

### Adiado para a fase 2 (registrado em `docs/architecture.md` §Deferred)

| Item | Por quê ficou fora do MVP |
|---|---|
| **Instância B** — número de relacionamento (clientes que já operam) no Evolution | mesmo padrão do canal de prospecção, sem agente; baixo esforço — revisar se o cronograma permitir |
| **Dashboard App (iframe)** com dado de domínio ao vivo | o MVP usa só atributos empurrados; mantém a central leve (AD-2) |
| **Sync bidirecional** (central → domínio) | MVP é unidirecional |
| **Campanhas/disparo em massa na central** | permanece no monorepo (AD-6) |
| **SSO / embed na plataforma interna** | fase 2 |
| **Novos canais** (Instagram, webchat, Telegram) | o padrão de adapter (AD-4) já os acomoda |

---

## Registro de sessões

| Data | Épico | Stories | Notas |
|---|---|---|---|
| 2026-07-13 | — | planejamento | Documentação BMAD gerada em `docs/`: `product-brief.md` (fase 1), `prd.md` (16 FRs, glossário fechado, jornadas), `architecture.md` (spine hub-and-spoke, AD-1..AD-9, diagramas, árvore-alvo), `epics-and-stories.md` (6 epics · 19 stories com CA Given/When/Then). Decisões travadas: Evolution fica no CRM com fan-out; merge só com telefone **E** documento; disparo em massa origina no monorepo. |
| 2026-07-13 | — | setup | Scaffold do repo: `.claude/` (hooks, 5 comandos, 4 memories), `PROGRESS.md`, `CLAUDE.md`, `README.md`, `.gitignore`. 11 skills instaladas em `.claude/skills/` (incl. as oficiais `chatwoot-cli` e `twilio/ai`). Nenhum código de runtime. |
| 2026-07-13 | EPIC-1 | 1.1 · 1.2 · 1.3 · 1.4 | **A central subiu.** `deploy/` criado: compose (Caddy 2.11.4 · Chatwoot `v4.15.1-ce` web+sidekiq+init · pgvector 0.8.5-pg16 · Redis 7.4.9), `Caddyfile`, `.env.example`, init-db e 5 scripts de operação; `Makefile` com `up/check/smoke/backup/restore-check/retencao`; runbooks de deploy, upgrade e backup. Decisões as-built: **`chatwoot-init` one-shot** (`db:chatwoot_prepare` via `service_completed_successfully`) para o `up` ser mesmo **um** comando — o compose oficial exige migração à mão; **extensões pré-criadas pelo superusuário** no init-db (o `pg_stat_statements` não é *trusted*, e o usuário da app é não-superusuário por AD-9); **`APP_DB_*`** no init para desfazer a colisão de `POSTGRES_PASSWORD` (superusuário na imagem do Postgres vs. usuário da app no Chatwoot). Gate do épico verificado ao vivo em dev. |

| 2026-07-13 | EPIC-2 | 2.1 · 2.2 · 2.3 | **Canal de prospecção ligado.** A instância `crm` (Evolution, no CRM) passou a ter **dois consumidores**: o Agente N8N (webhook global) e a central (integração nativa Chatwoot). A inbox `WhatsApp Prospecção` é criada pela própria Evolution (`autoCreate`). Ponte por rede Docker externa `flash-canais` — nada exposto na internet. Novos comandos: `make evolution`, `make fanout`, `make dedup`, `make aquecimento`. Runbooks de canal e de aquecimento. **Achados que mudaram o desenho:** (1) o Chatwoot recusa webhook/mídia em host sem IP público (anti-SSRF do `SafeFetch`) → `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`, senão o canal falha **em silêncio**; (2) um host só tem uma porta 443 → o Caddy da central virou perfil `edge` e, no host compartilhado, o Caddy do CRM serve `inbox.<DOMAIN>`; (3) o dedup nativo da Evolution depende do import por Postgres direto (proibido por AD-9) → faxineiro `dedup-mensagens.sh` na central. Commits: `4bbccb5` (central) · `46b96b2` (CRM). Gate do épico **pendente do pareamento do chip** (manual). |

| 2026-07-13 | EPIC-3 | 3.1 · 3.2 | **Canal oficial (Twilio) ligado — e o épico foi definido por uma descoberta.** O número oficial **já tinha dono do webhook**: o monorepo recebe o inbound, valida a assinatura e alimenta a confirmação de sacado. Um número Twilio tem **um** webhook de inbound — apontá-lo para o Chatwoot quebraria a cobrança; o inverso deixaria a confirmação de dinheiro refém do chat. Desenho forçado: **o monorepo segue dono e faz fan-out**, igual ao EPIC-2. Na central: `conectar-twilio.sh` (inbox `Channel::TwilioSms` **medium=whatsapp** — é o medium que ativa a janela de 24h nativa; como `sms`, a Meta rejeitaria o texto livre pós-24h **em silêncio**), Caddy barrando `/twilio/callback` com `RELAY_TOKEN` (o `Twilio::CallbackController` **não valida** a assinatura), `verificar-canal-oficial.sh`. No monorepo (branch `feat/espelho-chatwoot`): `ChatwootMirror`, fan-out do inbound **depois** da confirmação, espelho no choke point do dispatch. **O achado que salvou o épico:** o Chatwoot **reenviaria** o disparo se a mensagem chegasse sem `source_id` — cobrança em dobro. Provado ao vivo com credencial Twilio **falsa**: com SID → `sent` sem chamar a Twilio; sem SID → `failed` (HTTP 401). Comandos novos: `make twilio`, `make twilio-status`, `make oficial`. Commits: `b16dabc` (central) · `c3d5438` (monorepo, branch). Gate **pendente de credencial real**. |

| 2026-07-13 | EPIC-3 | gate | **Gate do EPIC-3 fechado ao vivo, com o número oficial real.** Mensagem recebida na inbox, resposta enviada pela central e chegando no WhatsApp, espelho do disparo caindo na conversa do contato — e a Twilio **sem nenhuma cópia** da mensagem espelhada (o guard do `source_id` segurou com credencial real: cobrança em dobro não acontece). Antes do teste com celular, a cadeia foi validada forjando uma chamada da Twilio com **assinatura HMAC-SHA1 válida** pela URL pública. O caminho até aqui foi feito de **falhas silenciosas**, e cada uma virou guard: a conta órfã que o smoke test deixou (os canais nasceram na conta de TESTE e o operador via a central vazia); o Caddy comendo o `api_access_token` por causa do underscore; o `env_get` sem aparar espaço; o `make check` comparando o `.env` numa direção só. Achado colateral **grave, do monorepo**: o webhook do Twilio apontava para um túnel ngrok morto desde 03/07 — a **confirmação de sacado por WhatsApp nunca funcionou em produção**. Commits: `b16dabc`, `78beb30`, `483adc2`, `3890d31`, `c7d0df3`, `83002d2`, `fd86c4f` (central) · `c3d5438` (monorepo, branch `feat/espelho-chatwoot`). |

| 2026-07-14 | — | docs | **Faxina da documentação.** O `CLAUDE.md` afirmava "implementação NÃO iniciada — 0/19 stories", "não existe `deploy/`" e "a próxima é a STORY-1.1" — mentira em todos os pontos, e é o primeiro arquivo que qualquer sessão lê. Reescrito com o estado real, os comandos do Makefile e os 5 as-built que mordem. Auditoria varreu os 17 docs restantes: corrigidos o README e o `runbook-canal-oficial.md` (afirmavam o espelho **em produção**, quando ele está numa branch não mergeada do monorepo), o `runbook-deploy.md` (mandava `make up` em produção sem alertar que `COMPOSE_PROFILES=edge` sobe um **segundo Caddy** e colide com o do CRM), a "Opção B" fantasma e um "acima"/"abaixo" trocado no runbook de prospecção, a árvore de fonte do `architecture.md` (listava 5 dos 12 scripts) e o cabeçalho da dívida técnica ("Nada ainda" com 9 itens logo abaixo). Nas memories — que são o que o `/story` carrega: `decisions.md` não registrava o **modo espelho** (um agente leria o AD-5 e acharia normal responder ao lead pela central) e `security.md` dizia que o inbound da central é validado por assinatura, quando quem o protege é o **`RELAY_TOKEN`** no Caddy. |

| 2026-07-14 | EPIC-4 | 4.1 | **Canal de e-mail ligado até onde é automatizável — e o épico foi definido por uma descoberta.** A **service account do Gmail não pluga no Chatwoot**: não é preferência, é ausência de caminho de código (`BaseRefreshOauthTokenService` faz `raise 'A refresh_token is not available'`; SA usa JWT-bearer e nunca emite refresh_token). Rota: **OAuth de usuário**, consent screen **Internal** (Workspace) — dispensa revisão do Google no escopo restrito. Novos: `conectar-gmail.sh` (`make gmail`/`gmail-status`/`gmail-url`), `verificar-canal-email.sh` (`make email`), `docs/runbook-canal-email.md`, e as chaves `GMAIL_*`/`GOOGLE_OAUTH_*`/`ACTIVE_RECORD_ENCRYPTION_*`. **A inbox é PRÉ-CRIADA** porque o `OauthCallbackController` a criaria com o nome do perfil Google, violando o glossário. **Três armadilhas silenciosas viraram guard ou runbook:** (1) o SMTP de saída usa o access_token **cru**, mantido fresco pelo job IMAP — **agendador parado ⇒ a atendente para de responder** em 1h; (2) re-autorizar sem revogar **não devolve refresh_token**, e o canal nasce condenado; (3) o `refresh_token` fica em **texto puro** no `provider_config` (jsonb que o Chatwoot não criptografa) — dívida técnica aceita, mitigada por revogação. Criptografia at-rest ligada sem regressão. Gate **pendente do passo manual do operador** (Google Cloud + dança do OAuth). |

| 2026-07-14 | EPIC-4 | gate 4.1 | **Gate da STORY-4.1 fechado ao vivo, com a caixa real.** A 1ª sincronização puxou **8 conversas de operação de verdade** (NF, boletos, Jotform); a resposta digitada na central chegou ao destinatário **na mesma thread** (o `In-Reply-To` sai do `Message-ID` do Gmail que veio no inbound). E o teste que mais importava: **forçamos o `expires_on` para o passado** e o refresher renovou o token no Google, preservou o `refresh_token` e o **IMAP autenticou com o token renovado** — o canal não morre em 1h. Andaime removido (ponte derrubada, `FRONTEND_URL` devolvida) e o `make email` continua verde **sem** ele, provando que o refresh não depende do `redirect_uri`. O caminho até aqui teve **duas falhas silenciosas**: a URL de consentimento saindo com `client_id` **vazio** (o controller lê `installation_configs`, não o ENV — e o Chatwoot semeia a linha vazia, então o fallback devolve o vazio); e um **falso negativo do meu próprio verificador**, que consultava a coluna `value` — quando a coluna é `serialized_value`, jsonb **com YAML dentro**. Consequência de negócio registrada: a central passou a ingerir **PII real de cliente** a cada minuto; o operador decidiu seguir (este host vira produção), e o **cron da retenção LGPD** virou bloqueador de go-live. |

| 2026-07-14 | EPIC-2 | 2.1 · 2.2 | **Chip pareado e o FAN-OUT PROVADO AO VIVO.** O chip entrou pelo **código de pareamento** (`make chip-codigo`) — sem câmera, sem UI da Evolution. A mensagem real do celular apareceu na inbox `WhatsApp Prospecção` **e** o N8N registrou execução do `WF-04-001` para o mesmo evento: **os dois consumidores viram o mesmo evento** (AD-5, o risco nº 1 do MVP). Mas o **Agente não respondeu**, e a investigação achou o que o CRM escondia. |
| 2026-07-14 | — | achados no CRM | **Duas descobertas graves no `crm-flash-capital`, ambas invalidando o "MVP FEATURE-COMPLETE".** (1) **38 nós, em 20 dos 21 workflows, estavam SEM CREDENCIAL** — todo nó que fala com o Twenty declara `authentication: genericCredentialType` e não tinha credencial atribuída. Em runtime o n8n levanta `Credentials not found` e o workflow morre, **mesmo "ativo"**. Ou seja: nenhum workflow que toca o Twenty jamais conseguiu rodar; os 38/38 gates "PASS" foram validados com teste/mock, nunca com o n8n executando. (2) As credenciais eram referenciadas por **IDs placeholder** (`REPLACE_*_CRED`) que não existiam na instância — o `secrets-setup.md` mandava cadastrar as 5 na UI, à mão. Ambos consertados (`scripts/n8n-credenciais.sh` + fiação por URL de destino). O **Agente migrou para OpenAI** por decisão do operador (`gpt-5.4-mini`): não bastava trocar a URL — o `system` vira primeira mensagem, `max_tokens` é **rejeitado** pelos gpt-5.x (é `max_completion_tokens`) e a resposta vem em `choices[0].message.content`. Os três falhariam **calados** dentro de um job. Commits: `ed59d13`, `83f2769` (CRM). |
| 2026-07-14 | EPIC-3 | revisão | **O canal oficial estava quebrado, e pior do que a dívida registrada.** O webhook do número apontava para **`https://demo.twilio.com/welcome/sms/reply`** — a URL de exemplo da própria Twilio. Não recebia mensagem, não capturava histórico, e **não alimentava a confirmação de sacado**. Tudo o mais estava certo: branch `feat/espelho-chatwoot` em uso, `chatwoot_mirror.py` dentro do container, `CHATWOOT_MIRROR_ENABLED=true`, apontando para a conta 3 / inbox 6. Reapontado para o túnel do monorepo. **É a segunda vez que esse webhook apodrece em silêncio** — vira dívida reincidente, com um item novo para monitoramento. |

> **Nota sobre este registro:** é um log **por sessão** (grão grosso). O rastreamento **por story** — com hash de commit — vive nas tabelas de cada épico acima.
