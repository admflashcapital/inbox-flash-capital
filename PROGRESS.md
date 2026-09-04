# Inbox Flash Capital — Progress Tracker

> Para iniciar sessão: "Leia o CLAUDE.md e o PROGRESS.md, continue da próxima story pendente."
> Atualizado pelo Claude Code via `/done`. Detalhe de cada story em `docs/epics-and-stories.md`.

**Legenda:** `[ ]` pendente · `[~]` em andamento · `[x]` concluída · `[!]` bloqueada

**Milestones (escopo ANTIGO — mantido para leitura do histórico):** M1 = EPIC-1 · M2 = EPIC-2 + 3 + 4
(canais) · M3 = EPIC-5 (sync) · M4 = EPIC-6 (go-live).
O EPIC-1 bloqueia tudo. Os EPICs 2/3/4 podem correr em paralelo depois dele.
Cada épico tem um gate de saída — use `/gate EPIC-N`.

**Progresso total: 11 / 11 stories vivas `[x]` — o MVP está fechado.** O inventário tem 19; **8 foram
canceladas** (EPIC-2 com 3, EPIC-5 com 5). A contagem antiga ("9/19, sobram 5 canceladas e 5 do
EPIC-6") estava errada nos dois números: o EPIC-6 sempre teve 3 stories, e as canceladas são 8.

**O escopo de código do MVP está fechado.** A central recebe, responde e espelha nos dois canais, com
número e caixa reais:

| Canal | Estado ao vivo |
|---|---|
| WhatsApp Oficial (Twilio) | recebe · espelha o disparo · **responde pela tela** · carimba o contexto do título |
| E-mail (Gmail) | recebe · responde na mesma thread · renova o token sozinho |

E a operação está montada: **1 admin + agentes com escopo por inbox**, 7 labels manuais, 5 respostas
rápidas, atribuição manual por decisão, log em JSON, expurgo LGPD e sonda de saúde no cron do host.
`bash scripts/verificar-operacao.sh` cobra tudo isso ao vivo — 15 asserções.

**Próximo passo: mover a fronteira pública para o Railway.** Medido em 2026-09-03 na API da Twilio: o
`sms_url` e o `status_callback` do número de produção apontam para um **túnel ngrok da máquina do
escritório**. Enquanto for assim, uma queda daqui derruba a confirmação de sacado, o link do boleto e a
mídia — não só o painel. É o bloco **B0** de `docs/plano-resiliencia.md`, não depende do domínio novo e
vem antes de todo o resto.

### 📊 Primeira medição de carga do espelho — 2026-09-04

Surto real disparado pelo painel de dev. **É a primeira prova de que o AD-12 se comporta sob carga**,
e não só na conversa avulsa.

| Medido | Valor |
|---|---|
| Disparos WhatsApp | **50**, em 340,6 s |
| Cadência | **8,8/min** — intervalo p50 de **7,34 s**, min 6,95 / máx 7,86. Regularidade dessas diz *throttle*, não capacidade |
| **Espelhadas no Chatwoot** | **50 de 50 — zero perda**, e zero erro nas 54 linhas de log do espelho |
| Destino | **1 conversa, 1 contato** — os 50 foram para o mesmo número. Isto mede **vazão**, não distribuição |
| Falhas de entrega | 0 · todos com `whatsapp_message_sid` · status final `read` nos 50 |
| Memória em repouso (pós-surto) | chatwoot-web 488 MB · sidekiq 309 MB · postgres 78 MB · fastapi_api 218 MB |

**Duas coisas que a medição revelou, e que valem mais que os números:**

1. **A latência de envio NÃO é medida.** `confirmacoes_disparos.enviado_em` é gravado igual a
   `created_at` — os 50 deram `0,00 s`, que é ausência de instrumentação, não velocidade. Enquanto for
   assim, não dá para responder "quanto demora um disparo".
2. **O carimbo veio parcial, e por desenho:** a conversa ficou com `cnpj`, `cedente` e
   `valor_em_aberto`, sem `titulo_id`, `dias_atraso` e `link_boleto`. É o esperado — o disparo cobria
   um **lote** (e `titulo_id` de um título só descreveria parte dele) e `dias_atraso` só a régua
   preenche. Confirma o AD-13: campo que o disparo não conhece é **omitido**, não gravado vazio.

**O que este surto NÃO mede:** CPU durante o pico (não foi capturado — o surto já tinha terminado
quando fomos olhar), comportamento com destinatários distintos, e o espelho **atravessando a
internet**, que é como ele vai rodar do Railway.

**A Fase 3.5 deixou de ser gate.** Ela existia para decidir *onde a central roda*, e essa decisão saiu
em 2026-09-03: máquina do escritório 24h, VPS num segundo momento. O que resta dela — pico de disparo,
CPU média, crescimento do volume — vira **janela de observação**, útil para dimensionar a VPS futura,
não bloqueante para nada.

A **Fase 4** (fronteira pública) está prevista e rastreada em **`docs/fase-4-premissas.md`** — dois
eixos independentes (*onde executar*, decidido pela 3.5 · *como acessar*, decidido pelo domínio), o
que um domínio novo destrava, as dívidas que caem e as que **não** caem, e o que levar à diretoria.
Os **dois eixos já foram decididos** (2026-09-03) e a decisão virou **AD-15** em
`docs/architecture.md`: domínio novo aprovado, execução na máquina do escritório 24h, PaaS descartada
para a central, Cloudflare no plano gratuito. O passo a passo está em
**`docs/runbook-cloudflare.md`** e a queda é tratada como certa em **`docs/plano-resiliencia.md`**.
⚠️ O **monorepo está no Railway**: o espelho deixa de trafegar por rede privada e passa pela internet —
consequências no §2.1 do doc de premissas. Nada iniciado.

---

## EPIC-1 — Fundação da Plataforma

Chatwoot self-hosted na infra da Flash: deploy reproduzível, banco isolado, versão fixada, backup validado.

| # | Story | Status | Commit |
|---|---|---|---|
| 1.1 | Stack Docker da central sobe com um comando (FR-1) | [x] | |
| 1.2 | Banco da central isolado dos bancos de domínio (FR-1, AD-9) | [x] | |
| 1.3 | Versão fixada e procedimento de upgrade (FR-2) | [x] | |
| 1.4 | Backup e restore validados (FR-3) | [x] | |

**Gate EPIC-1** (reescrito em 2026-09-02 pelo AD-10 — o enunciado original exigia Caddy e HTTPS local, que saíram): `docker compose up -d --wait` sobe web + Sidekiq + Postgres/pgvector + Redis, **com os canais já semeados**; a UI responde em `127.0.0.1:${CHATWOOT_HOST_PORT}`; o TLS externo é da borda, não do Chatwoot; dados persistem após restart; imagem com **tag fixa** (nunca `latest`); Postgres próprio, sem credencial cruzada com Twenty/Supabase; restore de backup recompõe conversas e anexos num ambiente limpo.

**Gate verificado ao vivo em 2026-07-13 (dev) — evidência da stack COM Caddy, que não existe mais:**
`docker compose up -d --wait` sobe os 6 containers healthy com um
comando · `https://inbox.localhost` responde (HTTP→HTTPS 308; cert da CA interna em dev) ·
`bash scripts/smoke-test.sh` prova que
conversa, mensagem e anexo sobrevivem ao restart · `bash scripts/verificar-invariantes.sh` valida tag fixa `-ce`, banco próprio
sem credencial cruzada, usuário não-superusuário, sem dblink/fdw, só o Caddy publicando porta ·
`bash scripts/backup.sh` + `bash scripts/restore.sh --verificar` recompõem banco **e** anexos num ambiente limpo.

**Reverificado em 2026-09-02, com o banco zerado e a stack nova:** `docker compose up -d --wait`
sobe tudo e o `chatwoot-seed` recria conta, inbox oficial e inbox de e-mail sem intervenção — foi a
prova do seed automático que o AD-10 prometia.

**Pendências de produção (passo manual do operador — `docs/runbook-deploy.md`):** preencher o `.env`
de produção com segredos próprios, criar o admin em `/installation/onboarding`, configurar o SMTP
transacional, agendar a cópia offsite criptografada do backup, e satisfazer a **especificação do
ingresso** (as 5 linhas em `runbook-deploy.md`) antes de expor.

---

## ~~EPIC-2 — Canal WhatsApp Prospecção~~ `[CANCELADO 2026-09-02 — AD-11]`

3 stories, 2 runbooks e 5 scripts removidos na Fase 1.1. O que aconteceu enquanto o épico viveu está
no **Registro de sessões** (2026-07-13 e 2026-07-14), incluindo o fan-out provado ao vivo.

A regra que sobreviveu ao épico: **prospecção fria sai por e-mail, nunca por WhatsApp** — o número
oficial é exclusivo de cobrança e transacional.

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
| a central não origina disparo em massa | `bash scripts/verificar-canal-oficial.sh`: zero campanhas na inbox (AD-6) |

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
`X-Twilio-Signature`. O inbound legítimo chega pelo relay do monorepo (que já validou) pela rede
`flash-espelho`, sem tocar em porta publicada. Quem barra o path para a internet é a **borda**:
`deploy/ngrok-policy.yml` devolve **403**, verificado ao vivo por `verificar-canal-oficial.sh`.
O `RELAY_TOKEN` continua viajando no `X-Relay-Token` — mas nada o exige na entrada, e é por isso que
o gate da borda é obrigatório em toda exposição (ver a especificação em `docs/runbook-deploy.md`).

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
   **falha se ela sobreviver**; `bash scripts/verificar-invariantes.sh` recusa conta de teste e exige **uma única** conta.
2. **Proxy que reescreve header quebra a autenticação da API.** O Chatwoot autentica com
   `api_access_token`, e proxy que descarta header com underscore (defesa contra request smuggling)
   faz o cliente levar **401 com token válido** — a UI não sofre, porque usa cookie. Falando direto
   com o Rails o problema não existe. → `bash scripts/verificar-invariantes.sh` prova ao vivo que a
   API responde 200 com o token; qualquer ingresso futuro tem de manter essa prova verde.
3. **`env_get` não aparava espaço/`\r`** do valor lido do `.env`. Espaço sobrando num SID vira URL
   inválida; numa senha de banco, falha de autenticação sem pista. → aparado nos 10 scripts, e o
   `bash scripts/verificar-invariantes.sh` detecta a sujeira (o Docker Compose **não** apara — passa o valor cru ao container).
4. **`bash scripts/verificar-invariantes.sh` comparava `.env` e `.env.example` numa direção só**, e mesmo assim afirmava "mesmas
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
| 4.2 | Contexto de domínio carimbado na conversa (FR-10, AD-13) | [x] | `d9b680f` + `564e634` (monorepo) |

## ✅ Gate da STORY-4.1 verificado AO VIVO (2026-07-14, caixa real de produção)

Com a caixa `operacional@flashcapital.com.br` (Google Workspace, OAuth):

| Critério do gate | Evidência |
|---|---|
| e-mail que chega na caixa vira conversa na inbox `E-mail` | **8 conversas reais** puxadas na 1ª sincronização (NF, boletos, Jotform, mailer-daemon) |
| resposta pela central volta ao remetente | resposta digitada na central → **entregue** na caixa do destinatário |
| a resposta cai na **mesma thread** | a mensagem inbound trouxe o `Message-ID` do Gmail (`CAL=_anO9…`); é dele que o mailer monta o `In-Reply-To` + `References`. `Reply-To` = a própria caixa |
| **o canal se renova sozinho** | forçamos `expires_on` para o passado: o refresher chamou o Google, renovou, **preservou o `refresh_token`** — e o IMAP **autenticou com o token renovado** |
| o canal vive sem o andaime do OAuth | `FRONTEND_URL` devolvida a `https://inbox.localhost` e a ponte derrubada: `bash scripts/verificar-canal-email.sh` **continua verde** |

**Ainda não exercitado:** a janela de ~24h do IMAP (`SINCE hoje−1`) — o canal tolera o Sidekiq fora do ar
por horas, mas acima de ~24h o que chegou no buraco não é mais buscado. Não dá para provar sem esperar.

**Gate EPIC-4:** e-mail que chega na caixa vira conversa na inbox `E-mail`; resposta pela central volta ao remetente na mesma thread; e a conversa de cobrança carrega o contexto do título nos `custom_attributes` — **inclusive quando a conversa foi reusada**, que é o caminho comum.

> **Gate EPIC-4: PASS** (2026-09-02). As duas metades verificadas ao vivo: o canal de e-mail refeito
> do zero depois do banco zerado (9 checks verdes) e o carimbo provado em conversa **reusada**, com
> número e título reais.

> **EPIC-4 fechado.** A 4.1 exigiu o passo manual do operador (OAuth Client no Google Cloud, 3
> chaves no `.env`, a dança do OAuth) — refeito do zero em 2026-09-02 depois do banco zerado, com o
> checklist de `docs/runbook-canal-email.md`.
>
> **A 4.2 mudou de conteúdo com o AD-13** e foi entregue no monorepo: em vez de reconciliar
> identidade depois do fato, o disparo carimba o contexto que já tem em mãos. São **8 atributos**
> (`titulo_id`, `cnpj`, `cedente`, `numero_nf`, `data_vencimento`, `valor_em_aberto`, `dias_atraso`,
> `link_boleto`), definidos em `atributos.py::CHAVES` e espelhados como
> `CustomAttributeDefinition` pelo `chatwoot_seed.rb` deste repo — **as duas listas têm de bater**,
> senão o valor é gravado e fica invisível. A armadilha que o desenho evita: `_garantir_conversa`
> tem duas saídas, e o carimbo é etapa separada para valer nas duas.
>
> **Provado ao vivo (2026-09-02):** três disparos reais (títulos 15722, 15724, 15726) reusaram a
> **mesma** conversa e ela terminou com 7 dos 8 atributos carimbados — `dias_atraso` ausente porque
> o título não estava vencido, que é o comportamento correto (campo vazio é omitido, `0` não é vazio).

**A descoberta que definiu o épico: a service account do Gmail NÃO pluga no Chatwoot.** Não é
preferência — é ausência de caminho de código. O `Imap::GoogleFetchEmailService` autentica XOAUTH2
com o `Google::RefreshOauthTokenService`, que renova por `grant_type=refresh_token` e faz
`raise 'A refresh_token is not available'` se ele faltar. Service account usa o grant **JWT-bearer**
(domain-wide delegation) e **nunca emite `refresh_token`**. Injetar um token de SA na marra faria o
canal viver **1 hora** e morrer **dentro de um job do Sidekiq**, calado. Rota escolhida: **OAuth de
usuário** (`provider=google`), com a tela de consentimento **Internal** (é Workspace) — o que dispensa
a revisão do Google para o escopo restrito `https://mail.google.com/`.

**STORY-4.1 — o que já está de pé (2026-07-14, dev).** `conectar-gmail.sh` (`bash scripts/conectar-gmail.sh`) **pré-cria**
a inbox `E-mail` (`Channel::Email`) e devolve a URL de autorização. A pré-criação não é detalhe: o
`OauthCallbackController` **cria a inbox sozinho** nomeando-a com o perfil do Google
(`users_data['name']`), o que violaria o nome fixo do glossário; pré-criada com o endereço certo, o
callback a **encontra** (`find_channel_by_email`) e só anexa os tokens. `verificar-canal-email.sh`
(`bash scripts/verificar-canal-email.sh`) recusa as três falhas silenciosas do canal. Criptografia at-rest ligada
(`ACTIVE_RECORD_ENCRYPTION_*`) — sem regressão: o `auth_token` da Twilio, gravado antes em texto puro,
continua legível (`support_unencrypted_data = true`).

**A armadilha que quase custou horas: a env var do OAuth NÃO basta.** O controller que monta a URL de
consentimento não lê o ENV — lê `GlobalConfigService.load`, que consulta a tabela
`installation_configs`. Esse loader *tenta* cair para o ENV, mas faz
`InstallationConfig.where(name: k).first_or_create(...)` e **devolve `i.value`** — e como o
`installation_config.yml` do Chatwoot **semeia a linha vazia** no deploy, o `first_or_create`
**encontra** a linha vazia, não atualiza nada, e devolve o vazio. **O ENV é ignorado para sempre.**
Sintoma: a URL de consentimento sai com `client_id` **em branco** e o Google responde um erro
genérico — sem nada de errado no `.env`. Resolvido: `bash scripts/conectar-gmail.sh` grava os valores no
`installation_configs` e limpa o cache; `bash scripts/verificar-canal-email.sh` reprova se estiverem vazios.
(De quebra: a coluna é `serialized_value` **jsonb com YAML dentro** — o próprio Chatwoot marca isso
com um `FIX ME` —, então a checagem **não pode** ser SQL; passa pelo model.)

**O consent do Gmail sai por `localhost`, nunca por túnel** — e a razão importa. O Google **aceita**
`http://localhost:3001/google/callback` (a exigência de HTTPS isenta o `localhost` **puro**;
`inbox.localhost` é subdomínio e é recusado), e a central publica exatamente ali. Cadastrar a URL do
túnel seria pior de duas formas: ela muda todo dia, e cada troca exigiria voltar ao Google Cloud.
Por isso o `conectar-gmail.sh` **recusa** rodar apontando para um túnel efêmero e imprime a receita
de localhost.

*(A ponte `socat` que existia para expor a 3000 morreu na Fase 1: com a central publicando direto em
`127.0.0.1:3001`, o `localhost` puro passou a ser o endereço real dela.)*

E o que o refresh **não** exige: `grant_type=refresh_token` não passa `redirect_uri`, então rotacionar
a `CENTRAL_URL_PUBLICA` **não** derruba um canal já autorizado — medido em 2026-09-02, 9 checks verdes
depois da troca. O Google Cloud só volta a ser tocado num **consent novo**.

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

**Por que o e-mail não apodrece como o webhook do Twilio.** O redirect URI só precisa existir **no
momento do clique**; o webhook do Twilio precisa existir **para sempre**. É essa diferença — não a
ferramenta — que fez um apodrecer por 10 dias em silêncio e o outro não.

---

## ~~EPIC-5 — Serviço de Sync (Enriquecimento de Contato)~~ `[CANCELADO 2026-09-02]`

> **Épico cancelado — ver AD-13.** O monorepo já conhece `titulo_id`, CNPJ, valor e dias de atraso no
> instante do disparo; carimbar isso nos `custom_attributes` da conversa entrega o que o Sync prometia,
> sem construir o Sync nem exigir outbox. `docs/epic-5-premissas.md` vira anexo histórico.

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
| 6.1 | Cockpit unificado e papéis de agente (FR-15) | [x] | `b213f2f` |
| 6.2 | Atribuição, labels manuais e respostas rápidas (FR-16) | [x] | `b213f2f` |
| 6.3 | Observabilidade e conformidade LGPD | [x] | `bb657b6` + `07ea955` |

**Gate EPIC-6** (reescrito em 2026-09-03 — o enunciado anterior pedia duas coisas que o Community Edition **não entrega**, e prometê-las era pior do que não tê-las): as 2 inboxes visíveis numa interface única; papéis (admin/agente) negam acesso indevido, com o escopo vindo de `inbox_members` — **não de papel customizado**, que é premium e está desligado; atribuição **manual** funcionando e a automática desligada por decisão registrada; respostas rápidas inseridas; labels manuais aplicáveis e visíveis na barra lateral; log estruturado (JSON) e alerta de saúde dos canais chegando no sino do Nexus; expurgo LGPD **agendado**; e o acesso a CPF/CNPJ **restrito por inbox** — no CE, quem abre a conversa vê o documento, porque o atributo é da conversa e a policy libera para agente.

**✅ Gate verificado ao vivo em 2026-09-03.** `bash scripts/verificar-operacao.sh` → **12 asserções verdes** *(o número é o daquele dia; o commit `6dec810` acrescentou depois os crons de backup e de ensaio de restore, e hoje o script devolve **15** — a evidência datada fica como foi medida)*. As provas que não cabem num script:

- **Papéis, avaliados pelas policies reais** (as mesmas que os controllers usam), não por leitura de código:
  `ADMIN  papel=administrator inboxes_visiveis=["WhatsApp Oficial", "E-mail"] ve_conv56=true  apaga_conv=true`
  `AGENTE papel=agent         inboxes_visiveis=["E-mail"]                     ve_conv56=false apaga_conv=false`
- **Log estruturado ao vivo**, com o que faltava para reconstituir um incidente:
  `{"method":"GET","path":"/api","status":200,"duration":26.03,"db":5.86,"host":"127.0.0.1","remote_ip":"127.0.0.1","user_id":null}`
- **Janela de 24h medida, não suposta:** `messaging_window = 86400s`, `medium=whatsapp`, `can_reply=true` na conversa mais recente do canal oficial.
- **Sonda de saúde ponta a ponta:** com o túnel derrubado de propósito, o monitor pegou a falha (e **não** caiu na armadilha do 404 do ngrok morto) e postou o alerta; a notificação chegou ao perfil `nexus` no painel do monorepo. Com o estado inalterado, **não** repetiu o aviso.
- **Seed idempotente:** segunda execução seguida = 0 objetos criados.

**O que o gate NÃO exercitou:** envio por template **fora** da janela de 24h. O mecanismo está provado (o `can_reply?` fecha e reabre, e há **45** templates aprovados sincronizados), mas o envio real exige 24h de silêncio do cliente.

---

## Dívida técnica conhecida

Itens levantados em code-review e desvios as-built. **Nenhum bloqueia o MVP** — mas os marcados
"antes do go-live" precisam ser resolvidos antes de a operação depender disto de verdade.

| Item | Risco | Alvo |
|---|---|---|
| ~~**O `CENTRAL_ACCESS_TOKEN` do espelho pertence a uma PESSOA**~~ **DEIXOU DE SER DÍVIDA em 2026-09-04 — virou decisão.** O Vitor decidiu que **o seed não inventa usuário**: o único e-mail root é o do administrador (`adm@flashcapital.com.br`), e é o token dele que o espelho usa. Conta de máquina criada por seed seria usuário fantasma, sem dono e sem auditoria. O seed passou a gravar o valor do `.env` no token do admin — a instalação nova continua sem copiar nada da UI. | **consequência aceita, e é preciso saber dela:** revogar esse token derruba o acesso da pessoa junto, e apagar o usuário admin quebra o espelho **em silêncio** (AD-12) | ✅ decidido · `verificar-operacao.sh` cobra que exista administrador com `access_token` |
| ~~**A janela de 24h não está modelada em ponto nenhum do código**~~ **MEDIDO EM 2026-09-03: era falso para a tela, e verdadeiro só para a API.** O Chatwoot modela a janela de primeira classe (`Conversations::MessageWindowService`), e ela vale para o canal oficial porque a inbox foi criada com `medium: whatsapp`: passadas 24h o editor **fecha**, aparece banner em pt-BR e a UI só oferece os templates aprovados. **A atendente está protegida.** O que não existe é defesa server-side: `Base::SendOnChannelService` e o `MessagesController` não consultam `can_reply?`, e o `Twilio::SendOnTwilioService` não tem o fallback-para-template que o `Whatsapp::SendOnWhatsappService` tem. Quem posta **pela API** — monorepo, script, bot — passa fora da janela, vira job, e só falha na Twilio. Consertar exigiria fork (AD-7). **Regra: quem chama a API checa antes.** | envio por API fora da janela falha depois, sem erro na tela de quem chamou | ✅ o lado da atendente está fechado · o lado do chamador é regra em `runbook-operacao.md` |
| **O inbound é recebido, classificado e descartado sem persistir o corpo.** No monorepo, o `twilio_webhooks_router` usa o `Body` para a confirmação de sacado e o repassa ao espelho, mas **não o grava** em base própria. Se o espelho falhar (e ele falha em silêncio — AD-12), o conteúdo da resposta do cliente não existe em lugar nenhum sob controle da Flash Capital: só na Twilio e no aparelho do cliente. *(extraído do ADR-0014 arquivado)* | perda definitiva do teor da resposta do cliente | **`plano-resiliencia.md` §F2** — persistir o corpo é pré-requisito de qualquer reenvio (§F1) |
| ~~**Handoff Agente ↔ humano não existe.**~~ **SEM OBJETO desde 2026-09-02**: o Agente N8N atendia no número de prospecção, que saiu junto com a Evolution (EPIC-2 cancelado). Não há mais conversa de lead na central para assumir. | — | ✅ sem objeto |
| **O espelho PERDE, e não tem como recuperar.** A metade "duplicar" desta dívida morreu com a Evolution (era replay do Baileys). Sobra a metade cara, hoje elevada a **AD-12**: `chatwoot_mirror.py` não tem retry, fila nem backfill, e nenhum job reconcilia depois — a falha é logada e descartada. Central fora do ar = **buraco permanente** no painel, não atraso. Decidir onde a central roda **é** decidir a completude do painel. | painel amostral, sem aviso na UI | **`plano-resiliencia.md` §F1** (fila de reenvio no monorepo) — **não cai com o domínio**. A 3.5 deixou de ser gate; até o F1, "amostral" continua declarado por escrito |
| ~~**Anti-SSRF do Chatwoot desligado para rede privada**~~ (`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`). **FECHADA em 2026-09-02** (`eebbbb7`): o flag só existia para o Chatwoot alcançar a Evolution na rede privada; com a Evolution fora (AD-11), voltou a `false` e a proteção está ligada. | — | ✅ fechada |
| ~~**Retenção de conversa sem aval jurídico**~~ **DECIDIDA E AGENDADA em 2026-09-02.** `RETENCAO_CONVERSAS_DIAS=1825` deixou de ser default técnico: o operador aprovou os **5 anos** por escrito. O expurgo (`retencao-conversas.sh`) entrou no cron do host (domingo 04:10, com `flock`, log em `backups/retencao.log`) e o dry-run foi validado. **Resíduo, hoje menor:** a tarefa `WSL-Always-On` do Windows ancora a VM no logon (`docs/runbook-wsl-autostart.md`, item **R1**) — a ação está provada, mas ainda **não** sobreviveu a um reboot real sem ninguém abrir terminal. Até essa prova, tratar como **passo que pode não disparar**, e cobrar execução no `backups/retencao.log`, não no cron registrado. | LGPD / prova em disputa de dívida | ✅ decidida · o resíduo virou **`plano-resiliencia.md` §R1**, hoje **implementado** (`docs/runbook-wsl-autostart.md`); falta só a prova num reboot real |
| **Identidade dupla no canal Twilio: telefone e BSUID.** O inbound real criou **dois** `contact_inbox` para o mesmo contato: `whatsapp:+553182210297` (telefone) e `whatsapp:BR.4456758834604506` (o **BSUID**, identificador novo da Meta que a Twilio manda em `ExternalUserId`). Hoje o Chatwoot prefere o do telefone (`twilio_whatsapp_primary_source_id`) e é ele que o espelho do monorepo usa — então disparo e resposta casam. Mas a Meta está migrando para payloads **só com BSUID** (o próprio código do Chatwoot já trata esse caso). No dia em que o `From` vier sem telefone, o inbound resolveria o `contact_inbox` do BSUID e o espelho continuaria criando o do telefone: **mesmo contato, threads separadas**. | disparo e resposta em conversas diferentes (dado não se perde; a thread racha) | monitorar; revisar quando a Meta forçar BSUID |
| ~~**Webhook do Twilio depende de URL de ngrok efêmera**~~ · ~~**Sem monitoramento do webhook**~~ **MITIGADOS em 2026-09-02.** O `tuneis-manha.sh` do monorepo fechou o laço: sobe os três túneis, grava as URLs nos `.env` dos repos que as consomem, recria os containers que precisam reler o ambiente e **escreve o `SmsUrl` e o `StatusCallback` no console da Twilio** (`scripts/tuneis_twilio.py`), provando a vida na URL pública ao final. O modo de falha que custou 10 dias em silêncio deixou de depender de alguém lembrar. **Não é conserto:** a causa (URL efêmera) continua, e o subdomínio fixo **não existe** no plano free (`ERR_NGROK_313`, medido). O conserto é o domínio estável da Fase 4. | apodrecimento automatizado, não eliminado | ✅ mitigado · conserto na Fase 4 |
| ~~**Rota de disparo em massa do monorepo sem autenticação.**~~ **JÁ ESTAVA FECHADA — verificado em 2026-09-02.** O achado era de 2026-07-13 e o monorepo consertou em 16/07, sem que este repo soubesse: `api/routers/whatsapp_dispatch.py:26` declara `APIRouter(dependencies=[Depends(require_operational)])`, e `api/tests/test_rotas_protegidas.py` cobre as rotas. A dívida sobreviveu 7 semanas só porque ninguém releu. | — | ✅ fechada no monorepo |
| **O `link_boleto` carimbado é uma URL de túnel — e ela morre amanhã.** O atributo guarda a URL pública **do dia do disparo** (`https://<aleatório>.ngrok-free.app/b/…`). Na rodada seguinte do `tuneis-manha.sh` o subdomínio muda e o link da barra lateral vira 404, em silêncio, para sempre. O histórico da mensagem não sofre (o cliente já recebeu o PDF pelo WhatsApp); quem perde é o atendente que abrir uma conversa antiga. É a mesma causa raiz do webhook que apodrece, num lugar novo — e o mesmo conserto: domínio estável. | link morto na conferência de conversa antiga | **`plano-resiliencia.md` §B0** — o link aponta para o túnel desta máquina; move junto com a fronteira, antes do domínio novo |
| **As 8 chaves de atributo vivem em dois repos e só um lado é cobrado.** `atributos.py::CHAVES` (monorepo) e as `CustomAttributeDefinition` do `chatwoot_seed.rb` (aqui) precisam bater: sem definição, o valor é gravado e **não aparece** na barra lateral, sem erro nenhum. `verificar-canal-oficial.sh` passou a cobrar as 8 definições ao vivo, o que pega o lado de cá — mas **nada** avisa se alguém acrescentar uma chave só no Python. | atributo novo nasce invisível | monitorar; fechar se o conjunto crescer |
| **`/twilio/delivery_status` da central aceita chamada não assinada.** O Chatwoot não valida o `X-Twilio-Signature` em nenhum dos dois callbacks. O `/twilio/callback` nós fechamos com o `RELAY_TOKEN` (o inbound vem do monorepo), mas o `delivery_status` **precisa** ficar público — é a Twilio que o chama direto, para as mensagens que a central envia. Forjá-lo só altera o status de entrega de uma mensagem existente. E ele **tem de** ficar alcançável: sem isso a Twilio recusa o envio da central com **21609** e a atendente não responde (AD-11.1). Mitigação possível no ingresso: allowlist dos IPs da Twilio — nunca autenticação humana, que quebraria a chamada de máquina. | status de entrega forjado (sem leitura nem envio de dados) | ingresso da Fase 4: **Bypass** (a Twilio não manda header — Service Auth ali traz o 21609 de volta), estreitando por IP |
| **O `refresh_token` do Gmail fica em TEXTO PURO no banco.** O `Channel::Email` criptografa só `imap_password`/`smtp_password`. Com OAuth, a credencial real vive no `provider_config` — **jsonb, que o Chatwoot não criptografa**, mesmo com `ACTIVE_RECORD_ENCRYPTION_*` ligado (ligamos: protege o `Hook#access_token` e habilita MFA, mas **não** cobre este caso). O token dá **leitura e envio na caixa inteira** (`https://mail.google.com/`) e **não expira**. Está no Postgres e dentro de **todo backup**. Corrigir exigiria forkar o Chatwoot — proibido (AD-7). Mitigação: `BACKUP_DIR` tratado como segredo; revogar em `myaccount.google.com/permissions` ao menor sinal. | quem tiver o backup tem a caixa de atendimento inteira | **revisado no EPIC-6 e mantido**: sem fork não há saída (AD-7). Mitigação documentada em `docs/runbook-lgpd.md` |
| **Envio de e-mail acoplado ao poller de recebimento.** O SMTP de saída usa o `provider_config['access_token']` **cru**; quem o mantém fresco é o job IMAP que roda a cada minuto. Agendador do Sidekiq parado ⇒ em até 1h a atendente **para de conseguir responder**, com falha de auth SMTP **dentro de um job** (sem erro na tela). `bash scripts/verificar-canal-email.sh` checa o registro do cron. | resposta ao cliente some em silêncio | ✅ **coberto**: `monitorar-canais.sh` cobra a idade do último enfileiramento do cron do IMAP (falha acima de 3 min) e avisa no sino do Nexus |
| **O espelho do canal oficial não está na `main` do monorepo.** `mirror_outbound`/`relay_inbound`/`_carimbar_atributos` vivem na linhagem `feat/espelho-chatwoot`, hoje dentro de `feat/regua-comunicacao-v2` — entra na `main` junto com a régua. O gate do EPIC-3 foi provado ao vivo **rodando essa branch** — mas até **merge + deploy** no monorepo, a central **não recebe** o inbound relayado nem o espelho em produção. | o EPIC-3 parece fechado e não está, em produção | monorepo — antes do go-live |
| **O Community Edition não tem trilha de auditoria.** `audit_logs` é `premium: true, enabled: false` e a tabela `audits` está vazia: **não é possível saber quem leu o CPF de quem**. O único controle de acesso é a inbox (`inbox_members`), porque o atributo é da conversa e `CustomAttributeDefinitionPolicy` libera para `administrator? || agent?`. Ligar exigiria fork (AD-7). | acesso a documento de terceiro sem rastro | limite conhecido do CE · registrado em `docs/runbook-lgpd.md` |
| **`CannedResponsesController` do Chatwoot não tem authorization.** Ao contrário de labels e automações, o controller de respostas rápidas não chama `check_authorization` e não existe `CannedResponsePolicy`: **qualquer agente cria, edita e apaga as respostas rápidas de todos**, pela API. Upstream, sem conserto possível sem fork. Mitigação: o seed recria o conjunto a cada `up`, então o estrago é reversível. | agente apaga o repertório da equipe | limite do CE · monitorar |
| ~~**3 dos 48 Content Templates têm `friendly_name` duplicado**~~ **RESOLVIDO em 2026-09-04, e era pior do que estava escrito.** Não eram cópias: eram **duas versões aprovadas**, e a de 25/08 pede uma variável a mais (`prazo_vencimento`). O catálogo apontava para a **antiga** — a revisão nunca entrou em vigor, e o `sincronizar_espelho_twilio.py --check` acusava os três como *"enviam AMOSTRA no lugar do dado real"*. Repontado para os SIDs novos (JSON do Sensei → `provision_twilio_templates.py --no-submit`), e as 3 cópias antigas **apagadas na Twilio** depois de varredura provando zero referência em código, JSON e nas 320 colunas de texto/jsonb de `internal`+`public`. Definições arquivadas em `sensei-cobrancas/arquivo/` antes de apagar, porque reenvio à Meta tem histórico ruim. **Twilio: 48 → 45, zero nomes duplicados. Espelho × catálogo: 0 divergentes.** 915 testes verdes. | — | ✅ fechado |
| **No painel do monorepo, `GET /notificacoes` e `mark-read` são globais.** Os dois recebem `current_user` e **não o usam**: todo usuário autenticado lê as notificações de todos, e "marcar lidas" marca as de todos. O sino já é um mural. Endereçar o alerta ao perfil `nexus` é, hoje, cosmético — funciona, mas não isola. *(achado ao ligar o alerta de saúde; anterior a este trabalho)* | notificação de operação visível a qualquer usuário do painel | monorepo — corrigir junto com a próxima mexida em notificações |
| ~~**Cópia offsite do backup é manual**~~ **AUTOMATIZADA em 2026-09-04.** `scripts/backup-offsite.sh` cifra os artefatos em AES256 (`gpg --symmetric`, round-trip provado) e os espelha num bucket privado do Supabase Storage via `rclone sync` — a retenção 7+4 sai de graça, por ser espelho do `BACKUP_DIR` que o `backup.sh` já poda. **Credencial escopada a storage** (S3 Access Keys), nunca a `service_role`, que furaria RLS no projeto inteiro e daria à central acesso ao banco de domínio (AD-9). **LIGADO e provado no mesmo dia:** bucket `backups` criado, chave S3 no `.env`, `rclone` instalado em `~/.local/bin` (sem sudo), 8 artefatos cifrados e confirmados no bucket, e o 5º cron instalado (30 5, depois do backup das 05:10). **Ensaio de restore feito a partir do BUCKET, não do disco:** as duas metades baixadas, decifradas e **byte-a-byte idênticas** ao original — o dump com 90 tabelas e o tar com 19 anexos. **Resíduo, e é o único que sobra:** guardar a `BACKUP_OFFSITE_PASSPHRASE` no gerenciador de senhas. Ela mora no `.env` desta máquina; se a máquina morrer e a frase só existir nela, o offsite está lá e é ilegível. | perda total em falha de host | ✅ ligado e provado · ⬜ **frase no cofre** |
| **Staging não existe ainda.** O runbook de upgrade exige validar em staging antes de produção (FR-2); hoje só há o ambiente dev local. | upgrade sem rede de proteção | antes do 1º upgrade em prod |

### Adiado para a fase 2 (registrado em `docs/architecture.md` §Deferred)

| Item | Por quê ficou fora do MVP |
|---|---|
| **Dashboard App (iframe)** com dado de domínio ao vivo | o MVP usa só atributos empurrados; mantém a central leve (AD-2) |
| **Sync bidirecional** (central → domínio) | MVP é unidirecional |
| **Campanhas/disparo em massa na central** | permanece no monorepo (AD-6) |
| **SSO / embed na plataforma interna** | fase 2 |
| **Novos canais** (Instagram, webchat, Telegram) | o padrão de adapter (AD-4) já os acomoda |

---

## Registro de sessões

| Data | Épico | Stories | Notas |
|---|---|---|---|
| 2026-09-03 | — | revisão do `scripts/` | **Revisão dos 16 scripts, e o que dava para tirar da mão.** Nenhum órfão, nenhum obsoleto — mas o `backup.sh` era o único recorrente **fora do cron** (último par feito à mão em 02/09) e o `verificar-operacao.sh` dava verde assim mesmo, porque só cobrava dois jobs. Entraram no cron backup (05:10 diário) e `restore.sh --verificar` (sáb 05:40), os dois rodados de ponta a ponta antes de agendar. **05:10 e não 03:10 de propósito**: o expurgo LGPD roda domingo 04:10, e um backup antes dele congelaria por quatro semanas exatamente a conversa que a política acabou de apagar. Apagado um dump órfão de julho que estava fora do glob da poda — logo, eterno. Três blocos novos no seed, para a instalação nova não depender de shell na VPS: **`account.locale` nascia `en`** (o `ApplicationMailer` cai nele, então todo e-mail que a central envia ia com envelope em inglês, e **nenhuma tela do CE oferece a troca**); **Content Templates sincronizados na primeira vez** (só quando o canal está sem template — seed de boot não pode depender da Twilio em toda subida); e a **conta de máquina do espelho**, que materializa o `CENTRAL_ACCESS_TOKEN` do `.env` em vez de alguém buscá-lo na UI. Foi ao medir isso que apareceu o achado: **o token em uso pertence ao admin humano**, o oposto do que a `security.md` afirmava. Doc corrigida, dívida aberta. `runbook-deploy.md` ganhou a sequência de instalação inteira, o truque do `DOCKER_HOST=ssh://` (roda o script no seu notebook, age na VPS) e o caminho pela tela como **plano B** — com a constatação de que pela tela sozinha a instalação **não fecha**: `INSTALLATION_NAME`/`BRAND_NAME` e `account.locale` não existem em UI nenhuma. Varridos ainda três resíduos do dicionário de labels morto (`CLAUDE.md`, `architecture.md` e a jornada UJ-3 do `prd.md`, que mandava filtrar por uma label inexistente). |
| 2026-09-02 | — | Fases 0→3 | **A simplificação inteira, e o marco que a estrutura antiga nunca alcançou: a atendente responde pelo WhatsApp, pela tela.** Fases 0 a 3 executadas nos três repos. **Saíram:** Evolution (+`lid_service`, `evolution_db`, 5 scripts, 2 runbooks), Caddy (nos dois repos), Makefile, a rede `flash-canais`, a ponte socat, o EPIC-2 e o EPIC-5. **Ficou:** um `compose.yaml` na raiz, `docker compose up -d --wait` como comando único, e a rede `flash-espelho` com exatamente 2 membros. **Bancos zerados a pedido do operador** — Chatwoot (697 conversas, 196 anexos, 84 MB) e CRM (Twenty + n8n: 15 workflows, 4 credenciais, 37 execuções) —, mais 5 volumes órfãos e o `evolution_db`, que não pode voltar porque o script de init dele foi apagado. As duas stacks subiram com **um comando cada**, o que foi a prova do seed automático (AD-10). Reconfiguração do zero: conta 1, inbox 1 (WhatsApp Oficial, `medium=whatsapp`, 48 Content Templates), inbox 2 (E-mail, OAuth completo). **STORY-4.2 entregue** (AD-13): 8 atributos carimbados em etapa separada, provados em conversa **reusada** com 3 disparos reais. **E o 21609 caiu:** `Channel::TwilioSms` anexa `status_callback` sem condição, então `FRONTEND_URL` público não é UX — é pré-condição de envio; a chave `CENTRAL_URL_PUBLICA` virou o 3º túnel, com `deploy/ngrok-policy.yml` negando `/twilio/callback` na borda. Medições que mudaram decisões: a Twilio **aceita** um StatusCallback que devolve 404; a traffic policy do ngrok **funciona** no plano free, mas subdomínio próprio **não** (`ERR_NGROK_313`); rotacionar a URL **não** quebra o Gmail já autorizado; o Rack::Attack já bloqueia na 6ª tentativa. Cron da retenção LGPD agendado (5 anos, aprovados). Commits: `1cf69fb`→`b038921` (inbox, 21) · `a9256b7`→`adca1f2` (crm, 9) · `91b2d13`→`c1f013f` (monorepo, 7). |
| 2026-09-03 | EPIC-6 | 6.3 | **Observabilidade e LGPD — e o sino que nunca tocou.** Log estruturado custou uma linha (`LOGRAGE_ENABLED=true`): o initializer já estava na imagem, desligado. A sonda `monitorar-canais.sh` entrou no cron de hora em hora com 6 sinais de **liveness** — os `verificar-*.sh` cobram configuração, que não muda sozinha; isto cobra o que muda. Dois deles não existiam em lugar nenhum: **`Channel::TwilioSms` não inclui `Reauthorizable`**, então "canal WhatsApp desconectado" não existe para o Chatwoot e a única matéria-prima é `messages.status=3` + `external_error`; e a prova do túnel passou a ser `/api` devolver a **mesma versão**, porque **ngrok morto responde 404** — idêntico ao 404 legítimo do Rails, o que fazia a asserção de ontem passar com o túnel caído. O alerta chega no **sino do Nexus** (`POST /notificacoes/alerta` no monorepo, `X-Monitor-Token`, fecha por falta de env). Ao ligar, descobrimos que **a tabela `notificacoes` tinha zero linha desde que existe**: o único produtor gravava o **uuid** do perfil numa coluna que é **FK para `perfil(email)`**, todo INSERT violava a constraint e o `except` engolia. Corrigido, com teste. O sino também não fazia polling — só buscava ao abrir o dropdown, o que tornaria o alerta invisível; ganhou um poll de 60s. LGPD: `docs/runbook-lgpd.md` novo, com o direito de exclusão do titular cobrindo os **dois** lados e os backups, e dizendo o que o CE **não** entrega (sem trilha de auditoria, sem papel customizado). |
| 2026-09-03 | EPIC-6 | 6.2 | **Atribuição, labels e respostas rápidas.** O seed passou a semear 7 labels e 5 respostas rápidas, e a **reconciliar** as inboxes existentes — antes ele só dizia "já existe, não recrio". `enable_auto_assignment` estava `true` nas duas inboxes **mentindo**: a fila do `AutoAssignment::AssignmentService` sai de `inbox_members` ∩ agentes online, e com `inbox_members` vazio ele nunca distribuiu nada. Passou a `false`, que é a verdade e é a decisão (com um operador só, round robin é ruído). O dicionário de labels foi **refeito, não estendido**: `lead-frio`/`lead-qualificado` eram vocabulário do EPIC-2 cancelado, `nao-identificado` era a label que o Sync aplicaria, e `cliente-ativo`/`em-cobranca`/`inadimplente` são estado do **título** — repeti-los aqui criaria duas verdades (AD-1). O critério novo: label descreve o que a **conversa** apurou. Duas armadilhas do model viraram comentário no seed: `title` recusa espaço e força minúsculas, e `show_on_sidebar` é nullable **sem default** — não setar deixa a label existente, aplicável e invisível. |
| 2026-09-03 | EPIC-6 | 6.1 | **Cockpit e papéis.** `criar-agente.sh` novo: usa o `AgentBuilder` do próprio Chatwoot e **define a senha**, porque o convite nativo depende de um SMTP que esta instalação não tem — sem isso o agente nasce inutilizável. A senha vai por stdin para um arquivo com `umask 077` dentro do container, é lida e apagada: nunca em `argv`, nunca em env, nunca no `.env`. Papéis provados pelas **policies reais**: o agente vinculado só à inbox `E-mail` não enxerga a inbox do WhatsApp nem abre a conversa 56 (`show?=false`, `destroy?=false`). Achado que muda o gate: **`custom_roles` é premium e está desligado no CE** — não existe "agente que atende sem ver o CPF". O único controle é a inbox, e o gate foi reescrito para dizer isso em vez de prometer o que não há. A central também deixou de se apresentar como "Chatwoot". |
| 2026-09-02 | — | code-review | **Pente fino nos 37 commits, nos docs e no `.claude/` dos três repos.** O padrão achado não foi código errado — foi **doc que envelheceu contando o contrário do que passou a valer**. Os piores: o `runbook-canal-oficial.md` afirmava que "túnel ngrok não resolve de forma utilizável" e que trocar a URL "quebraria o OAuth do Gmail junto" — as duas coisas medidas como **falsas** no mesmo dia, e é exatamente a solução que entregamos; o AD-11.1 dizia que a central "não RESPONDE" pelo WhatsApp; o `PLAYBOOK-ECOSSISTEMA.md` do monorepo apontava para **conta 3 / inbox 6** (que o wipe apagou) e jurava que a 3001 "nunca" teria túnel. Reescritos como as-built. Fechadas 3 dívidas que já não existiam (rota de disparo protegida desde 16/07, webhook sem monitoramento, retenção sem cron) e abertas 2 novas achadas na varredura: o `link_boleto` guarda uma URL de túnel que morre no dia seguinte, e as 8 chaves de atributo vivem em dois repos com só um lado cobrado. Virou verificação executável: `verificar-canal-oficial.sh` passou a provar **ao vivo** as 8 definições de atributo, o 403 no `/twilio/callback` e a alcançabilidade do `/twilio/delivery_status`. |
| 2026-07-13 | — | planejamento | Documentação BMAD gerada em `docs/`: `product-brief.md` (fase 1), `prd.md` (16 FRs, glossário fechado, jornadas), `architecture.md` (spine hub-and-spoke, AD-1..AD-9, diagramas, árvore-alvo), `epics-and-stories.md` (6 epics · 19 stories com CA Given/When/Then). Decisões travadas: Evolution fica no CRM com fan-out; merge só com telefone **E** documento; disparo em massa origina no monorepo. |
| 2026-07-13 | — | setup | Scaffold do repo: `.claude/` (hooks, 5 comandos, 4 memories), `PROGRESS.md`, `CLAUDE.md`, `README.md`, `.gitignore`. 11 skills instaladas em `.claude/skills/` (incl. as oficiais `chatwoot-cli` e `twilio/ai`). Nenhum código de runtime. |
| 2026-07-13 | EPIC-1 | 1.1 · 1.2 · 1.3 · 1.4 | **A central subiu.** a raiz do repo criado: compose (Caddy 2.11.4 · Chatwoot `v4.15.1-ce` web+sidekiq+init · pgvector 0.8.5-pg16 · Redis 7.4.9), `Caddyfile`, `.env.example`, init-db e 5 scripts de operação; `Makefile` com `up/check/smoke/backup/restore-check/retencao`; runbooks de deploy, upgrade e backup. Decisões as-built: **`chatwoot-init` one-shot** (`db:chatwoot_prepare` via `service_completed_successfully`) para o `up` ser mesmo **um** comando — o compose oficial exige migração à mão; **extensões pré-criadas pelo superusuário** no init-db (o `pg_stat_statements` não é *trusted*, e o usuário da app é não-superusuário por AD-9); **`APP_DB_*`** no init para desfazer a colisão de `POSTGRES_PASSWORD` (superusuário na imagem do Postgres vs. usuário da app no Chatwoot). Gate do épico verificado ao vivo em dev. |

| 2026-07-13 | EPIC-2 | 2.1 · 2.2 · 2.3 | **Canal de prospecção ligado.** A instância `crm` (Evolution, no CRM) passou a ter **dois consumidores**: o Agente N8N (webhook global) e a central (integração nativa Chatwoot). A inbox `WhatsApp Prospecção` é criada pela própria Evolution (`autoCreate`). Ponte por rede Docker externa `flash-canais` — nada exposto na internet. Novos comandos: `make evolution`, `make fanout`, `make dedup`, `make aquecimento`. Runbooks de canal e de aquecimento. **Achados que mudaram o desenho:** (1) o Chatwoot recusa webhook/mídia em host sem IP público (anti-SSRF do `SafeFetch`) → `SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`, senão o canal falha **em silêncio**; (2) um host só tem uma porta 443 → o Caddy da central virou perfil `edge` e, no host compartilhado, o Caddy do CRM serve `inbox.<DOMAIN>`; (3) o dedup nativo da Evolution depende do import por Postgres direto (proibido por AD-9) → faxineiro `dedup-mensagens.sh` na central. Commits: `4bbccb5` (central) · `46b96b2` (CRM). Gate do épico **pendente do pareamento do chip** (manual). |

| 2026-07-13 | EPIC-3 | 3.1 · 3.2 | **Canal oficial (Twilio) ligado — e o épico foi definido por uma descoberta.** O número oficial **já tinha dono do webhook**: o monorepo recebe o inbound, valida a assinatura e alimenta a confirmação de sacado. Um número Twilio tem **um** webhook de inbound — apontá-lo para o Chatwoot quebraria a cobrança; o inverso deixaria a confirmação de dinheiro refém do chat. Desenho forçado: **o monorepo segue dono e faz fan-out**, igual ao EPIC-2. Na central: `conectar-twilio.sh` (inbox `Channel::TwilioSms` **medium=whatsapp** — é o medium que ativa a janela de 24h nativa; como `sms`, a Meta rejeitaria o texto livre pós-24h **em silêncio**), Caddy barrando `/twilio/callback` com `RELAY_TOKEN` (o `Twilio::CallbackController` **não valida** a assinatura), `verificar-canal-oficial.sh`. No monorepo (branch `feat/espelho-chatwoot`): `ChatwootMirror`, fan-out do inbound **depois** da confirmação, espelho no choke point do dispatch. **O achado que salvou o épico:** o Chatwoot **reenviaria** o disparo se a mensagem chegasse sem `source_id` — cobrança em dobro. Provado ao vivo com credencial Twilio **falsa**: com SID → `sent` sem chamar a Twilio; sem SID → `failed` (HTTP 401). Comandos novos: `bash scripts/conectar-twilio.sh`, `bash scripts/conectar-twilio.sh --status`, `bash scripts/verificar-canal-oficial.sh`. Commits: `b16dabc` (central) · `c3d5438` (monorepo, branch). Gate **pendente de credencial real**. |

| 2026-07-13 | EPIC-3 | gate | **Gate do EPIC-3 fechado ao vivo, com o número oficial real.** Mensagem recebida na inbox, resposta enviada pela central e chegando no WhatsApp, espelho do disparo caindo na conversa do contato — e a Twilio **sem nenhuma cópia** da mensagem espelhada (o guard do `source_id` segurou com credencial real: cobrança em dobro não acontece). Antes do teste com celular, a cadeia foi validada forjando uma chamada da Twilio com **assinatura HMAC-SHA1 válida** pela URL pública. O caminho até aqui foi feito de **falhas silenciosas**, e cada uma virou guard: a conta órfã que o smoke test deixou (os canais nasceram na conta de TESTE e o operador via a central vazia); o Caddy comendo o `api_access_token` por causa do underscore; o `env_get` sem aparar espaço; o `bash scripts/verificar-invariantes.sh` comparando o `.env` numa direção só. Achado colateral **grave, do monorepo**: o webhook do Twilio apontava para um túnel ngrok morto desde 03/07 — a **confirmação de sacado por WhatsApp nunca funcionou em produção**. Commits: `b16dabc`, `78beb30`, `483adc2`, `3890d31`, `c7d0df3`, `83002d2`, `fd86c4f` (central) · `c3d5438` (monorepo, branch `feat/espelho-chatwoot`). |

| 2026-07-14 | — | docs | **Faxina da documentação.** O `CLAUDE.md` afirmava "implementação NÃO iniciada — 0/19 stories", "não existe a raiz do repo" e "a próxima é a STORY-1.1" — mentira em todos os pontos, e é o primeiro arquivo que qualquer sessão lê. Reescrito com o estado real, os comandos do Makefile e os 5 as-built que mordem. Auditoria varreu os 17 docs restantes: corrigidos o README e o `runbook-canal-oficial.md` (afirmavam o espelho **em produção**, quando ele está numa branch não mergeada do monorepo), o `runbook-deploy.md` (mandava `docker compose up -d --wait` em produção sem alertar que `COMPOSE_PROFILES=edge` sobe um **segundo Caddy** e colide com o do CRM), a "Opção B" fantasma e um "acima"/"abaixo" trocado no runbook de prospecção, a árvore de fonte do `architecture.md` (listava 5 dos 12 scripts) e o cabeçalho da dívida técnica ("Nada ainda" com 9 itens logo abaixo). Nas memories — que são o que o `/story` carrega: `decisions.md` não registrava o **modo espelho** (um agente leria o AD-5 e acharia normal responder ao lead pela central) e `security.md` dizia que o inbound da central é validado por assinatura, quando quem o protege é o **`RELAY_TOKEN`** no Caddy. |

| 2026-07-14 | EPIC-4 | 4.1 | **Canal de e-mail ligado até onde é automatizável — e o épico foi definido por uma descoberta.** A **service account do Gmail não pluga no Chatwoot**: não é preferência, é ausência de caminho de código (`BaseRefreshOauthTokenService` faz `raise 'A refresh_token is not available'`; SA usa JWT-bearer e nunca emite refresh_token). Rota: **OAuth de usuário**, consent screen **Internal** (Workspace) — dispensa revisão do Google no escopo restrito. Novos: `conectar-gmail.sh` (`bash scripts/conectar-gmail.sh`/`gmail-status`/`gmail-url`), `verificar-canal-email.sh` (`bash scripts/verificar-canal-email.sh`), `docs/runbook-canal-email.md`, e as chaves `GMAIL_*`/`GOOGLE_OAUTH_*`/`ACTIVE_RECORD_ENCRYPTION_*`. **A inbox é PRÉ-CRIADA** porque o `OauthCallbackController` a criaria com o nome do perfil Google, violando o glossário. **Três armadilhas silenciosas viraram guard ou runbook:** (1) o SMTP de saída usa o access_token **cru**, mantido fresco pelo job IMAP — **agendador parado ⇒ a atendente para de responder** em 1h; (2) re-autorizar sem revogar **não devolve refresh_token**, e o canal nasce condenado; (3) o `refresh_token` fica em **texto puro** no `provider_config` (jsonb que o Chatwoot não criptografa) — dívida técnica aceita, mitigada por revogação. Criptografia at-rest ligada sem regressão. Gate **pendente do passo manual do operador** (Google Cloud + dança do OAuth). |

| 2026-07-14 | EPIC-4 | gate 4.1 | **Gate da STORY-4.1 fechado ao vivo, com a caixa real.** A 1ª sincronização puxou **8 conversas de operação de verdade** (NF, boletos, Jotform); a resposta digitada na central chegou ao destinatário **na mesma thread** (o `In-Reply-To` sai do `Message-ID` do Gmail que veio no inbound). E o teste que mais importava: **forçamos o `expires_on` para o passado** e o refresher renovou o token no Google, preservou o `refresh_token` e o **IMAP autenticou com o token renovado** — o canal não morre em 1h. Andaime removido (ponte derrubada, `FRONTEND_URL` devolvida) e o `bash scripts/verificar-canal-email.sh` continua verde **sem** ele, provando que o refresh não depende do `redirect_uri`. O caminho até aqui teve **duas falhas silenciosas**: a URL de consentimento saindo com `client_id` **vazio** (o controller lê `installation_configs`, não o ENV — e o Chatwoot semeia a linha vazia, então o fallback devolve o vazio); e um **falso negativo do meu próprio verificador**, que consultava a coluna `value` — quando a coluna é `serialized_value`, jsonb **com YAML dentro**. Consequência de negócio registrada: a central passou a ingerir **PII real de cliente** a cada minuto; o operador decidiu seguir (este host vira produção), e o **cron da retenção LGPD** virou bloqueador de go-live. |

| 2026-07-14 | EPIC-2 | 2.1 · 2.2 | **Chip pareado e o FAN-OUT PROVADO AO VIVO.** O chip entrou pelo **código de pareamento** (`make chip-codigo`) — sem câmera, sem UI da Evolution. A mensagem real do celular apareceu na inbox `WhatsApp Prospecção` **e** o N8N registrou execução do `WF-04-001` para o mesmo evento: **os dois consumidores viram o mesmo evento** (AD-5, o risco nº 1 do MVP). Mas o **Agente não respondeu**, e a investigação achou o que o CRM escondia. |
| 2026-07-14 | — | achados no CRM | **Duas descobertas graves no `crm-flash-capital`, ambas invalidando o "MVP FEATURE-COMPLETE".** (1) **38 nós, em 20 dos 21 workflows, estavam SEM CREDENCIAL** — todo nó que fala com o Twenty declara `authentication: genericCredentialType` e não tinha credencial atribuída. Em runtime o n8n levanta `Credentials not found` e o workflow morre, **mesmo "ativo"**. Ou seja: nenhum workflow que toca o Twenty jamais conseguiu rodar; os 38/38 gates "PASS" foram validados com teste/mock, nunca com o n8n executando. (2) As credenciais eram referenciadas por **IDs placeholder** (`REPLACE_*_CRED`) que não existiam na instância — o `secrets-setup.md` mandava cadastrar as 5 na UI, à mão. Ambos consertados (`scripts/n8n-credenciais.sh` + fiação por URL de destino). O **Agente migrou para OpenAI** por decisão do operador (`gpt-5.4-mini`): não bastava trocar a URL — o `system` vira primeira mensagem, `max_tokens` é **rejeitado** pelos gpt-5.x (é `max_completion_tokens`) e a resposta vem em `choices[0].message.content`. Os três falhariam **calados** dentro de um job. Commits: `ed59d13`, `83f2769` (CRM). |
| 2026-07-14 | EPIC-3 | revisão | **O canal oficial estava quebrado, e pior do que a dívida registrada.** O webhook do número apontava para **`https://demo.twilio.com/welcome/sms/reply`** — a URL de exemplo da própria Twilio. Não recebia mensagem, não capturava histórico, e **não alimentava a confirmação de sacado**. Tudo o mais estava certo: branch `feat/espelho-chatwoot` em uso, `chatwoot_mirror.py` dentro do container, `CHATWOOT_MIRROR_ENABLED=true`, apontando para a conta 3 / inbox 6. Reapontado para o túnel do monorepo. **É a segunda vez que esse webhook apodrece em silêncio** — vira dívida reincidente, com um item novo para monitoramento. |

> **Nota sobre este registro:** é um log **por sessão** (grão grosso). O rastreamento **por story** — com hash de commit — vive nas tabelas de cada épico acima.
