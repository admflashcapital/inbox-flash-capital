---
stepsCompleted: [step-01, step-02, step-03, step-04]
inputDocuments: [docs/product-brief.md, docs/prd.md, docs/architecture.md]
title: Inbox Flash Capital — Epic Breakdown
created: 2026-07-13
updated: 2026-07-13
phase: 3-solutioning
skill: bmad-create-epics-and-stories
---

# Inbox Flash Capital - Epic Breakdown

> ### ⚠️ REESCOPO — 2026-09-02
>
> **EPIC-2 (Evolution) e EPIC-5 (Sync) cancelados** — o escopo cai de 19 para **16 stories**. A **STORY-4.2 está destravada** pelo AD-13 (não espera mais o Sync). O detalhamento das stories canceladas fica abaixo só para leitura do histórico.
>
> Ver **AD-10..AD-13** em `inbox/docs/architecture.md`, **ADR-010** em `crm/docs/07_Decisoes.md`, e o `HANDOFF-espelho-chatwoot.md`.


## Overview

Decomposição completa em epics e stories a partir do [PRD](./prd.md) e da [Architecture](./architecture.md). Cada story referencia os FRs que realiza e traz critérios de aceite testáveis. A ordem de execução respeita as dependências: a Fundação (Epic 1) habilita os canais (Epics 2–4); o Serviço de Sync (Epic 5) depende de ao menos um canal vivo; a Operação & Governança (Epic 6) fecha o MVP.

## Requirements Inventory

### Functional Requirements
- **FR-1** Deploy self-hosted reproduzível · **FR-2** Versão fixada e upgrade controlado · **FR-3** Backup e retenção
- **FR-4** Inbox de prospecção espelhada · **FR-5** Convivência com Agente N8N (dois consumidores) · **FR-6** Aquecimento/proteção do número
- **FR-7** Inbox oficial espelhada · **FR-8** Espelho dos disparos em massa
- **FR-9** Inbox de e-mail espelhada · **FR-10** Unificação sob o mesmo contato
- **FR-11** Resolução de identidade · **FR-12** Push de labels · **FR-13** Push de atributos · **FR-14** Direção de fluxo/desacoplamento
- **FR-15** Cockpit unificado e papéis · **FR-16** Atribuição, labels e respostas rápidas

### NonFunctional Requirements
- Desacoplamento (sem chamada síncrona central→domínio) · Segurança (segredos, TLS, assinatura de webhook) · Privacidade/LGPD (retenção, acesso) · Observabilidade (logs, healthcheck, alerta de conexão) · Confiabilidade (entrega tolerante a falha; fan-out sem perda).

### Additional Requirements
- Chatwoot Community Edition (MIT), sem fork (AD-7) · Banco da central isolado (AD-9) · Guardrail de reputação de número (prospecção só inbound).

### UX Design Requirements
- Sem telas novas: UI é a do Chatwoot. UX = configuração de inboxes, labels, papéis e barra lateral de atributos.

### FR Coverage Map

| FR | Epic.Story |
| --- | --- |
| FR-1 | 1.1, 1.2 |
| FR-2 | 1.3 |
| FR-3 | 1.4 |
| FR-4 | 2.1 |
| FR-5 | 2.2 |
| FR-6 | 2.3 |
| FR-7 | 3.1 |
| FR-8 | 3.2 |
| FR-9 | 4.1 |
| FR-10 | 4.2, 5.2 |
| FR-11 | 5.1, 5.2 |
| FR-12 | 5.3 |
| FR-13 | 5.4 |
| FR-14 | 5.5 |
| FR-15 | 6.1 |
| FR-16 | 6.2 |

## Epic List

1. **Fundação da Plataforma** — Chatwoot self-hosted na infra da Flash (deploy, versão, backup). *(MVP)*
2. **Canal WhatsApp Prospecção (Evolution)** — número novo, inbound, convivendo com N8N. *(MVP)*
3. **Canal WhatsApp Oficial (Twilio/Meta)** — cobrança/transacional + espelho de disparos. *(MVP)*
4. **Canal E-mail (Gmail)** — thread de e-mail como conversa unificada. *(MVP)*
5. **Serviço de Sync — Enriquecimento de Contato** — identidade + labels + atributos. *(MVP)*
6. **Operação de Atendimento & Governança** — cockpit, papéis, labels, LGPD, observabilidade. *(MVP)*

---

