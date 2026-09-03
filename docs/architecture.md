---
name: Inbox Flash Capital
type: architecture-spine
purpose: build-substrate
altitude: feature
paradigm: hub-and-spoke com enriquecimento por eventos unidirecional (mirror hub + adapters + event-driven bridge)
scope: Central de atendimento — Chatwoot self-hosted e os providers de canal (Twilio, Gmail). Não governa a lógica interna do Twenty nem do monorepo.
status: draft
created: 2026-07-13
updated: 2026-07-13
binds: [FR-1, FR-2, FR-3, FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-10, FR-11, FR-12, FR-13, FR-14, FR-15, FR-16]
sources: [docs/product-brief.md, docs/prd.md]
companions: []
---

# Architecture Spine — Inbox Flash Capital

## Design Paradigm

**Hub-and-spoke com enriquecimento unidirecional.** O Chatwoot é o **hub** (espelho + cockpit de conversas). Cada canal é um **spoke** conectado por um **provider-adapter** (Twilio, Gmail). O contexto de negócio entra **empurrado pelo domínio no instante do disparo** (AD-13), não por reconciliação posterior. Nenhuma dependência aponta do hub para os bancos de domínio.

Mapa de camadas → responsabilidade:
- **Hub** (Chatwoot): modelo de Conversa/Contato, UI de atendimento, labels, atribuição, relatórios.
- **Adapters** (providers): tradução canal ↔ hub. Plugáveis; trocar provider não muda o modelo de conversa.
- **Domínio** (Twenty, Supabase/monorepo): fontes da verdade de dados de negócio. Emitem eventos; nunca são consultados em runtime pelo hub.

## Invariants & Rules

### AD-1 — Chatwoot é espelho, nunca fonte da verdade de dados de domínio
- **Binds:** all
- **Prevents:** perda de soberania do dado e acoplamento do domínio à central.
- **Rule:** nenhum dado de negócio autoritativo (contato de domínio, contrato, operação, cobrança) é criado ou editado somente na central. A verdade de conversa é do Chatwoot; a verdade de negócio é do Twenty/Supabase.

### AD-2 — Enriquecimento é unidirecional e assíncrono (domínio → central) `[REVISADO 2026-09-02 — ver AD-13]`
- **Binds:** FR-11, FR-12, FR-13, FR-14
- **Prevents:** a central entrar no caminho crítico do domínio.
- **Rule:** o domínio só empurra para o Chatwoot — hoje pelo `chatwoot_mirror.py` do monorepo, no instante do disparo (AD-13). O Chatwoot nunca faz chamada síncrona aos bancos de domínio no caminho de atendimento. Indisponibilidade do domínio degrada o enriquecimento, não o atendimento. **Mas o inverso não vale:** central indisponível perde o evento para sempre (AD-12).

### AD-3 — Identidade de contato por chave dupla E.164 + documento `[REVISADO 2026-09-02 — a regra passa a viver no `chatwoot_mirror.py`; ver AD-13]`
- **Binds:** FR-10, FR-11
- **Prevents:** contatos duplicados e merges errados.
- **Rule:** telefone sempre normalizado para E.164 e documento para dígitos antes de casar. A regra vive no `chatwoot_mirror.py` do monorepo (`_garantir_contato`/`_garantir_conversa`), não num serviço próprio. A **sugestão de merge** para revisão humana era função do Sync e **não existe**: sem ele, o contato é resolvido pelo E.164 do disparo, que é o dado que a Twilio devolve.

### AD-4 — Um número = uma Inbox; provider é adapter plugável
- **Binds:** FR-4, FR-7, FR-9
- **Prevents:** lógica de canal vazando para o hub ou para o domínio.
- **Rule:** cada canal conectado por seu provider (Twilio/Gmail) como uma Inbox distinta. O modelo Conversa/Contato do hub é agnóstico de provider. As inboxes nascem do `chatwoot-seed`, pelos nomes fixos de `INBOX_OFICIAL_NOME` e `INBOX_EMAIL_NOME`.

