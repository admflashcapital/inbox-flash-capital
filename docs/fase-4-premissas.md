# Fase 4 — a fronteira pública. Premissas e rastreio

> **Isto não é plano de execução, é previsão.** Nada aqui vira código antes de a diretoria decidir o
> domínio. O objetivo é que, no dia em que a decisão sair, ninguém precise redescobrir o que já foi
> medido — e que a lista de trabalho já esteja escrita, com dono e dependência.
>
> **Status:** ⬜ não iniciada · **os dois eixos já foram decididos** (§1) · falta comprar o domínio e
> conferir os seis limites da Cloudflare
> **Irmãos:** `docs/runbook-cloudflare.md` (o passo a passo, para executar quando o domínio chegar) ·
> `docs/plano-resiliencia.md` (a queda como certa)
> **Fontes:** `docs/runbook-deploy.md` §Antes de expor · `docs/architecture.md` AD-8/10/11/11.1/12 ·
> `PROGRESS.md` §Dívida técnica · `deploy/ngrok-policy.yml` · `scripts/tuneis-manha.sh` (monorepo)

---

## 1. O que a Fase 4 é, e o que ela não é

A Fase 4 tem **dois eixos independentes**, e confundi-los foi o erro que travou a decisão por semanas:

| Eixo | Pergunta | Quem decide | Estado |
|---|---|---|---|
| **Onde executar** | a central roda na máquina de expediente, numa VPS ou numa PaaS? | Vitor | ✅ **decidido 2026-09-03**: máquina do escritório, ligada 24h; VPS num segundo momento |
| **Como acessar** | por qual nome, com qual borda, com qual controle de acesso? | diretoria (domínio) | ✅ **domínio aprovado**; compra e configuração pendentes |

### As decisões tomadas em 2026-09-03

1. **Domínio novo aprovado**, a ser comprado pela GoDaddy, com os NS **daquele domínio** apontados para
   a Cloudflare. `flashcapital.com.br` não é tocado.
2. **Execução na máquina do escritório**, 24h ligada. VPS fica como evolução, não como pré-requisito —
   a decisão é reversível porque o `cloudflared` mora no compose e a stack é portável (AD-10).
3. **PaaS descartada** (Railway e Fly) **para a central**: a base de configuração vive nos scripts
   Docker, e perdê-los não se paga. Custo de descartar: zero, e reversível.
4. **Cloudflare no plano gratuito**, com os seis limites conferidos **antes** de qualquer execução —
   ver `docs/runbook-cloudflare.md`.

> ⚠️ A decisão 2 vale para a **central**. O **monorepo já está no Railway** — ver §2.1, que é a mudança
> de topologia mais consequente deste doc.

**O que o domínio não resolve:** disponibilidade. Uma máquina de escritório cai por energia, internet e
reboot do Windows. Isso não é objeção à decisão — é o escopo de `docs/plano-resiliencia.md`, que trata
a queda como certa e reduz o custo dela.

---

## 2. O que o domínio novo destrava (e por que é mais do que parece)

Todo o impasse anterior existia por uma restrição só: **os NS de `flashcapital.com.br` não podem ser
migrados** — a zona serve o site institucional e, por ADR-0002 do monorepo, também `www.`, `app.` e
`internal.` no Railway. E o Cloudflare Tunnel exige o hostname numa zona Cloudflare, sendo a delegação
de NS **exclusiva**: não coexiste com a GoDaddy. Isso produziu sete caminhos, seis deles ruins:

| Caminho | Custo | Por que caiu |
|---|---|---|
| A) migrar os NS de `flashcapital.com.br` | R$ 0 | rejeitado: mexe na zona do site institucional |
| B) 2º domínio + Cloudflare for SaaS | ~US$ 10/ano | válido, mas complexidade sem ganho sobre o C |
| **C) 2º domínio direto na Cloudflare** | **~US$ 10/ano** | **era barrado só por "não comprar domínio"** |
| D) Partial Setup (CNAME) | **US$ 200/mês** (Business) | preço proibitivo |
| E) VPS + proxy próprio | ~R$ 70/mês | reintroduz o proxy compartilhado que o AD-10 cortou |
| F) Subdomain Setup (zona filha) | Enterprise | descartado: recurso não existe abaixo de Enterprise |
| G) Tunnel + hostname **privado** (Cloudflare One) | R$ 0 | ótimo para a equipe; não cobre a perna server-to-server |

