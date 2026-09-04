> ## ⛔ SUPERSEDED — 2026-09-02
>
> **Este ADR foi desconsiderado por decisão do Vitor.** O Chatwoot **permanece** como painel de
> acompanhamento dos disparos; não se constrói UI de chat no painel interno, e o corte do Chatwoot (D3)
> não acontece. O que vale é o **Anexo A — Trilha C**, hoje detalhado nos **AD-10..AD-15** de
> `docs/architecture.md` e, do lado do monorepo, em `monorepo-flash-capital/docs/ESPELHO-CHATWOOT.md`.
>
> ⚠️ **Não siga os ponteiros do corpo deste documento.** Ele foi escrito em 2026-09-02 e cita
> `inbox/PROGRESS.md` **por número de linha**; aquele arquivo foi reescrito várias vezes desde então e
> as âncoras apontam para conteúdo diferente. O mesmo vale para `HANDOFF-espelho-chatwoot.md`, citado
> na versão original desta nota: esse arquivo **nunca existiu com esse nome** em nenhum dos três repos.
> O que continua válido aqui é o **raciocínio e as medições**, não os endereços. Para o estado atual,
> vá ao `PROGRESS.md` §Dívida técnica e ao `docs/architecture.md`.
>
> **Arquivado aqui — não apagado — porque registra uma direção rejeitada com medição.** Se alguém
> repropuser "cortar o Chatwoot e trazer o atendimento para o monorepo" daqui a seis meses, este é o
> documento que evita refazer a análise do zero.
>
> **O que sobreviveu e foi extraído para onde é acionável:**
> | Do ADR-0014 | Foi para |
> |---|---|
> | D4 — Evolution removida | `crm/docs/07_Decisoes.md` **ADR-010** (executa o que o ADR-009 decidiu) |
> | §2 — o Twenty nunca chegou ao usuário (medição de 2026-08-21) | **ADR-010**, §"Por que o critério do ADR-005 nunca poderia ser cumprido" |
> | §2 — a circularidade do critério do ADR-005 | **ADR-010**, mesma seção |
> | Riscos — janela de 24h não modelada; inbound descartado sem persistir o corpo | `PROGRESS.md` §Dívida técnica deste repo |
> | §1 — o EPIC-5 é trabalho criado por si mesmo | **AD-13** de `docs/architecture.md` |
>
> **O número 0014 colide** com `monorepo-flash-capital/docs/decisions/0014-regua-config-marco-e-recompra.md`.
> Documento histórico; não renumerar, não citar como vigente.

# 0014 — Atendimento no monorepo: corte do Chatwoot, da Evolution e validação do Twenty

- Status: **Aceito — faseado, com gatilhos explícitos**
- Data: 2026-08-21
- Contexto de tier: L (atravessa os três repositórios; toca atendimento de cobrança em produção e PII de cliente)

## Contexto

O ecossistema tem três repositórios e três destinos de execução hoje:

| Repo | O que roda | Onde roda hoje |
|---|---|---|
| `monorepo-flash-capital` | api, worker, redis, frontend interno, website cliente, landing | Railway — ~$10/mês em 3-4 meses |
| `crm-flash-capital` | Twenty (server+worker), n8n, Evolution, lid/render/contract, Postgres, Redis, Caddy | máquina local, `docker compose up -d` |
| `inbox-flash-capital` | Chatwoot (web+sidekiq), Postgres, Redis, Caddy | máquina local + túnel ngrok — **com PII real de cliente desde 2026-07-14** |

A necessidade que abriu a discussão: **o número oficial (Twilio) não tem interface**. A régua dispara
cobrança por WhatsApp e o único jeito de acompanhar é a API da Twilio. O Chatwoot foi adotado como
essa interface (EPIC-3 do `inbox`, fechado e verificado ao vivo com o número real).

A pergunta original era de infraestrutura — dimensionar uma VPS para subir `crm` + `inbox` em produção.
A auditoria dos três repos mudou a pergunta.

## O problema

### 1. O Chatwoot cria o trabalho que ele deveria evitar