## Epic 1: Fundação da Plataforma

Subir a instância Chatwoot self-hosted, reproduzível e segura, como base de todas as inboxes — versão fixada, isolada dos bancos de domínio e com backup/restore validado.

### Story 1.1: Stack Docker da central sobe com um comando

As a operação de tecnologia,
I want subir toda a stack da central com `docker compose up`,
So that a plataforma esteja disponível sem passos manuais frágeis.

**Acceptance Criteria:**

**Given** o repositório `inbox-flash-capital` com `deploy/docker-compose.yml` e `.env` preenchido
**When** executo `docker compose up`
**Then** sobem os serviços web, Sidekiq, Postgres (com pgvector), Redis e Caddy
**And** a UI do Chatwoot responde em HTTPS num domínio da Flash com certificado válido.

**Given** a stack no ar
**When** reinicio os containers
**Then** conversas, contatos e configurações persistem (dados em volume/DB).

### Story 1.2: Banco da central isolado dos bancos de domínio

As a arquiteto,
I want o Postgres da central separado de Twenty e Supabase,
So that não haja acoplamento de dados nem blast-radius entre sistemas.

**Acceptance Criteria:**

**Given** a stack da central
**When** inspeciono a configuração de banco
**Then** o Chatwoot usa uma instância Postgres própria
**And** não há credencial nem conexão cruzada com os bancos do CRM ou do monorepo (AD-9).

### Story 1.3: Versão fixada e procedimento de upgrade

As a tecnologia,
I want a imagem do Chatwoot fixada por tag e um upgrade documentado,
So that eu atualize sob demanda sem virar refém do upstream.

**Acceptance Criteria:**

**Given** o `docker-compose.yml`
**When** leio a referência da imagem Chatwoot
**Then** ela usa uma tag de versão explícita, nunca `latest`.

**Given** uma nova versão desejada
**When** sigo o runbook de upgrade
**Then** o processo (bump da tag + migrações) é executado em staging antes de produção
**And** está documentado em `docs/` ou `deploy/`.

### Story 1.4: Backup e restore validados

As a operação,
I want backup automatizado e restore testado,
So that eu recupere a central após uma falha, em conformidade com LGPD.

**Acceptance Criteria:**

**Given** a central em produção
**When** o job de backup roda
**Then** banco do Chatwoot e storage de anexos são copiados na periodicidade definida.

**Given** um backup existente
**When** executo o restore num ambiente limpo
**Then** conversas e anexos são recompostos integralmente
**And** a política de retenção de conversas está configurada.

---

## Epic 2: Canal WhatsApp Prospecção (Evolution)

Conectar o número novo (pré-pago) como inbox de prospecção via Evolution, em modo inbound, convivendo com o Agente N8N sem perda de mensagem.

### Story 2.1: Inbox de prospecção espelhada no Chatwoot

As a atendente de prospecção,
I want ver na central toda conversa do número de prospecção,
So that eu acompanhe os leads pescados num lugar só.

**Acceptance Criteria:**

**Given** o número novo conectado via Evolution (integração nativa Chatwoot) como inbox `WhatsApp Prospecção`
**When** um lead envia mensagem ao número
**Then** a mensagem aparece como conversa/mensagem na inbox `WhatsApp Prospecção`.

**Given** uma conversa aberta na central
**When** respondo pela central
**Then** o lead recebe a resposta no WhatsApp
**And** mídia recebida (imagem/documento) é anexada à conversa.

### Story 2.2: Convivência com o Agente N8N sem perda (fan-out)

As a arquiteto,
I want que o N8N e o Chatwoot recebam cada mensagem do número de prospecção,
So that a automação de recepção e o espelho coexistam sem um engolir o evento do outro.

**Acceptance Criteria:**

**Given** a instância Evolution no CRM configurada para fan-out
**When** chega uma mensagem inbound no número de prospecção
**Then** o fluxo N8N e o Chatwoot recebem o evento (at-least-once, consumidores idempotentes).

**Given** um lead novo desconhecido
**When** o Agente N8N envia a saudação e o link Jotform
**Then** essas mensagens outbound aparecem na conversa da central
**And** não há mensagem sistematicamente perdida ou duplicada entre os dois consumidores.

### Story 2.3: Aquecimento e proteção do número

As a operação,
I want operar o número novo em ritmo de aquecimento e só inbound,
So that eu reduza o risco de bloqueio do WhatsApp.