**Com o domínio aprovado, o caminho C fica trivial e sem risco:** zona nova, vazia, criada direto na
Cloudflare. Nada é migrado, a GoDaddy não é tocada, e não há janela de propagação a temer porque não
existe tráfego legado naquele nome. É a diferença entre "mudar o DNS da empresa" e "criar um DNS novo".

**E o ganho passa dos três repos.** O `tuneis-manha.sh` mantém hoje **quatro** URLs efêmeras vivas:

| Túnel | Serve | Consome a URL | Na Fase 4 |
|---|---|---|---|
| `:8001` | FastAPI do monorepo — webhook da Twilio + boleto público | `PUBLIC_BOLETO_BASE_URL` | **Railway**, `api.flashcapital.com.br` (CNAME na zona antiga) |
| `:54321` | mídia do Supabase (a Twilio busca o PDF) | `SUPABASE_PUBLIC_URL` | ✅ **some.** O Supabase é hospedado (`supabase.co`) e já em produção: a URL de storage nasce pública e estável. O túnel é artefato de **dev** |
| `:3001` | a central (Chatwoot) | `CENTRAL_URL_PUBLICA` | túnel → `inbox.<novodominio>` |
| `:5678` | n8n do CRM — webhooks Resend/JotForm | `WEBHOOK_URL` | túnel → `n8n.<novodominio>` |

**Uma delas não é opcional:** o n8n atende Resend e JotForm, que são máquinas de terceiros e **exigem
URL estável** — o ngrok é dev-only por decisão, então a Fase 4 é obrigatória para o CRM.

---

## 2.1 Topologia — a plataforma NÃO fica na mesma máquina `[DECIDIDO 2026-09-03]`

> ⚠️ **Isto é o ALVO, não o estado atual.** Medido na API da Twilio (2026-09-03, reconfirmado em
> 2026-09-04): o número de produção `+553123916846` tem inbound **e** status callback apontando para um
> túnel ngrok da máquina do escritório. O monorepo **tem deploy no Railway** — provado: o
> `api.flashcapital.com.br` é CNAME para `bps2k9e9.up.railway.app`, responde e envia de lá — mas a
> **fronteira pública de volta ainda não foi movida**. Enquanto não for, uma queda do escritório derruba
> a confirmação de sacado, o link do boleto e a mídia — não só o painel.
>
> Mover essa fronteira é o item **B0** do `docs/plano-resiliencia.md`, **não depende do domínio novo** e
> vem antes de tudo o mais.

O alvo: o monorepo no **Railway**; inbox e CRM na máquina do escritório. São dois lugares, e isso muda
mais do que parece:

```
   Supabase Cloud          Railway (24/7)                escritório (24h, mas cai)
  ┌──────────────┐   ┌───────────────────────┐     ┌──────────────────────────────┐
  │ banco + mídia│◀──│  FastAPI + worker     │     │  Chatwoot   :3001            │
  │ *.supabase.co│   │  api.flashcapital…    │─────┼─▶ inbox.<novodominio>        │
  └──────────────┘   └───────────▲───────────┘     │  n8n        :5678            │
   (URL já pública)              │      ESPELHO    │  n8n.<novodominio>           │
                          Twilio, Resend (internet)└──────────────────────────────┘
```

São **três** lugares, não dois. O Supabase é hospedado e já está em produção; o Railway fala com ele
por connection string. Consequência prática: a mídia que a Twilio busca **já tem URL pública e
estável** — o túnel `:54321` era artefato de dev e simplesmente deixa de existir.