### AD-5 — Convivência multi-consumidor no número de prospecção sem perda `[SUPERSEDED 2026-09-02 — Evolution removida dos dois repos; ver AD-11]`
- **Binds:** FR-5
- **Prevents:** o agente N8N e o Chatwoot "engolirem" o evento um do outro.
- **Rule:** a instância Evolution permanece no CRM e faz **fan-out** dos eventos (N8N **e** Chatwoot recebem cada mensagem); não é uma fila competida. Entrega at-least-once; consumidores idempotentes.

### AD-6 — Disparo em massa origina no monorepo; central recebe o outbound por push `[ADOPTED]`
- **Binds:** FR-8
- **Prevents:** histórico parcial (só a resposta do cliente) e a central virar motor de campanha.
- **Rule:** o pipeline do monorepo, ao disparar, também registra a mensagem outbound na conversa via API do Chatwoot. A central não origina campanha no MVP.

### AD-7 — Chatwoot Community Edition, sem fork
- **Binds:** all
- **Prevents:** dívida de manutenção de fork e uso indevido de features enterprise.
- **Rule:** imagem oficial (tag fixa), extensão só via API/webhook/automação/atributos custom. Não habilitar features da pasta `enterprise/`.

### AD-8 — Segredos fora do repo; webhooks autenticados; TLS sempre
- **Binds:** all
- **Prevents:** vazamento de credencial e ingestão forjada.
- **Rule:** tokens (Twilio/Chatwoot/Gmail) em `.env`, nunca versionados; lidos por `env_get` sem `source`, para não entrarem no ambiente do processo. Todo webhook valida origem: a assinatura `X-Twilio-Signature` é conferida **no monorepo**, dono do webhook, e o relay para a central leva o `X-Relay-Token`. O TLS do tráfego externo é terminado pela **borda**, nunca pelo Chatwoot: hoje pelo túnel da `CENTRAL_URL_PUBLICA` (AD-11.1), amanhã pelo ingresso da Fase 4. `FORCE_SSL=false` continua correto porque a borda entrega em HTTP na loopback — não porque o tráfego seja interno.

### AD-9 — Banco da central isolado dos bancos de domínio
- **Binds:** FR-1
- **Prevents:** acoplamento de dados e risco de blast-radius.
- **Rule:** Postgres próprio do Chatwoot, sem cross-DB com Twenty/Supabase — verificado por `verificar-invariantes.sh` (sem `dblink`/`postgres_fdw`, usuário não-superusuário, nenhuma credencial de banco de domínio no `.env`). O store de identidade próprio do Sync não existe (AD-13).

### AD-10 — Infra é só `docker compose`; nada publica além de loopback `[ACCEPTED 2026-09-02]`
- **Binds:** all
- **Prevents:** camada de indireção (Makefile, Caddyfile) e um porteiro compartilhado entre dois repos.
- **Rule:** um `compose.yaml` na raiz, `.env` na raiz, `scripts/` na raiz. Seed idempotente por
  `rails runner`, encadeado por `service_completed_successfully`; `docker compose up -d --wait` é o
  comando único. **Nenhum serviço publica em `0.0.0.0`** — só `chatwoot-web`, em
  `127.0.0.1:${CHATWOOT_HOST_PORT}` (3001). Sem Makefile, sem Caddy, sem `/etc/hosts`. Quando houver
  ingresso remoto, ele é um `cloudflared` dentro do compose **deste** repo — nunca um proxy
  compartilhado com o CRM.
- **A regra é sobre o compose, e continua valendo: a exposição vem de fora dele.** O túnel da
  `CENTRAL_URL_PUBLICA` (AD-11.1) é um processo do host que fala com a mesma porta de loopback — o
  compose não muda, e derrubar o túnel devolve a central ao isolamento sem tocar em arquivo nenhum.
  É por isso que a proteção do `/twilio/callback` **não pode** ser topológica: ela vive na borda
  (`deploy/ngrok-policy.yml`), que sobe e desce junto com a exposição.