Por AD-1 do `inbox`, o Chatwoot é **espelho e cockpit, nunca fonte da verdade**. Consequência direta:
para a atendente ver contexto de domínio (CNPJ, dias de atraso, valor em aberto) é preciso construir o
**Serviço de Sync** — EPIC-5, 5 stories, "único componente construído do zero", TDD obrigatório —
cuja única função é reconciliar identidade entre Chatwoot ↔ Twenty ↔ Supabase e empurrar labels/atributos.

Dentro do painel interno esse contexto é gratuito: já se está no sistema dono do dado. **O EPIC-5 inteiro
é trabalho criado por ter posto o chat fora da fonte da verdade.**

### 2. O Twenty nunca chegou ao usuário

Verificado no banco vivo em 2026-08-21:

- **1 `workspaceMember`** — só a conta admin. João (comercial) e Guy (analista) **não têm conta**;
  a criação das roles segue como intervenção manual pendente (`crm/PROGRESS.md:193`).
- **12 leads, 0 convertidos** — "Teste Massa LTDA", "Fulano PF", MEI do Vitor ×4, 6 em branco.
- **4 `emailLog`**, todos para `vitor@flashcapital.com.br`.
- **Último login 2026-07-23**; em 30 dias só o cron de polling de 2 minutos executou.
- **0 de 36** checkboxes em `docs/Cheat_Sheet/go-live-e-smoke.md`.
- `contract-service` — container inteiro, 14 cláusulas, DOCX→PDF — **nunca executou**.