⚠️ **LGPD:** com isso o dado do titular passa a viver em três lugares com janelas de retenção
diferentes — Supabase Cloud (backup gerenciado, janela **não medida**), Railway (compute, sem dado em
repouso) e a máquina do escritório (conversas, anexos e os backups 7+4 do `backup.sh`). O procedimento
de exclusão do `runbook-lgpd.md` continua correto ao dizer que o pedido atinge **os dois lados**; o que
falta é medir a janela de backup do Supabase, porque o aviso "restore ressuscita o dado" agora vale
para duas janelas e só uma está documentada.

**Duas zonas de DNS, de propósito:** `api.` fica em `flashcapital.com.br` (CNAME para o Railway, sem
mexer em NS) e `inbox.`/`n8n.` ficam no domínio novo, na Cloudflare. Não é inconsistência: o Cloudflare
Tunnel exige que o hostname esteja **numa zona Cloudflare** (o CNAME aponta para
`<UUID>.cfargotunnel.com`, que só resolve lá dentro). O Railway não precisa disso — aceita CNAME de
qualquer zona. Por isso `api.` pode continuar na zona antiga e `inbox.` não pode.

### O que a separação quebra

1. **`CHATWOOT_URL=http://chatwoot-web:3000` morre.** É nome de container na rede privada
   `flash-espelho`, que passa a ter um membro só. O espelho vai ter de falar
   `https://inbox.<novodominio>` — **pela internet pública**.
2. **A regra do AD-10 ("a via máquina-a-máquina é sempre rede privada") deixa de valer para essa
   perna.** Isso é mudança de arquitetura, não detalhe de configuração: precisa de ADR, não de um
   `sed` no `.env`.
3. **O Block incondicional do `/twilio/callback` passa a estar ERRADO.** A justificativa era: *"o
   inbound legítimo não passa por aqui — chega ao monorepo e é relayado container-a-container, sem
   tocar no túnel"*. Com o monorepo no Railway, **o relay é justamente tráfego de fora**. Negar o path
   na borda mataria o espelho do inbound. A regra vira *negar **exceto** com `X-Relay-Token` válido*.
4. **O `RELAY_TOKEN` vira a única proteção real** desse path, e passa a ser **obrigatório na borda** —
   já estava registrado como "pré-condição bloqueante de qualquer ingresso futuro". Venceu.
5. **O Access não pode barrar o espelho.** Ele é máquina, não navegador. Isso promove o item
   *Service Auth* da checklist da Cloudflare de "importante" a **load-bearing**: sem ele, não é só o
   `delivery_status` que quebra — é o espelho inteiro.

### O que a separação melhora — e é bastante

6. **O caminho crítico do negócio deixa de depender do escritório.** A Twilio entrega no Railway, que
   fica de pé: a confirmação de sacado, a régua e a fila sobrevivem a qualquer queda daqui. Cai só o
   **painel**.
7. **A perda vira de mão única, com o remetente vivo.** Quem falha em entregar (o monorepo) continua
   rodando e **pode guardar o que não conseguiu entregar**. É o que torna a fila de reenvio barata — e
   é a diferença entre "buraco permanente" e "atraso". Ver `docs/plano-resiliencia.md` §F1.

⚠️ **Ordem obrigatória:** a asserção anti-"login HTML 200" (`plano-resiliencia.md` §F3) entra **antes**
de o Access ir para a frente da central. Se inverter, o espelho passa a mentir que entregou — e a
falha é silenciosa.

---

## 3. A medição que define a arquitetura

Nenhum terceiro entrega **mensagem** no Chatwoot: a Twilio fala com o **monorepo**, que valida a
assinatura; o e-mail entra por **polling IMAP de saída**. Mas **duas máquinas precisam alcançá-lo**, e
isso descarta o caminho de hostname privado + WARP (bom: ninguém precisa instalar cliente):

- a **Twilio**, em `/twilio/delivery_status` — para as mensagens que a *própria central* envia. Sem
  isso ela recusa o envio com **21609** e a atendente não responde pelo WhatsApp;
- o **espelho do monorepo**, em `/twilio/callback` e na API — que agora vem do Railway, pela internet.

