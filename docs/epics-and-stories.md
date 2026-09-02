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

## Overview

Decomposição completa em epics e stories a partir do [PRD](./prd.md) e da [Architecture](./architecture.md). Cada story referencia os FRs que realiza e traz critérios de aceite testáveis. A ordem de execução respeita as dependências: a Fundação (Epic 1) habilita os canais (Epics 3 e 4); a Operação & Governança (Epic 6) fecha o MVP.

A numeração tem lacunas em **2** e **5**, e elas não são reaproveitadas: os números continuam presos aos épicos que foram cancelados (AD-11 e AD-13), e reciclá-los faria referência antiga apontar para escopo novo.

## Requirements Inventory

### Functional Requirements
- **FR-1** Deploy self-hosted reproduzível · **FR-2** Versão fixada e upgrade controlado · **FR-3** Backup e retenção
- **FR-7** Inbox oficial espelhada · **FR-8** Espelho dos disparos em massa
- **FR-9** Inbox de e-mail espelhada · **FR-10** Contexto de domínio na conversa
- **FR-15** Cockpit unificado e papéis · **FR-16** Atribuição, labels e respostas rápidas

### NonFunctional Requirements
- Desacoplamento (sem chamada síncrona central→domínio) · Segurança (segredos, TLS, assinatura de webhook) · Privacidade/LGPD (retenção, acesso) · Observabilidade (logs, healthcheck, alerta de conexão) · Confiabilidade (entrega tolerante a falha; o fan-out do inbound alimenta a confirmação de sacado **e** a central, e a confirmação nunca fica refém da central).

### Additional Requirements
- Chatwoot Community Edition (MIT), sem fork (AD-7) · Banco da central isolado (AD-9) · Guardrail de reputação de número: **prospecção fria sai por e-mail, nunca por WhatsApp** — o número oficial é exclusivo de cobrança e transacional.

### UX Design Requirements
- Sem telas novas: UI é a do Chatwoot. UX = configuração de inboxes, labels, papéis e barra lateral de atributos.

### FR Coverage Map

| FR | Epic.Story |
| --- | --- |
| FR-1 | 1.1, 1.2 |
| FR-2 | 1.3 |
| FR-3 | 1.4 |
| FR-7 | 3.1 |
| FR-8 | 3.2 |
| FR-9 | 4.1 |
| FR-10 | 4.2 |
| FR-15 | 6.1 |
| FR-16 | 6.2 |

## Epic List

1. **Fundação da Plataforma** — Chatwoot self-hosted na infra da Flash (deploy, versão, backup). *(MVP)*
3. **Canal WhatsApp Oficial (Twilio/Meta)** — cobrança/transacional + espelho de disparos. *(MVP)*
4. **Canal E-mail (Gmail)** — thread de e-mail como conversa unificada. *(MVP)*
6. **Operação de Atendimento & Governança** — cockpit, papéis, labels, LGPD, observabilidade. *(MVP)*

---

## Epic 1: Fundação da Plataforma

Subir a instância Chatwoot self-hosted, reproduzível e segura, como base de todas as inboxes — versão fixada, isolada dos bancos de domínio e com backup/restore validado.

### Story 1.1: Stack Docker da central sobe com um comando

As a operação de tecnologia,
I want subir toda a stack da central com `docker compose up`,
So that a plataforma esteja disponível sem passos manuais frágeis.

**Acceptance Criteria:**

**Given** o repositório `inbox-flash-capital` com `compose.yaml` e `.env` preenchido
**When** executo `docker compose up`
**Then** sobem os serviços web, Sidekiq, Postgres (com pgvector) e Redis
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
**And** está documentado em `docs/` ou a raiz do repo.

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

### Story 4.2: Contexto de domínio carimbado na conversa (AD-13)

As a atendente,
I want ver o título, o CNPJ, o valor e os dias de atraso ao lado da conversa,
So that eu atenda sem sair da central para consultar outro sistema.

O contexto **não** é reconciliado depois: o monorepo já o conhece no instante do disparo e o empurra
junto. A central continua sem consultar banco de domínio em runtime (AD-2).

**Acceptance Criteria:**

**Given** um disparo de cobrança originado no monorepo
**When** o espelho grava a mensagem na central
**Then** a conversa carrega o contexto do título em `custom_attributes`, visível na barra lateral —
o conjunto fechado de `atributos.py::CHAVES` no monorepo (`titulo_id`, `cnpj`, `cedente`,
`numero_nf`, `data_vencimento`, `valor_em_aberto`, `dias_atraso`, `link_boleto`), com os campos
que o disparo não conhece **omitidos**, não gravados vazios.

**Given** os atributos gravados na conversa
**When** a atendente abre a barra lateral
**Then** cada um aparece com rótulo e tipo — o que exige uma `CustomAttributeDefinition` por chave
neste repo (`scripts/seed/chatwoot_seed.rb`). Sem a definição o valor é gravado e **não aparece**,
sem erro nenhum: a barra lateral itera as definições, não as chaves.

**Given** um cliente que **já tinha** conversa aberta nesta inbox
**When** um novo disparo reusa essa conversa em vez de abrir outra
**Then** os atributos são atualizados na conversa reusada — carimbar só na criação não atende o
critério, porque o reuso é o caminho comum.

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
**When** um serviço falha ou o canal (Twilio/IMAP) perde a conexão
**Then** há log estruturado e alerta de saúde da conexão.

**Given** que o espelho descarta o que não conseguiu entregar (AD-12)
**When** a central fica indisponível durante um disparo
**Then** a perda é visível em log — o painel não tem como se reconciliar depois.

**Given** a política de retenção definida
**When** verifico a configuração
**Then** a retenção de conversas está aplicada e o acesso a dados sensíveis (CPF/CNPJ) é restrito por papel.

---

## Sequenciamento sugerido

1. **Epic 1** (fundação) — bloqueia tudo.
2. **Epic 3 e 4** (canais) — podem correr em paralelo após o Epic 1.
3. **Epic 6** (operação/governança) — fecha o MVP. No Chatwoot é majoritariamente configuração, não código.