- **A porta publicada é do NAVEGADOR; a via máquina-a-máquina é rede privada.** A rede
  **`flash-espelho`** tem exatamente dois membros — `fastapi_api` (monorepo) e `chatwoot-web` — e
  nada publicado nela. O CRM não entra: é isso que torna inbox e crm independentes, e é a asserção
  que `verificar-invariantes.sh` cobra.
  **Não substituir por `host.docker.internal`:** medido em 2026-09-02, um bind em `127.0.0.1` recusa
  pacote vindo da bridge do Docker (`172.17.0.1`). E o espelho falha em silêncio (AD-12), então essa
  troca não daria erro — daria um painel com buracos. É também o mesmo formato na VPS e no Railway
  (`chatwoot.railway.internal`).

### AD-11 — A central nunca é site público `[ACCEPTED 2026-09-02]`
- **Binds:** FR-4, FR-6, AD-8
- **Prevents:** expor uma ferramenta interna, e tratar a central como se ela precisasse receber o
  inbound da Twilio — não precisa, e apontar o webhook para ela quebraria a confirmação de sacado.
- **Rule:** nenhum terceiro **entrega dado** no Chatwoot. A Twilio entrega o inbound ao **monorepo**, que valida
  `X-Twilio-Signature` e relaya para `/twilio/callback` com token compartilhado
  (`conectar-twilio.sh:19`, `chatwoot_mirror.py::relay_inbound`); o e-mail entra por **polling IMAP de
  saída** (`trigger_imap_email_inboxes_job`). Sobram dois consumidores: o navegador do colaborador
  (sempre autenticado) e o monorepo (máquina-a-máquina). O `Twilio::CallbackController` **não valida
  assinatura da Twilio**, então o gate do relay é obrigatório em qualquer exposição.
- **A ressalva que o AD-11.1 abriu:** a Twilio *chama* a central num ponto só —
  `/twilio/delivery_status`, das mensagens que a própria central envia. Isso não a torna site
  público: é um path aberto de propósito, ao lado de um `/twilio/callback` negado e de um login
  obrigatório em todo o resto. "Nunca público" continua significando **nenhuma superfície anônima de
  leitura ou escrita de conversa** — nunca "nenhum pacote entra".

### AD-11.1 — A central responde pelo WhatsApp porque tem URL pública; o 21609 é o motivo `[MEDIDO 2026-09-02]`
- **Binds:** AD-10, AD-11, STORY-3.2
- **O fato forçado.** `Channel::TwilioSms#send_message` anexa `status_callback` **sem condição**,
  montado a partir de `FRONTEND_URL`. A Twilio valida esse callback na **criação** da mensagem: com a
  central em `http://localhost:3001` o `messages.create` é recusado com **21609** e a mensagem nem
  chega a sair. Não há toggle; omitir exigiria fork (proibido, AD-7). Logo **`FRONTEND_URL` pública
  não é preferência de UX — é pré-condição para responder pelo canal oficial.**
- **Rule:** o `FRONTEND_URL` do container vem da chave `CENTRAL_URL_PUBLICA` do `.env`
  (`compose.yaml` falha o boot se ela faltar), preenchida em dev pelo terceiro túnel do
  `tuneis-manha.sh` do monorepo. Toda exposição da central — túnel de dev ou ingresso de produção —
  **tem de** manter `/twilio/delivery_status` alcançável e `/twilio/callback` negado. A
  especificação está em `docs/runbook-deploy.md`; a implementação de dev, em `deploy/ngrok-policy.yml`.
- **Medido, não suposto:** (1) a Twilio aceita um StatusCallback que devolve **404** — ela valida o
  host, não o path, e é o que permite negar o `/twilio/callback` sem quebrar o envio; (2) rotacionar
  a `CENTRAL_URL_PUBLICA` **não** quebra o canal de e-mail já autorizado, porque o refresh do Gmail
  usa `grant_type=refresh_token`, que não passa `redirect_uri` (9 checks verdes depois da troca). O
  Google Cloud só é tocado num **consent novo**.