| Serviço | Quem precisa alcançar | Fronteira | Controle |
|---|---|---|---|
| n8n (CRM) | Resend, JotForm | **pública** | restrita a `^/webhook(-test)?/` + catch-all **403** |
| API (Railway) | Twilio (assinada), cliente baixando boleto | **pública** | assinatura Twilio; `/b/…` público por natureza |
| **Chatwoot** | equipe (navegador) **+ Twilio + espelho** (máquinas) | **pública, com portão** | Access para humano · Service Auth para máquina · WAF no `/twilio/callback` |
| Twenty (CRM) | só a equipe | **privada** | Access |

**O AD-11 sobrevive:** a central continua não sendo *site* público — ganha nome estável e portão de
identidade, não porta aberta. O que mudou é que o portão precisa saber deixar **máquina** passar.

---

## 4. A especificação que o ingresso tem de satisfazer

Já escrita e verificada em `docs/runbook-deploy.md` §Antes de expor. Resumo do que muda de estado:

| # | Requisito | Hoje (ngrok) | Fase 4 |
|---|---|---|---|
| 1 | ~~negar `/twilio/callback` de fora~~ → **só o espelho passa** | ✅ 403 incondicional (o relay era interno) | Access **Service Auth**, não WAF — **mudou por causa do §2.1**. Token do relay no WAF seria uma 4ª cópia do segredo |
| 2 | `/twilio/delivery_status` alcançável | ✅ aberto | **Bypass/Service Auth avaliado ANTES de Allow/Block** + allowlist dos IPs da Twilio |
| 3 | headers de segurança | ✅ `add-headers` | Transform Rules |
| 4 | teto de tamanho de corpo | ❌ **não coberto** | primeira vez que fica coberto |
| 5 | auth e anti-força-bruta | ✅ nativo do Chatwoot (Rack::Attack, 6ª tentativa → 429) | some do escopo: o Access passa a barrar antes |

**As duas armadilhas já registradas, que só aparecem na hora de ligar:**

1. **Access mal configurado devolve a página de login em HTML com status 200.** O `raise_for_status()`
   do espelho **passa**, e ele conclui que deu certo. Como o espelho não tem retry nem backfill
   (AD-12), isso vira buraco permanente no painel, em silêncio. Se a central for para trás do Access,
   o espelho precisa de asserção de `content-type` ou de header `cf-access-*` — **antes** de ligar.
2. **A perna de máquina precisa de política própria.** `/twilio/delivery_status` não tem identidade
   humana; exigir login ali quebra a chamada da Twilio e traz o **21609** de volta — a atendente para
   de responder pelo WhatsApp.

---

## 5. As dívidas que a Fase 4 paga

Todas já rastreadas em `PROGRESS.md`. Aqui só o mapa de quais caem e quais não.

| Dívida | Cai com o domínio? |
|---|---|
| `link_boleto` guarda URL de túnel que morre amanhã → 404 em conversa antiga | ✅ sim, é o conserto exato |
| Webhook da Twilio apodrece (hoje só mitigado pelo `tuneis-manha.sh`) | ✅ sim |
| n8n: editor alcançável pela URL efêmera | ✅ sim, com a restrição de path na borda |
| `/twilio/delivery_status` aceita chamada não assinada | 🟡 mitigado por allowlist de IP, não eliminado |
| Teto de corpo (requisito 4) | ✅ passa a existir |
| **Cron que pode nunca disparar** | ❌ não pelo domínio → **`plano-resiliencia.md` §R1** (autostart do WSL2) |
| **AD-12: espelho perde e não recupera** | ❌ não pelo domínio → **`plano-resiliencia.md` §F1** (fila de reenvio) |
| **Painel amostral (AD-12/README)** | ❌ não pelo domínio → cai junto com o F1 |

**Leia a metade de baixo com atenção.** As três dívidas mais caras não são de rede — são de
**disponibilidade**, e um domínio apontando para uma máquina desligada não conserta nenhuma delas.
Elas têm plano próprio, e a boa notícia é que **nenhuma das três depende do domínio**: podem começar
hoje.

---

## 6. Rastreio do trabalho — o que fazer quando a decisão sair

Ordem por dependência, não por dificuldade. Nada disto está iniciado.