**Acceptance Criteria:**

**Given** o número de prospecção
**When** reviso sua operação
**Then** ele não dispara outbound frio em massa
**And** existe um limite/orientação documentado de volume inicial crescente (aquecimento).

---

## Epic 3: Canal WhatsApp Oficial (Twilio/Meta)

Conectar o número oficial (Twilio) como inbox de cobrança/transacional e espelhar os disparos em massa originados no monorepo.

### Story 3.1: Inbox oficial espelhada

As a atendente/cobrança,
I want ver e responder as conversas do número oficial na central,
So that o atendimento oficial fique unificado com os demais canais.

**Acceptance Criteria:**

**Given** o número Twilio conectado como inbox `WhatsApp Oficial`
**When** um cliente envia mensagem ao número oficial
**Then** ela aparece na inbox `WhatsApp Oficial`.

**Given** uma conversa dentro da janela de 24h
**When** respondo pela central
**Then** a mensagem é enviada pelo canal oficial
**And** fora da janela de 24h, o envio usa template Meta aprovado.

### Story 3.2: Espelho dos disparos em massa (push do monorepo)

As a responsável por cobrança,
I want ver na conversa os disparos de cobrança que saíram pelo pipeline do monorepo,
So that disparo e resposta fiquem na mesma thread.

**Acceptance Criteria:**

**Given** um disparo de cobrança enviado pelo pipeline do monorepo
**When** o pipeline registra o outbound via API do Chatwoot (AD-6)
**Then** a mensagem outbound aparece na conversa correta do contato na central.

**Given** um cliente que recebeu o disparo
**When** ele responde
**Then** a resposta cai na mesma thread do disparo
**And** a central não origina o disparo em massa (permanece no monorepo).

---

## Epic 4: Canal E-mail (Gmail)

Conectar uma caixa Gmail de atendimento como inbox de e-mail, com as threads unificadas ao mesmo contato dos canais de WhatsApp.

### Story 4.1: Inbox de e-mail espelhada

As a atendente de operação,
I want receber e responder e-mails de dentro da central,
So that o e-mail entre no mesmo fluxo de atendimento.

**Acceptance Criteria:**

**Given** a caixa Gmail conectada (IMAP/SMTP) como inbox `E-mail`
**When** chega um e-mail na caixa
**Then** ele vira uma conversa na inbox `E-mail`.

**Given** uma conversa de e-mail
**When** respondo pela central
**Then** o remetente recebe a resposta por e-mail na mesma thread.

### Story 4.2: Unificação sob o mesmo contato

As a atendente,
I want que e-mail e WhatsApp do mesmo cliente apareçam sob o mesmo contato,
So that eu veja a história completa sem duplicidade.

**Acceptance Criteria:**

**Given** um contato com e-mail e telefone conhecidos
**When** existem conversas de e-mail e de WhatsApp desse cliente
**Then** ambas aparecem sob o mesmo Contato quando e-mail/documento casam
**And** o contato não é duplicado entre as inboxes (depende de Epic 5).

---

## Epic 5: Serviço de Sync — Enriquecimento de Contato

Construir a Ponte: resolução de identidade por telefone+documento e push unidirecional de labels e atributos, mantendo a central desacoplada dos bancos de domínio. Único componente construído do zero.

### Story 5.1: Resolução de identidade por telefone + documento

As a Serviço de Sync,
I want reconciliar uma conversa a um contato conhecido no Twenty e/ou Supabase,
So that o operador saiba com quem está falando sem duplicar contatos.

**Acceptance Criteria:**

**Given** uma conversa recebida com um telefone
**When** o serviço normaliza o telefone para E.164 e busca nos sistemas de domínio
**Then** um contato reconhecido resulta num único Contato no Chatwoot com `source_twenty_id`/`source_supabase_id` preenchidos.

**Given** um número/e-mail desconhecido
**When** não há match
**Then** cria um Contato marcado com label `nao-identificado`.

### Story 5.2: Regra de merge (auto vs. sugestão)

As a Serviço de Sync,
I want aplicar merge automático só quando telefone E documento casam,
So that eu evite juntar contatos errados.

**Acceptance Criteria:**

**Given** um contato cujo telefone (E.164) e documento casam na mesma fonte
**When** o serviço reconcilia
**Then** faz merge automático num único Contato.