- **O que ainda falta:** a URL do túnel muda a cada rodada e o subdomínio fixo não existe no plano
  free (`ERR_NGROK_313`, medido). O custo diário é reconfigurar o `.env` — automatizado, mas real. O
  ingresso da Fase 4 substitui isso por um domínio estável.

### AD-12 — O painel é tão completo quanto o uptime de quem o alimenta `[ACCEPTED 2026-09-02]`
- **Binds:** FR-8, AD-6
- **Prevents:** a equipe de cobrança confiar num painel com buracos silenciosos.
- **Rule:** `chatwoot_mirror.py` **não tem retry, fila nem backfill** — a falha é logada e descartada, e
  nenhum job reconcilia depois. Em produção o espelho sai do Railway. Logo **cada minuto com a central
  inalcançável é um buraco permanente**, não um atraso. Decidir onde a central roda é decidir a
  completude do painel. Enquanto a central rodar em máquina de disponibilidade não-garantida, o painel é
  declarado **amostral** por escrito, na UI e no runbook.

### AD-13 — Sem Serviço de Sync: o contexto é carimbado no instante do disparo `[ACCEPTED 2026-09-02]`
- **Binds:** FR-11..FR-14 (anulados), STORY-4.2
- **Prevents:** construir reconciliação posterior para um dado que já está na mão.
- **Rule:** **EPIC-5 cancelado.** O monorepo já conhece `titulo_id`, CNPJ, valor e dias de atraso no
  instante do disparo; esse contexto vai nos `custom_attributes` da conversa. Push unidirecional no
  momento do disparo em vez de reconciliação. A central continua sem consultar banco de domínio em
  runtime — o espírito do AD-2 é preservado sem o serviço que ele pressupunha.
- **Como, e por que não do jeito óbvio:** o carimbo é uma etapa **separada**
  (`chatwoot_mirror.py::_carimbar_atributos`), chamada depois que `conversa_id` foi resolvido —
  **não** dentro de `_garantir_conversa`. Aquele método tem duas saídas, reuso e criação, e o reuso
  é o caminho comum (um sacado em cobrança já tem thread). Pôr os atributos no corpo do POST de
  criação passaria no teste e não carimbaria nada em produção.
- **O endpoint substitui, não mescla:** `POST /conversations/{id}/custom_attributes` faz
  `conversation.custom_attributes = params[...]`. Cada carimbo manda o conjunto completo, e um
  disparo que não conhece um campo o apaga. É deliberado: num painel de cobrança, dado ausente é
  melhor que `dias_atraso` de três meses atrás.
- **O conjunto é fechado e vive num lugar só:** `api/integrations/chatwoot/atributos.py::CHAVES` no
  monorepo — `titulo_id`, `cnpj`, `cedente`, `numero_nf`, `data_vencimento`, `valor_em_aberto`,
  `dias_atraso`, `link_boleto`. Como a semântica é substituição, dois produtores com conjuntos
  diferentes se sobrescreveriam em silêncio; por isso **só entram atributos do TÍTULO**, que todo
  caminho de disparo consegue preencher. Estado da régua (fase, recompra, protesto) fica de fora de
  propósito: só o `dispatch_gateway` o conhece, e o disparo por catálogo o apagaria no envio seguinte.
- **Os mesmos 8 nomes têm de existir como `CustomAttributeDefinition`** neste repo
  (`scripts/seed/chatwoot_seed.rb`). A barra lateral do Chatwoot **itera as definições**, não as
  chaves gravadas: sem definição o valor é salvo e fica invisível. São duas listas em repos
  diferentes que precisam bater — `verificar-canal-oficial.sh` cobra as 8 definições ao vivo, mas
  nada cobra o lado Python. Mexeu em `CHAVES`, mexa no seed no mesmo dia.