### Bloco 0 — pré-condições
| # | Item | Dono | Pronto quando |
|---|---|---|---|
| 0.1 | 🟡 domínio **aprovado** — falta comprar | Vitor | comprado, e `.com` × `.com.br` decidido (muda o processo: `.com.br` troca NS pelo Registro.br) |
| 0.2 | ✅ decisão *onde executar* | Vitor | máquina do escritório 24h; VPS depois |
| 0.3 | ⬜ **conferir os 6 limites do plano gratuito** — `docs/runbook-cloudflare.md` §Passo 1 | Vitor | os seis números anotados. **O item *Service Auth* pode invalidar o plano free** |
| 0.4 | ⬜ Fase 3.5 — o que resta: pico de disparo, CPU média e crescimento do volume. O **idle já foi medido** (Chatwoot ~896 MiB · CRM ~1546 MiB, host de 7,8 GB), mas **só nas anotações da sessão de 2026-09-02**, não neste repo — reconfirmar com `docker stats` antes de citar como número | Vitor | vira janela de observação, não projeto — a decisão de onde executar já saiu |

### Bloco 1 — a borda
| # | Item | Repo | Depende de |
|---|---|---|---|
| 1.1 | ⬜ zona nova na Cloudflare, GoDaddy intacta | — | 0.1 |
| 1.2 | ⬜ instalar o `cloudflared` na máquina e mapear `inbox.` e `n8n.` | inbox + crm | 1.1 |
| 1.3 | ⬜ traduzir `deploy/ngrok-policy.yml` em Custom Rules + Transform Rules (a sintaxe morre, **as regras vão**) | inbox | 1.1 |
| 1.4 | ⬜ **`/twilio/delivery_status` → Bypass** (a Twilio **não** manda header: Service Auth ali devolve 403 e traz o 21609 de volta) | inbox | 0.3, 1.3 |
| 1.5 | ⬜ **`/twilio/callback` e `/api/*` → Service Auth** para o espelho — o outbound passa por `/api/v1/...`, não só pelo callback | inbox | 0.3, 1.3 |
| 1.6 | ⬜ teto de tamanho de corpo (requisito 4, nunca coberto) | inbox | 1.3 |
| 1.7 | ⬜ restrição de path do n8n: `^/webhook(-test)?/` + catch-all 403 | crm | 1.1 |

### Bloco 2 — o que consome as URLs
| # | Item | Repo | Nota |
|---|---|---|---|
| 2.1 | ⬜ `CENTRAL_URL_PUBLICA` → `inbox.<novodominio>` | inbox | vira `FRONTEND_URL` do Chatwoot |
| 2.2 | ⬜ **`CHATWOOT_URL` deixa de ser `http://chatwoot-web:3000`** e passa a `https://inbox.<novodominio>` | monorepo | consequência do §2.1. A rede `flash-espelho` fica com um membro e perde a razão de existir |
| 2.3 | ⬜ **ADR: o espelho atravessa a internet.** O AD-10 diz "máquina-a-máquina é sempre rede privada" — deixa de valer para essa perna | inbox | é mudança de arquitetura, não de `.env` |
| 2.4 | ⬜ `PUBLIC_BOLETO_BASE_URL` → `api.flashcapital.com.br` (CNAME para o Railway na zona antiga) | monorepo | **as três cópias** (env, DNS, console Twilio) têm de bater. Não depende do domínio novo |
| 2.5 | ⬜ conferir que `SUPABASE_PUBLIC_URL` está **ausente** (ou igual a `SUPABASE_URL`) no Railway | monorepo | com Supabase Cloud o `make_public_url` tem de virar no-op. Herdar o valor de dev reescreveria a URL da mídia para um `localhost:54321` — e a Twilio devolveria **63019** |
| 2.6 | ⬜ `WEBHOOK_URL` do n8n → `n8n.<novodominio>` | crm | reconfigurar Resend e JotForm |
| 2.7 | ⬜ **redirect URI do Google** no Cloud Console → domínio novo | inbox | destrava o consent permanente do Gmail (hoje é dança diária) |
| 2.8 | ⬜ aposentar o `tuneis-manha.sh` do fluxo de produção (fica como ferramenta de dev) | monorepo | depois de 2.1–2.6 |