**Given** um contato onde só o telefone OU só o documento casa
**When** o serviço reconcilia
**Then** cria uma **sugestão de merge** com status `pending` para revisão humana
**And** não altera o contato até aprovação.

### Story 5.3: Push de labels de segmento/estado

As a Serviço de Sync,
I want aplicar/atualizar labels quando o estado muda no domínio,
So that o operador filtre e enxergue o segmento do contato.

**Acceptance Criteria:**

**Given** uma transição de estado no domínio (ex.: lead converteu, entrou na régua, virou inadimplente)
**When** o serviço recebe o evento
**Then** a label correspondente do dicionário fechado é aplicada ao Contato/Conversa em tempo hábil
**And** apenas labels do Glossário são usadas (sem sinônimos).

### Story 5.4: Push de atributos de domínio

As a Serviço de Sync,
I want preencher atributos custom do Contato,
So that o contexto apareça na barra lateral no ponto de contato.

**Acceptance Criteria:**

**Given** um contato reconhecido
**When** o serviço empurra os atributos (`cnpj`, `status_operacao`, `dias_atraso`, `valor_em_aberto`, `link_twenty`, `link_supabase`)
**Then** eles aparecem na barra lateral ao abrir a conversa
**And** os atributos de link abrem o registro-fonte no Twenty/Supabase.

### Story 5.5: Desacoplamento e degradação graciosa

As a arquiteto,
I want que a central funcione mesmo com o domínio indisponível,
So that uma falha no CRM/monorepo nunca derrube o atendimento.

**Acceptance Criteria:**

**Given** o Twenty ou o Supabase indisponível
**When** chega uma mensagem
**Then** receber e responder continua funcionando; só o enriquecimento fica desatualizado até normalizar.

**Given** o caminho de atendimento
**When** inspeciono as chamadas do Chatwoot
**Then** não há chamada síncrona da central aos bancos de domínio (AD-2)
**And** o push de enriquecimento é idempotente e faz retry com backoff em falha transitória.

---

## Epic 6: Operação de Atendimento & Governança

Configurar a operação nativa do Chatwoot (cockpit, papéis, atribuição, labels, respostas rápidas) e fechar os requisitos de governança (LGPD, observabilidade).

### Story 6.1: Cockpit unificado e papéis de agente

As a gestão,
I want todas as inboxes numa tela e papéis de agente definidos,
So that a equipe atenda de um lugar só com acesso adequado.

**Acceptance Criteria:**

**Given** as 3 inboxes configuradas
**When** um agente autorizado acessa a central
**Then** ele vê as inboxes numa interface única.

**Given** papéis definidos (admin/agente)
**When** um agente sem permissão tenta acessar uma inbox restrita
**Then** o acesso é negado conforme o papel.

### Story 6.2: Atribuição, labels manuais e respostas rápidas

As a operador,
I want assumir/atribuir conversas, aplicar labels e usar respostas rápidas,
So that eu conduza o atendimento com agilidade.

**Acceptance Criteria:**

**Given** uma conversa
**When** eu assumo ou atribuo a outro agente
**Then** a atribuição (manual e automática por inbox) é aplicada.

**Given** a composição de resposta
**When** uso uma resposta rápida configurada
**Then** ela é inserida
**And** posso aplicar labels manualmente além das empurradas pelo Sync.

### Story 6.3: Observabilidade e conformidade LGPD

As a gestão,
I want logs, healthchecks e retenção configurada,
So that a central seja auditável e conforme.

**Acceptance Criteria:**

**Given** a central em produção
**When** um serviço falha ou a conexão Evolution cai
**Then** há log estruturado e alerta de saúde da conexão.

**Given** a política de retenção definida
**When** verifico a configuração
**Then** a retenção de conversas está aplicada e o acesso a dados sensíveis (CPF/CNPJ) é restrito por papel.

---

## Sequenciamento sugerido

1. **Epic 1** (fundação) — bloqueia tudo.
2. **Epic 2, 3, 4** (canais) — podem correr em paralelo após o Epic 1; o Epic 2 tem a complexidade extra da convivência com o N8N.
3. **Epic 5** (sync) — inicia após ≥1 canal vivo; entrega o valor de contexto.
4. **Epic 6** (operação/governança) — fecha o MVP.

**Próximo passo BMAD:** `bmad-check-implementation-readiness` (alinhar PRD ↔ Architecture ↔ Epics) e depois `bmad-sprint-planning` para iniciar a implementação.