### AD-14 — Quem restringe acesso é a inbox, não o papel `[MEDIDO 2026-09-03]`
- **Binds:** FR-15, STORY-6.1, STORY-6.3, NFR de privacidade
- **Prevents:** prometer no gate um controle de acesso que o Community Edition não tem.
- **O fato medido:** o CE tem **dois** papéis, `agent` e `administrator`
  (`AccountUser` enum). `custom_roles` é `premium: true, enabled: false` e o modelo **não existe na
  imagem** — não é configuração faltando, é código ausente. Ligar exigiria fork, que o AD-7 proíbe.
- **A consequência que ninguém pode ignorar:** o CPF/CNPJ é atributo da **conversa**, e
  `CustomAttributeDefinitionPolicy` libera para `administrator? || agent?`. Portanto **quem consegue
  abrir a conversa vê o documento.** Não há "agente que atende sem ver o CPF".
- **Rule:** o escopo de um agente é a lista de `inbox_members`, e só. Um agente entra **apenas** nas
  inboxes de que precisa (`scripts/criar-agente.sh --inbox`). Agente sem inbox nenhuma vê uma tela
  vazia; agente em todas vê todo documento carimbado. `verificar-operacao.sh` cobra os dois extremos.
- **O que sobra de controle real:** listagem e abertura de conversa por `inbox_members`
  (`User#assigned_inboxes` → `InboxPolicy::Scope` → `ConversationFinder`); exclusão de conversa
  restrita a administrador (`ConversationPolicy#destroy?`); telas de configuração escondidas de quem
  não é admin. **Não há trilha de auditoria** (`audit_logs` é premium): não se sabe quem leu o quê.
- **Efeito no gate:** o enunciado do EPIC-6 pedia "acesso a CPF/CNPJ restrito por papel". Foi
  reescrito para "restrito por inbox", que é o que existe. Procedimento em `docs/runbook-lgpd.md`.

### Diagrama de direção de dependência (quem pode depender de quem)

```mermaid
graph LR
  subgraph Canais
    TW[Twilio / Meta API]
    GM[Gmail IMAP/SMTP]
  end
  subgraph Central["Central (127.0.0.1:3001)"]
    CW[Chatwoot Hub]
  end
  subgraph Domínio
    MONO[Monorepo API/Worker<br/>+ Supabase]
  end

  TW -->|inbound + delivery status| MONO
  MONO -->|espelho: mensagem + custom_attributes<br/>rede flash-espelho| CW
  CW -->|polling IMAP DE SAÍDA| GM
  TW -. NUNCA fala com a central .-> CW
  CW -. NUNCA consulta o domínio .-> MONO
```

Duas coisas que o desenho torna óbvias e que decidem o resto:

1. **Nenhum terceiro alcança a central.** A Twilio entrega ao monorepo (que valida
   `X-Twilio-Signature` e faz o relay); o e-mail entra por polling **de saída**. Sobram dois
   consumidores: o navegador do colaborador e o monorepo (AD-11).
2. **A seta do espelho não tem volta nem retry.** Falhou, o evento se perde (AD-12).

## Consistency Conventions

| Concern | Convention |
| --- | --- |
| Naming (labels) | kebab-case, **dicionário fechado** do Glossário do PRD (`lead-frio`, `lead-qualificado`, `cliente-ativo`, `em-cobranca`, `regua-etapa-N`, `inadimplente`, `nao-identificado`). Sem sinônimos. |
| Naming (atributos custom) | snake_case: `cnpj`, `cpf`, `status_operacao`, `dias_atraso`, `valor_em_aberto`, `origem`, `link_twenty`, `link_supabase`, `source_twenty_id`, `source_supabase_id`. |
| Naming (inboxes) | fixos: `WhatsApp Oficial`, `E-mail`. |
| Data & formats | telefone E.164; documento = só dígitos para casar; timestamps UTC; ids de origem guardados como atributos `source_*_id` para link reverso. |
| State & cross-cutting | enriquecimento **idempotente** (upsert por identidade); retry com backoff exponencial em falha transitória; auth por token; toda config por env; logs estruturados por serviço. |