O critério de migração do ADR-005 do `crm` ("time comercial usou 2+ semanas sem bloqueios, ≥5 leads
end-to-end") **nunca foi avaliado**. O mesmo ADR-005, porém, registra a consequência "Local only — time
comercial não acessa até deploy": o critério é circular, e é isso que o trava.

### 3. A Evolution já está morta, mas ainda ligada

ADR-009 do `crm` pausou a perna WhatsApp da prospecção. Os seis workflows WF-04 estão inativos e **sem
nenhuma execução desde 2026-07-21**. Os containers `evolution-api` e `lid-service` seguem rodando à toa —
o item 5 do ADR-009 foi executado pela metade.

### 4. Produção de cobrança depende de túnel efêmero

O webhook de inbound da Twilio já apodreceu **duas vezes em silêncio** (a primeira custou 10 dias; na
segunda estava apontando para `demo.twilio.com`). Registrado como dívida reincidente em
`inbox/PROGRESS.md:350-351`, sem monitoramento.

## Opções avaliadas

### A) Tudo no Railway (um só lugar)
Exige decompor ~16 containers em serviços individuais. Custo medido por consumo real ($10/GB/mês de RAM),
e nada disso pode dormir (webhook/chat). Estimativa: **~$110-150/mês**. Rejeitada por custo e por
desmontar uma arquitetura compose que já funciona.

### B) Tudo em VPS (sair do Railway)
O monorepo é ativamente desenvolvido, dorme quando ocioso e custa ~$10/mês — o encaixe de PaaS é correto.
Migrar trocaria TLS, deploy por git push e rollback por trabalho operacional sem economia relevante.
Rejeitada.

### C) Manter o Chatwoot e construir o Sync (plano vigente)
Custo marginal do Chatwoot numa VPS de preço fixo é **R$20/mês** (diferença entre 8GB e 16GB) — barato.
Mas obriga a construir o EPIC-5 (5 stories, TDD) — que tem um pré-requisito fora do `inbox`: hoje
**nenhum dos dois sistemas de origem emite evento** — e a carregar armadilhas as-built documentadas
(ponte hífen→underscore no Caddy, guard de `source_id`, `refresh_token` do Gmail em texto puro no banco
e em todo backup). Rejeitada por esforço, não por custo.

**Não descartada — mantida como contingência com trilha mapeada e ponto de retorno definido.**
Ver o **Anexo A**, que também corrige duas armadilhas desta lista que deixam de existir com D4.

### D) Atendimento no monorepo + VPS só para Twenty/n8n — **escolhida**

## Decisão

Quatro decisões, cada uma com gatilho próprio.

### D1 — O atendimento passa a morar no monorepo `[decidido]`

A interface de acompanhamento e resposta do número oficial vira uma aba do painel interno, alimentada
pela API e pelo banco que já são fonte da verdade. **Escopo: apenas WhatsApp.** O e-mail permanece no
Gmail — ele já tem interface, e unificar dois canais numa tela agrega pouco para um time de três pessoas.

Isso é possível porque o encanamento já existe:

| Já pronto | Onde |
|---|---|
| Envio Twilio com captura de SID e retries | `api/integrations/whatsapp/twilio_whatsapp_service.py` |
| Webhook de inbound com assinatura validada | `api/routers/twilio_webhooks_router.py:74` |
| Delivery status (entregue/lido/falhou) com `error_code` | `api/routers/twilio_webhooks_router.py:57` |
| Tabela de mensagens append-only (corpo, canal, contato, SID, status) | `internal.comunicacao` |
| UI de histórico renderizando essas linhas por canal | `frontend/app/painel-controle/cobranca/regua-cobranca/components/ReguaCockpit.tsx:215` |
| Endpoint e repositório de timeline | `api/routers/regua_router.py:111`, `api/repositories/comunicacao_repo.py:105` |

### D2 — Faseamento em dois níveis, com costura por `titulo_id` `[decidido]`

O handler de inbound já resolve **telefone → disparo mais recente → título**, e o schema da régua v2 já
antecipa a resposta (`status = respondido`, coluna `respondido_em`). Isso define a costura:

**Nível 1 — resposta de cobrança (tem título).** Persistir o corpo do inbound como linha de
`internal.comunicacao` com coluna `direcao`, reusando o `titulo_id` que o handler já resolve.
`titulo_id` permanece `NOT NULL`. Completa o que o schema já prometia: `respondido` deixa de ser flag e
vira auditável. As respostas passam a aparecer no Sheet "Histórico" existente com trabalho mínimo de UI
(distinguir entrada de saída).

**Nível 2 — conversa (sem título).** Entidade de conversa, lista de conversas, campo de resposta, envio
livre não-template e modelagem da **janela de 24h do WhatsApp**. É aqui que `titulo_id` afrouxa.
Feature nova, branch própria.

> **O Nível 1 não substitui o Chatwoot** — dá visibilidade, não resposta. Só o Nível 2 fecha esse buraco.

### D3 — Corte do Chatwoot, condicionado `[gatilho]`

**Gatilho: o Nível 2 em produção, validado em uso real.** Só então: exportar o histórico de conversas
(as respostas dos clientes desde 2026-07-14 só existem lá), desligar a stack, arquivar
`inbox-flash-capital` e **cancelar formalmente o EPIC-5**. Até lá o Chatwoot continua rodando como está.

**Não executar no mesmo dia em que o Nível 2 sobe** — este é o ponto de não-retorno da decisão inteira.
Manter as duas trilhas em paralelo por algumas semanas custa R$20/mês e preserva a reversibilidade no
período em que ela mais vale. Ver **Anexo A.6**.

Os aprendizados as-built do `inbox` são preservados como ADR antes do arquivamento — não se joga fora
conhecimento pago com tempo.

### D4 — Evolution removida `[imediato]` · Twenty validado com prazo `[gatilho]`

**Evolution:** parar e remover do compose `evolution-api` e `lid-service`, o volume `evolution_instances`,
o banco `evolution_db` e o vhost `evolution.localhost`. Termina o item 5 do ADR-009. Nada não-WhatsApp
quebra: os nós vivos de notificação de documento e follow-up são só Resend. Morrem junto o bug de LID e
o erro 463.

**Twenty + n8n:** VPS de ~8GB dedicada, contratada explicitamente como **gasto de validação com data de
decisão marcada no dia da compra** — a própria mitigação que o ADR-005 sugeriu ("deploy temporário para
validação"). Deploy, criar as contas de João e Guy, rodar leads reais. **Gatilho de decisão: adoção
comprovada em até 2 meses** — senão, cancelar. A trilha é independente do atendimento e paraleliza bem:
consome tempo do time usando, não tempo de desenvolvimento.

Sem Chatwoot e sem Evolution restam **8 containers** (Twenty ×2, n8n, render, contract, Postgres, Redis,
Caddy), estimados em 4-5,5GB — folga confortável em 8GB.

## Ordem de execução

1. **Apontar o webhook de inbound da Twilio para a URL estável do Railway.** Maior valor, menor esforço,
   resolve a falha reincidente. Mudança de configuração, não de infraestrutura. **Antes de tudo.**
2. **Parar e remover a Evolution** (D4). Libera RAM local, não quebra nada.
3. **Fechar a régua v2 e levar `internal.comunicacao` para a `main`.** Não reabrir a v2 para caber o
   Nível 1 — se ela está fechando, feche; o Nível 1 entra como incremento pequeno em seguida. O que
   importa é a ordem, não a branch.
4. **Nível 1** — inbound persistido, visível no Histórico.
5. **Nível 2** — conversa, compositor, janela de 24h.
6. **Cutover do Chatwoot** (D3), com export prévio.

Em paralelo desde já: **VPS + Twenty + contas do time** (D4).

## Custo

| Item | Hoje | Alvo |
|---|---|---|
| Railway (monorepo) | ~$10/mês | ~$10-15/mês — a aba roda na api e no frontend existentes |
| VPS (Twenty + n8n) | R$0 | ~R$50/mês — validação com prazo |
| Chatwoot em VPS | — | R$0 (evitado; seria +R$20/mês) |
| Vercel Pro (landing) | — | $20/mês, opcional e sem pressa |

Provedor da VPS **em aberto**: Hostinger KVM2 (8GB/2vCPU, São Paulo, R$49,99) ou Hetzner CX32
(8GB/4vCPU, US West, ~$8) — Railway e Supabase já estão nos EUA, então proximidade com o Brasil não é
requisito hoje. **Confirmar prazo de compromisso e valor de renovação antes de contratar**: preço de
entrada com trava de 24 meses é incompatível com "gasto de validação".

O ganho principal nunca foi financeiro — é apagar um repositório, um épico inteiro e uma classe de falha
silenciosa.

## Riscos aceitos

- **Janela de 24h do WhatsApp.** Fora dela só template aprovado; resposta livre falha — e falha em
  silêncio, o modo que mais dói aqui. Não está modelada em nenhum ponto do código hoje. É requisito de
  aceite do Nível 2, não detalhe de implementação.
- **Subestimar a UI de chat.** Threading, anexos, paginação, estado de leitura, ordenação por última
  mensagem. É a maior parte do esforço do Nível 2.
- **Interim com o Chatwoot no arranjo atual** por mais 1-2 meses. O passo 1 protege a perna crítica
  (cobrança), mas o espelho monorepo→Chatwoot continua exigindo que o Railway alcance a máquina local.
  Mitigação parcial: depois do Nível 1 o espelho quebrado degrada (Chatwoot desatualizado) em vez de
  cegar (registro no banco próprio).
- **Perda de histórico** se o export do cutover falhar ou for esquecido.
- **Reconstruir um Chatwoot pior** se um dia houver necessidade real de helpdesk (múltiplos atendentes,
  atribuição, SLA, respostas rápidas). Mitigado por: a decisão é reversível (`docker compose up`), e o
  EPIC-6 — que usaria essas features — nunca foi construído; o que se usa hoje é a fatia fina.

## Fato vs. estimativa

**Verificado em código e banco:** os números do Twenty (D2 §2); Evolution pausada com 0 execuções desde
21/07; `contract-service` nunca executado; inbound recebido, classificado e **descartado** sem persistir
o corpo; `internal.comunicacao` ausente na `main` (existe só em `feat/regua-comunicacao-v2` e
`feat/espelho-chatwoot`); janela de 24h sem modelagem; Twenty ↔ Supabase sem integração e sem egresso de
rede (`twenty-server` só na rede `internal`, declarada `internal: true`).

**Estimativa/julgamento, não medição:** 2-3 semanas para o Nível 2; 4-5,5GB de consumo do stack restante;
que o time adotaria o Twenty se onboardado — **esse é justamente o desconhecido que D4 existe para
responder**; que o Gmail basta para atendimento por e-mail (decisão de produto, não técnica); que o
EPIC-5 se dissolve quase inteiro no painel — um resto de sincronização Twenty→Supabase pode sobreviver.

## Anexo A — Trilha C: concluir o Chatwoot (contingência viva)

A opção C não foi descartada, foi **preterida**. Este anexo existe para que trocar de trilha seja uma
decisão informada de algumas horas, não uma re-descoberta de semanas.

### A.1 — Quando pegar esta trilha

Qualquer um destes gatilhos torna C a escolha correta, e nenhum deles é hipotético demais para ignorar:

- **Necessidade real de helpdesk.** Mais de um atendente simultâneo, atribuição de conversa, respostas
  rápidas, status/SLA. É o EPIC-6, que no Chatwoot é **configuração** e no painel seria **construção**.
- **O Nível 2 travar.** Se a janela de 24h ou a UI de chat estourarem a estimativa de 2-3 semanas de
  forma relevante, o custo comparativo vira — o Chatwoot já resolve os dois nativamente.
- **E-mail precisar voltar para a tela única.** Se o Gmail se provar insuficiente para o atendimento,
  o canal já existe pronto e verificado ao vivo (STORY-4.1) — reconstruí-lo no painel é caro.
- **Crescimento do time de atendimento** além das três pessoas atuais.

### A.2 — Correção: D4 barateia a trilha C

Duas das armadilhas listadas contra C **são da Evolution, não do Chatwoot**, e morrem com D4 —
que acontece nas duas trilhas:

- **`SAFE_FETCH_ALLOW_PRIVATE_NETWORK=true`** existe porque o anti-SSRF do Chatwoot recusa host sem IP
  público e a Evolution vive em rede privada. Sem Evolution, o flag provavelmente volta ao default e o
  risco de SSRF registrado em `inbox/PROGRESS.md:347` some. *(Confirmar antes: verificar se algum caminho
  de download de mídia da Twilio depende dele — as URLs da Twilio são públicas, então não deveria.)*
- **Dedup por cron / "espelho pode duplicar"** — a duplicação vem do replay do Baileys, que é Evolution
  (`inbox/PROGRESS.md:346`). Sem ela, `dedup-mensagens.sh` deixa de ser obrigatório no cron.

Restam contra C: o `refresh_token` do Gmail em texto puro (exigiria fork, proibido por AD-7), a ponte
hífen→underscore no Caddy, a disciplina do guard de `source_id` — e o EPIC-5, que é o custo real.

### A.3 — O pré-requisito escondido do EPIC-5

`inbox/docs/epic-5-premissas.md` (2026-07-14) registra que **os dois sistemas de origem emitem zero
eventos hoje**: os webhooks de saída do Twenty v2.12 não disparam (bug de cache — por isso o `crm` usa
polling em `WF-01-001`) e o monorepo **não tem outbox**.

Ou seja: o EPIC-5 não é "5 stories no `inbox`". É 5 stories **precedidas de código novo nos outros dois
repositórios**. Qualquer estimativa que trate o EPIC-5 como trabalho isolado do `inbox` está errada —
foi essa descoberta que mais pesou na escolha de D.

### A.4 — Faseamento para concluir C

| Fase | O quê | Onde | Observação |
|---|---|---|---|
| **C0** | Deploy real: DNS de `inbox.<DOMAIN>`, `.env` de produção, admin em `/installation/onboarding`, SMTP transacional, VPS de 16GB | `inbox` + infra | é a lista de "Pendências de produção" de `inbox/PROGRESS.md:49-52`, nunca executada |
| **C1** | Dívida "antes do go-live": webhook da Twilio em URL estável **+ monitoramento**, cron de retenção LGPD, backup offsite automatizado, merge de `feat/espelho-chatwoot` na `main`, ambiente de staging (exigido pelo FR-2) | `inbox` + `monorepo` | **comum às duas trilhas** — o passo 1 da ordem de execução já cobre a parte crítica |
| **C2** | Emissão de eventos: padrão **outbox** no monorepo; validar se o polling do Twenty serve de fonte para o Sync | `monorepo` + `crm` | pré-requisito do C3 (ver A.3) |
| **C3** | **EPIC-5** — 5.1 identidade por telefone+documento · 5.2 merge automático vs. sugestão · 5.3 push de labels · 5.4 push de atributos · 5.5 degradação graciosa. TDD obrigatório. Desbloqueia a STORY-4.2 | `inbox` | banco próprio de identity-map (+1 database) |
| **C4** | **EPIC-6** — 6.1 cockpit e papéis · 6.2 atribuição/labels/respostas rápidas · 6.3 observabilidade e LGPD | `inbox` | maior parte é configuração, não código |

Escopo que **sai** da trilha em qualquer cenário: EPIC-2 (stories 2.1/2.2), que morre com D4. De 19
stories, 8 estão feitas, 2 são removidas do escopo, e restam **9 mais C0-C2**.

### A.5 — Custo da trilha C

- **VPS:** 16GB em vez de 8GB (Chatwoot ~4GB + Twenty ~4GB + n8n ~2GB + Sync + 2 Postgres + 2 Redis +
  Caddy ≈ 11-13GB). Na Hostinger, KVM4 a R$69,99 contra KVM2 a R$49,99 — **+R$20/mês**.
- **Um serviço a mais para operar** (o Sync) com seu próprio banco.
- **Três repositórios permanentes** em vez de dois.
- O que C **compra** e D não: multi-atendente, atribuição, respostas rápidas, status de conversa, app
  mobile, e-mail unificado, janela de 24h tratada nativamente — e **zero UI de chat para construir**.

### A.6 — Ponto de retorno

Trocar D por C é barato **enquanto o Chatwoot estiver de pé**. O ponto de não-retorno é o **cutover da
D3** (export do histórico, desligamento da stack, arquivamento do repo): depois dele, voltar significa
redeploy e perda do histórico de conversas não exportado.

Isso dá uma janela concreta: **até a D3 ser executada, C continua a um `docker compose up` de distância.**
Regra prática — não executar a D3 no mesmo dia em que o Nível 2 entra em produção. Rodar as duas em
paralelo por algumas semanas custa R$20/mês e preserva a reversibilidade justamente no período em que
ela vale mais.

## Referências

- Encanamento reusável: `api/routers/twilio_webhooks_router.py`, `api/services/regua/dispatch_gateway.py`,
  `api/repositories/comunicacao_repo.py`,
  `frontend/app/painel-controle/cobranca/regua-cobranca/components/ReguaCockpit.tsx`.
- Migration da tabela de mensagens: `supabase/migrations/20260721100500_regua_comunicacao.sql`.
- Espelho atual (a remover no cutover): `api/integrations/chatwoot/chatwoot_mirror.py`, `docs/ESPELHO-CHATWOOT.md`.
- ADRs relacionados: `0002-multi-domain-architecture.md` (domínios), `0008-confirmacao-sacado-tracking.md`
  (rastreio de disparo), `0013-f5b-deprecar-dispatch-manual-comissarias.md` (régua v2).
- Repos irmãos: `crm-flash-capital/docs/07_Decisoes.md` (ADR-005 deploy, ADR-009 pausa da Evolution);
  `inbox-flash-capital/docs/architecture.md` (AD-1 espelho, AD-9 isolamento de banco), `inbox/PROGRESS.md`
  (dívidas as-built, EPIC-5).
- Trilha C: `inbox-flash-capital/docs/epic-5-premissas.md` (emissão de eventos — pré-requisito do EPIC-5),
  `inbox/PROGRESS.md:49-52` (pendências de produção nunca executadas) e `:343-358` (tabela de dívida técnica).