### Bloco 3 — o que só aparece ao ligar
| # | Item | Repo | Nota |
|---|---|---|---|
| 3.1 | ⬜ asserção anti-"login HTML 200" no espelho | monorepo | **bloqueante**: entra ANTES de o Access ir para a frente da central. Detalhe em `plano-resiliencia.md` §F3 |
| 3.2 | ⬜ notificação de **Tunnel Health** da Cloudflare | — | o único vigia que vem de fora — `plano-resiliencia.md` §V1 |
| 3.3 | ⬜ revisar o horário dos 4 crons para a janela do host definitivo | inbox | o `04:10` foi escolhido para uma máquina de expediente |
| 3.4 | ⬜ rotacionar o `CENTRAL_ACCESS_TOKEN` para a conta de máquina | inbox + monorepo | dívida aberta; o deploy novo é a hora natural |
| 3.5 | ⬜ reavaliar o teto do AD-12 e o texto "painel amostral" do README | inbox | depende da **fila de reenvio** (`plano-resiliencia.md` §F1), não do domínio |
| 3.6 | ⬜ **asserção do caminho POSITIVO** no `verificar-canal-oficial.sh` | inbox | hoje ele só prova que `/twilio/callback` **sem** header dá 403 (`:151-155`). Com a regra condicional, um token errado na Cloudflare mantém o 403, o verificador segue verde e **todo relay morre em silêncio** |
| 3.7 | ⬜ atualizar `runbook-deploy.md` §Antes de expor: o título ainda diz "ainda não decidida" e o requisito 1 ainda é "negar de fora", incondicional | inbox | é a seção que este doc cita como fonte verificada |
| 3.8 | ⬜ apurar a **janela de backup do Supabase** e registrar em `runbook-lgpd.md` | monorepo | o aviso "restore ressuscita o dado" vale para duas janelas e só a do Chatwoot está medida |

---

## 7. O que levar para a diretoria

Três números e uma frase, não um pedido técnico:

1. **Custo:** ~US$ 10/ano de domínio. A Cloudflare (zona, Tunnel, Access até 50 usuários) é gratuita —
   **a confirmar no dia**, porque limite de fornecedor muda.
2. **O que se compra com isso:** o fim de quatro URLs que mudam todo dia e que hoje exigem um ritual
   manual toda manhã; o consent do Gmail deixa de ser dança; e o **CRM ganha a URL estável de que
   Resend e JotForm dependem** — hoje ele não tem caminho de produção.
3. **Os nameservers de `flashcapital.com.br` não são migrados.** A zona nova é dela mesma; a antiga
   continua na GoDaddy, servindo o site. O que ela recebe é **um CNAME a mais** (`api.`), do mesmo tipo
   que já servem `www.`, `app.` e `internal.` no Railway (ADR-0002 do monorepo). Não é "não tocar" —
   é "não migrar", que é o risco que importa.
4. **A frase:** o domínio resolve *como se chega* na plataforma. *Onde ela roda* continua em aberto, e
   é essa segunda decisão que determina se o painel de cobrança deixa de ser amostral.

---

## 8. Premissas que podem estar erradas

Registradas para serem conferidas, não para serem confiadas:

- **[A CONFERIR]** limites do plano gratuito da Cloudflare (regras, usuários do Access) — a doc do
  fornecedor muda, e o `runbook-deploy.md` já manda conferir na hora.
- **[A CONFERIR]** se o caminho de hostname **privado** (G) for escolhido, cada atendente precisa do
  cliente WARP instalado. É custo operacional real, e não foi dimensionado com ninguém.
- **[A MEDIR]** o benchmark de 24h nunca rodou. O que existe é **RAM idle**; pico de disparo, CPU
  média e crescimento do volume do Postgres continuam desconhecidos.
- **[NÃO MEDIDO]** o `DOCKER_HOST=ssh://` do `runbook-deploy.md` foi documentado sem VPS para testar.
  Se falhar, os scripts de setup voltam a exigir shell na máquina de produção.