## Stack

| Name | Version |
| --- | --- |
| Chatwoot (Community Edition) | **`v4.15.1-ce`** — fixada em `.env` (`CHATWOOT_TAG`); upgrade em `docs/runbook-upgrade.md` |
| PostgreSQL (com pgvector) | **`pgvector/pgvector:0.8.5-pg16`** |
| Redis | **`7.4.9-alpine`** |
| Twilio WhatsApp (Meta API, existente no monorepo) | provider atual |
| Gmail | IMAP/SMTP com OAuth (XOAUTH2) |
| Docker Compose | v2 — sem Makefile, sem proxy, sem serviço próprio (AD-10, AD-13) |


## Structural Seed

### Visão de containers (deployment)

```mermaid
graph TB
  NAV[Navegador do colaborador]
  subgraph Central["compose deste repo"]
    direction TB
    INIT[chatwoot-init<br/>one-shot: migrações]
    SEED[chatwoot-seed<br/>one-shot: canais + configs]
    CWWEB["chatwoot-web<br/>publica 127.0.0.1:3001"]
    CWWORKER[chatwoot-sidekiq]
    PG[(postgres+pgvector)]
    RD[(redis)]
    INIT ==>|completed| SEED
    SEED ==>|completed| CWWEB
    SEED ==>|completed| CWWORKER
    CWWEB --> PG
    CWWEB --> RD
    CWWORKER --> PG
    CWWORKER --> RD
  end
  subgraph HostMono["compose do monorepo"]
    APIMONO[fastapi_api]
    SUPA[(supabase)]
    APIMONO --> SUPA
  end
  NAV -->|loopback| CWWEB
  APIMONO ==>|rede flash-espelho<br/>chatwoot-web:3000| CWWEB
```

**As setas grossas são as duas que quebram calado.** A cadeia
`init → seed → web/sidekiq` é `service_completed_successfully`: se o seed falhar, a stack não sobe —
e é assim que se quer, porque um Chatwoot sem as inboxes aceitaria o espelho e o jogaria fora. A
`flash-espelho` tem **dois** membros e nada publicado; a porta em `127.0.0.1` é do navegador e
**não** é alcançável de dentro de container.

### Ambientes
- **staging** e **produção** com a mesma composição; upgrades de versão do Chatwoot validados em staging antes de produção (FR-2).
- Segredos por ambiente em `.env` fora do repo (AD-8).

### Modelo de entidade da central

A central usa **só** o Contact/Conversation/Message do próprio Chatwoot. Não há store de identidade
próprio: o monorepo conhece `titulo_id`, CNPJ, valor e dias de atraso **no instante do disparo** e
carimba tudo nos `custom_attributes` da conversa em `chatwoot_mirror.py::_carimbar_atributos` (AD-13)
— etapa separada, chamada depois que a conversa está resolvida. **Não** dentro de
`_garantir_conversa`: ele tem duas saídas, e o reuso é o caminho comum (ver a nota em AD-13).

```mermaid
erDiagram
  IDENTITY_MAP ||--o| CHATWOOT_CONTACT : referencia
  IDENTITY_MAP {
    string e164
    string documento
    string source_twenty_id
    string source_supabase_id
    int chatwoot_contact_id
    string status "merged | suggested | unresolved"
  }
  MERGE_SUGGESTION }o--|| IDENTITY_MAP : gera
  MERGE_SUGGESTION {
    int id
    string matched_key "telefone | documento"
    string payload
    string status "pending | approved | rejected"
  }
```

### Árvore de fonte (repo `inbox-flash-capital`)

Estado as-built em 2026-09-02, depois da Fase 1 (a marca diz o que **existe hoje**):

```text
inbox-flash-capital/
  compose.yaml               # [✔] a stack inteira: postgres, redis, chatwoot-{init,seed,web,sidekiq}
  .env                       # segredos — NUNCA versionado (AD-8)
  .env.example               # [✔] todas as chaves, valores vazios; simetria verificada nos 2 sentidos
  scripts/
    lib/env.sh               # [✔] env_get — lê UMA chave do .env sem dar `source` (segredo fora do ambiente)
    seed/chatwoot_seed.rb    # [✔] rails runner idempotente: 2 inboxes, 8 atributos, 7 labels, 5 respostas rápidas, marca
    init-db/                 # [1.2] cria usuário, banco e extensões da central (AD-9)
    backup.sh  restore.sh    # [1.4] backup do par banco+anexos; restore em ambiente limpo
    smoke-test.sh            # [1.1] semeia, reinicia e prova a persistência (dev; exige opt-in)
    verificar-invariantes.sh # [1.x] falha se AD-7/8/9/10 forem violados
    retencao-conversas.sh    # [6.3] expurgo LGPD de conversa resolvida antiga (cron: domingo 04:10)
    monitorar-canais.sh      # [6.3] 6 sinais de liveness; avisa no sino do Nexus (cron: de hora em hora)
    criar-agente.sh          # [6.1] põe alguém para atender; a senha nunca passa por argv nem env
    verificar-operacao.sh    # [6.x] papéis, labels, respostas rápidas, janela de 24h, crons
    conectar-twilio.sh       # [3.1] --status e --templates (a inbox já nasce do seed)
    conectar-gmail.sh        # [4.1] --status e --url (o consent do Google é clique humano)
    verificar-canal-oficial.sh  # [3.1] janela 24h, templates, AD-6, RELAY_TOKEN, nada fora da loopback
    verificar-canal-email.sh    # [4.1] provider, IMAP, refresh_token, job do Sidekiq, installation_configs
    backfill-email.sh        # [4.1] recupera e-mail perdido em janela de queda do poller
  docs/                      # product-brief, prd, architecture, epics + runbooks (inclui runbook-operacao e runbook-lgpd)
  .claude/                   # scaffold de dev: hooks, comandos, memories, skills
  CLAUDE.md  PROGRESS.md  README.md
```

> O espelho do canal oficial (STORY-3.2) **não mora aqui** — é código do `monorepo-flash-capital`
> (`api/integrations/chatwoot/chatwoot_mirror.py`), porque quem é dono do webhook do Twilio e do
> motor de disparo é o monorepo (AD-6). Estado: branch **`feat/espelho-chatwoot`** (`c3d5438`),
> **ainda não mergeada na `main` de lá** — até o merge+deploy, o espelho não roda em produção.

## Capability → Architecture Map

| Capability / Área | Lives in | Governed by |
| --- | --- | --- |
| Deploy/backup/versão (FR-1..3) | a raiz do repo + Chatwoot | AD-7, AD-8, AD-9 |
| WhatsApp Oficial (FR-7, FR-8) | Twilio → Chatwoot; monorepo push | AD-4, AD-6 |
| E-mail (FR-9, FR-10) | Gmail → Chatwoot | AD-4, AD-3 |
| ~~Enriquecimento (FR-11..14)~~ | **anulado** — `chatwoot_mirror.py` do monorepo carimba no disparo | **AD-13** |
| Janela de 24h (FR-7) | Chatwoot **nativo**, e só porque `medium: whatsapp` — a UI fecha o editor e oferece os templates. Sem defesa server-side: quem posta pela API checa antes | AD-7 |
| Acesso a documento (NFR privacidade) | por **inbox**, nunca por papel | **AD-14** |
| Operação (FR-15, FR-16) | Chatwoot nativo | AD-7 |

## Deferred

- **Dashboard App (iframe) com dado ao vivo:** adiada; MVP usa só atributos empurrados (AD-2 mantém a central leve).
- **Sync bidirecional (central → domínio):** adiada; MVP é unidirecional (AD-2).
- **Campanhas/disparo em massa na central:** adiada; permanece no monorepo (AD-6).
- **SSO / embed na plataforma interna:** adiada para fase 2.
- **Novos canais (Instagram, webchat, Telegram):** futuro; o paradigma de adapter (AD-4) já os acomoda.
