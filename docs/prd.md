---
title: Inbox Flash Capital
created: 2026-07-13
updated: 2026-07-13
phase: 2-planning
skill: bmad-prd
---

# PRD: Inbox Flash Capital

*Working title — confirmar.*

## 0. Document Purpose

Este PRD é para o time da Flash Capital que vai implementar a central de atendimento (dev, operação e gestão comercial) e para os workflows BMAD downstream (Architecture, Epics & Stories). Ele está estruturado com vocabulário ancorado num **Glossário** (§3) usado verbatim no resto do documento, **features** agrupadas com **FRs** aninhadas e numeradas globalmente (FR-N), e **assumptions** marcadas inline `[ASSUMPTION]` e indexadas em §9. Ele constrói sobre o [Product Brief](./product-brief.md) e não o duplica. Não há doc de UX separado: a UI é a do Chatwoot (produto pronto), então UX é tratado como configuração, não como design de telas novas.

## 1. Vision

O Inbox Flash Capital consolida numa única tela todos os canais de conversa da Flash — múltiplos números de WhatsApp e caixas de e-mail — funcionando como **espelho** das conversas e **cockpit** dos operadores, sem ser dono de nenhum dado de negócio. Cada canal é uma inbox; cada conversa carrega o contexto de domínio que o monorepo **carimba no instante do disparo** (AD-13). O operador deixa de trocar de ferramenta e passa a ver a história inteira de cada cliente num lugar só, com o contexto certo ao lado da conversa. A central roda self-hosted na infra da Flash, com soberania total sobre os dados.

## 2. Target User

### 2.1 Jobs To Be Done

- **Como atendente de relacionamento:** quando um cliente que já opera me procura, quero ver o histórico completo e a situação da operação ao lado da conversa, para responder com contexto sem consultar outro sistema.
- **Como responsável por cobrança:** quando falo com um inadimplente, quero ver em que etapa da régua ele está e o valor em aberto na própria conversa, para conduzir a cobrança certa.
- **Como gestão:** quero visão de volume, tempo de resposta e um histórico auditável de todas as conversas, para governança e conformidade LGPD.
- **Como time de tecnologia:** quero uma central desacoplada dos sistemas de domínio, para que uma indisponibilidade da central nunca derrube cobrança ou operação.

### 2.2 Non-Users (v1)

- Clientes finais (cedentes/sacados) não usam a central diretamente — ela é ferramenta interna de atendimento. O cliente continua no WhatsApp/e-mail de sempre.
- O time que roda disparo em massa de cobrança continua no pipeline atual do monorepo; a central não é motor de campanha, e não é meta que venha a ser.

### 2.3 Key User Journeys

- **UJ-2. Marina atende um cliente que já opera, com contexto completo.**
  - **Persona + contexto:** Marina, relacionamento, atende quem já tem operação ativa.
  - **Entry state:** autenticada, recebe atribuição de uma conversa no WhatsApp oficial/relacionamento.
  - **Path:** abre a conversa → na barra lateral vê os atributos que o disparo carimbou (CNPJ, valor em aberto, dias de atraso, título) → responde com base no contexto.
  - **Climax:** responde certo de primeira porque o contexto estava do lado, sem abrir outro sistema.
  - **Resolution:** conversa resolvida e etiquetada; histórico preservado para a próxima interação.

- **UJ-3. Carla conduz uma cobrança vendo a régua.**
  - **Persona + contexto:** Carla, cobrança, fala com inadimplentes pelo número oficial.
  - **Entry state:** autenticada, na inbox `WhatsApp Oficial`.
  - **Path:** o disparo de cobrança saiu pelo pipeline do monorepo e foi espelhado como mensagem na conversa → o cliente respondeu → Carla vê nos **atributos** o título, os dias de atraso e o valor em aberto que o disparo carimbou (AD-13) → negocia.
  - **Climax:** a resposta do cliente e o disparo estão na mesma thread, com a situação de cobrança visível.
  - **Resolution:** Carla etiqueta o **resultado da conversa** (`promessa-pagamento`, `negociacao`, `contestacao`…). A etapa da régua não vira label: ela é estado do título, vive no monorepo (AD-1) e chega aqui como atributo no próximo disparo.

- **UJ-4. Bruno atende um e-mail que virou conversa.**
  - **Persona + contexto:** Bruno, operação, monitora a caixa Gmail de atendimento.
  - **Entry state:** autenticado, inbox "E-mail" aberta.
  - **Path:** chega um e-mail → vira uma conversa na inbox `E-mail` → Bruno responde de dentro do Chatwoot → o cliente recebe por e-mail normalmente, na mesma thread.
  - **Climax:** o e-mail entra no mesmo fluxo de atendimento do WhatsApp, sem trocar de ferramenta.
  - **Resolution:** thread de e-mail registrada no histórico unificado.

- **UJ-5. Ana (gestão) audita o atendimento.**
  - **Persona + contexto:** Ana, gestão, precisa de rastreabilidade.
  - **Path:** acessa relatórios do Chatwoot → vê volume por inbox, tempo de resposta, conversas por agente e histórico completo de qualquer contato.
  - **Resolution:** exporta/consulta para fins de governança e LGPD.

## 3. Glossary

- **Central / Inbox Flash Capital** — a instância Chatwoot self-hosted que consolida os canais. Espelho e cockpit; nunca fonte da verdade de dados de negócio.
- **Inbox (Caixa)** — no Chatwoot, um canal conectado (um número de WhatsApp ou uma caixa de e-mail). Um número = uma Inbox.
- **Conversa** — thread bidirecional de mensagens entre um Contato e a Flash dentro de uma Inbox. Fonte da verdade da conversa é o Chatwoot.
- **Contato** — a identidade de conversa no Chatwoot (nome, telefone, e-mail, atributos custom). Não é dono do dado de domínio; é enriquecido a partir dele.
- **Provedor** — serviço que conecta um número ao Chatwoot. Um só: **Twilio** (WhatsApp oficial via Meta API).
- **Twilio / número oficial** — número WhatsApp Business API oficial (Meta), já em uso no monorepo para cobrança/transacional.
- **Twenty** — CRM open-source (fonte da verdade do funil comercial). Entidade central: **Lead** (empresa+contato achatados; tem CNPJ, telefone, e-mail).
- **Supabase (monorepo)** — Postgres da plataforma interna (fonte da verdade operacional). Entidades: **cedentes**, **sacados**, **perfil**.
- **Label (Etiqueta)** — marcador que a atendente aplica **à mão** na conversa, filtrável. Descreve o que a CONVERSA apurou, nunca o estado do TÍTULO — esse é do monorepo (AD-1), e repeti-lo aqui criaria duas verdades. Dicionário fechado, semeado por `scripts/seed/chatwoot_seed.rb`: `promessa-pagamento`, `negociacao`, `contestacao`, `aguardando-comprovante`, `contato-errado`, `sem-retorno`, `escalar-alcada`.
- **Atributo custom** — dado-ponto exibido na barra lateral da Conversa, gravado pelo monorepo no disparo. Ex.: `titulo_id`, `cnpj`, `dias_atraso`, `valor_em_aberto`.
- **Espelho** — o push do monorepo para a central: a mensagem que saiu pela Twilio é replicada na conversa, com `source_id` = `MessageSid`. Best-effort e sem retry (AD-12).
- **Régua de cobrança** — máquina de estados de cobrança cuja lógica vive no worker/API do monorepo; cada disparo dela é espelhado na central com o contexto do título.

## 4. Features

### 4.1 Plataforma Chatwoot self-hosted

**Description:** Stand up da instância Chatwoot na infra da Flash, via imagem oficial Docker com versão fixada, servindo como base de todas as inboxes. Roda como espelho/cockpit e é o sistema da verdade **apenas** de conversas e da identidade de contato de conversa. Realiza UJ-5 e sustenta UJ-1..UJ-4. `[ASSUMPTION: deploy num host/VM próprio da Flash com Docker; o TLS é do ingresso, quando houver — hoje a central só publica em loopback (AD-10, AD-11).]`

**Functional Requirements:**

#### FR-1: Deploy self-hosted reproduzível
Operação pode subir a central com um `docker compose up` a partir do repositório, com todos os serviços necessários (web, Sidekiq, Postgres/pgvector, Redis, reverse proxy TLS).
**Consequences (testable):**
- `docker compose up -d --wait` sobe web, Sidekiq, Postgres (com pgvector) e Redis sem passos manuais além de preencher o `.env`.
- A UI responde em HTTPS num domínio da Flash com certificado válido.
- Reiniciar os containers preserva conversas, contatos e configurações (dados em volume/DB persistente).

#### FR-2: Versão fixada e atualização controlada
Tecnologia pode fixar a versão da imagem Chatwoot e atualizar sob demanda, sem depender de acompanhar o upstream continuamente.
**Consequences (testable):**
- A imagem é referenciada por tag de versão explícita, nunca `latest`.
- Existe um procedimento documentado de upgrade (bump da tag + migrações) executável em staging antes de produção.

#### FR-3: Backup e retenção
Operação pode restaurar a central a partir de backup do Postgres e do storage de anexos.
**Consequences (testable):**
- Backup automatizado do banco do Chatwoot com periodicidade definida.
- Restore testado recompõe conversas e anexos.
- Política de retenção de conversas definida e configurada (LGPD).

**Feature-specific NFRs:**
- Isolamento: o banco do Chatwoot é **separado** dos bancos do CRM (Twenty) e do monorepo (Supabase) — sem compartilhamento de instância.

### 4.3 Canal WhatsApp Oficial (Twilio / Meta API)

**Description:** Conecta o número oficial (Twilio, API Meta) como inbox de cobrança/transacional. Inbound e outbound espelhados; disparo em massa de cobrança continua saindo pelo pipeline do monorepo, mas é **espelhado** na conversa para dar histórico unificado. Realiza UJ-3. `[ASSUMPTION: reaproveita o provider Twilio já existente no monorepo (ABC WhatsAppProvider, webhook inbound e templates Meta aprovados); a central conecta o mesmo número como inbox Twilio do Chatwoot.]`

**Functional Requirements:**

#### FR-7: Inbox oficial espelhada
Atendente/cobrança pode ver na central as conversas do número oficial, com inbound e outbound.
**Consequences (testable):**
- Mensagem recebida no número oficial aparece na inbox "WhatsApp Oficial".
- Resposta manual pela central é enviada via canal oficial, respeitando a janela de 24h e templates quando fora dela.

#### FR-8: Espelho dos disparos em massa
Cobrança pode ver, na conversa do contato, os disparos de cobrança que saíram pelo pipeline do monorepo.
**Consequences (testable):**
- Um disparo de cobrança enviado pelo monorepo aparece como mensagem outbound na conversa correta da central.
- A resposta do cliente ao disparo cai na mesma thread.
**Out of Scope:**
- Originar disparo em massa a partir da central (mantém-se no pipeline do monorepo no MVP).

### 4.4 Canal E-mail (Gmail)

**Description:** Conecta uma caixa Gmail de atendimento como inbox de e-mail; cada thread de e-mail vira uma conversa, casada ao mesmo contato dos canais de WhatsApp. Realiza UJ-4. `[ASSUMPTION: conexão via IMAP/SMTP da conta Gmail de atendimento; modelo "caixa de suporte", não cliente de e-mail completo.]`

**Functional Requirements:**

#### FR-9: Inbox de e-mail espelhada
Atendente pode receber e responder e-mails de dentro da central.
**Consequences (testable):**
- E-mail recebido na caixa configurada vira conversa na inbox "E-mail".
- Resposta enviada pela central chega ao remetente por e-mail, na mesma thread.

#### FR-10: Unificação sob o mesmo contato
Conversas de e-mail e de WhatsApp do mesmo cliente aparecem sob o mesmo Contato quando o e-mail/documento casa.
**Consequences (testable):**
- Um contato com e-mail conhecido e telefone conhecido não é duplicado entre a inbox de e-mail e as de WhatsApp.

### 4.5 Contexto de domínio na conversa (AD-13)

**Description:** O monorepo já conhece `titulo_id`, CNPJ, valor em aberto e dias de atraso **no instante em que dispara**. Em vez de um serviço reconciliar isso depois, o próprio espelho grava esses valores nos `custom_attributes` da conversa, no mesmo caminho de código que espelha a mensagem. Push unidirecional, sem reconciliação. Sustenta UJ-2 e UJ-3.

**Functional Requirements:**

#### FR-10: Contexto carimbado no disparo
A conversa exibe, na barra lateral, o contexto do título que originou o disparo.
**Consequences (testable):**
- Ao abrir uma conversa de cobrança, o operador vê `titulo_id`, `cnpj`, `valor_em_aberto` e `dias_atraso` preenchidos.
- O carimbo acontece **também quando a conversa é reusada**, não só quando é criada — o reuso é o caminho comum, e carimbar só na criação não entrega nada em produção.
- A central continua sem fazer chamada síncrona a banco de domínio no caminho de atendimento (AD-2).
- Falha ao carimbar **não derruba o disparo**: como todo caminho do espelho, é best-effort (AD-12).

**Notes:** o que morreu com o AD-13 não foi o contexto, foi a reconciliação. Um serviço que casasse identidade por telefone+documento depois do fato só faria sentido se o dado não estivesse na mão — e ele está.

### 4.6 Operação de atendimento (nativo Chatwoot)

**Description:** Uso das capacidades nativas do Chatwoot para operar o atendimento: múltiplas inboxes numa tela, atribuição de conversas a agentes, labels, respostas rápidas (canned responses), notas internas e relatórios. Sem desenvolvimento — é configuração. Realiza UJ-5.

**Functional Requirements:**

#### FR-15: Cockpit unificado e papéis
Operador pode atender todas as inboxes em escopo numa interface única, e gestão pode definir papéis/permissões de agentes.
**Consequences (testable):**
- As 2 inboxes aparecem para os agentes autorizados numa só tela.
- Agentes têm papéis (admin/agente) e só veem o que lhes cabe. ⚠️ O CE tem **dois** papéis e nada além: `custom_roles` é premium e está desligado. O que restringe um agente é a **inbox** (`inbox_members`), não o papel.

#### FR-16: Atribuição, labels e respostas rápidas
Operador pode assumir/atribuir conversas, aplicar labels manualmente e usar respostas rápidas.
**Consequences (testable):**
- Atribuição manual e automática (por inbox) funcionam.
- Respostas rápidas configuradas ficam disponíveis na composição.

## 5. Non-Goals (Explicit)

- A central **não é fonte da verdade** de dados de negócio (contatos de domínio, contratos, operações, cobrança) — esses moram no Twenty e no Supabase.
- A central **não é motor de disparo em massa** — a cobrança em massa continua no pipeline do monorepo.
- A Flash **não faz prospecção fria por WhatsApp** — ela sai por e-mail. O número oficial é exclusivo de cobrança e transacional; um número queimado por cold outreach levaria a cobrança junto.
- A central **não substitui** o CRM (Twenty) nem a plataforma interna (monorepo).
- Não há **fork do Chatwoot** no MVP — usa-se imagem oficial + pontos de extensão (API, webhooks, automações, atributos custom).
- Não há **agente de IA** respondendo dentro do Chatwoot no MVP.

## 6. MVP Scope

### 6.1 In Scope

- Chatwoot self-hosted (web + Sidekiq + Postgres/pgvector + Redis) na infra da Flash, versão fixada, com backup.
- Inbox WhatsApp Oficial via Twilio/Meta, com espelho dos disparos do monorepo.
- Inbox E-mail via Gmail.
- Contexto de domínio carimbado na conversa pelo próprio disparo do monorepo (AD-13).
- Operação nativa: cockpit único, papéis, atribuição, labels, respostas rápidas, relatórios.

### 6.2 Out of Scope for MVP

- Dashboard App (iframe) com dado de operação ao vivo — fase 2 (MVP usa só atributos empurrados).
- Sincronização bidirecional (central → domínio) — fase 2; hoje o fluxo é unidirecional.
- Reconciliação de identidade por telefone+documento entre Twenty e Supabase — fora de escopo por decisão (AD-13): o contexto chega no disparo, não por reconciliação posterior.
- Disparo em massa originado na central / campanhas Chatwoot — fase 2.
- SSO e embutir a central na plataforma interna (:3000) — fase 2.
- Novos canais (Instagram, webchat, Telegram) — futuro.

## 7. Success Metrics

**Primary**
- **SM-1**: Cobertura de canais — % das conversas dos 2 canais visíveis na central. Target: 100%. Valida FR-7, FR-9.
  ⚠️ Teto real: o espelho não tem retry nem backfill (AD-12), então indisponibilidade da central vira buraco permanente. Enquanto isso valer, esta métrica é **amostral por construção**.
- **SM-2**: Tempo de primeira resposta (TPR) — mediana do tempo entre inbound e primeira resposta humana, por inbox. Target: reduzir vs. baseline pré-central. Valida FR-15, FR-16.
- **SM-3**: Contexto no ponto de contato — % de conversas de cobrança que abrem com os `custom_attributes` preenchidos. Target: 100% dos disparos espelhados, porque o dado sai da mesma transação do disparo. Valida FR-10.

**Secondary**
- **SM-4**: Persistência/rastreabilidade — % de conversas com histórico completo recuperável por contato. Target: 100%. Valida FR-1, FR-10.

**Counter-metrics (não otimizar)**
- **SM-C1**: Volume de mensagens automáticas no número oficial — não aumentar para "parecer produtivo". O número é o ativo mais caro da cobrança: bloqueio dele para a operação inteira. Contrabalança SM-1.
- **SM-C2**: Quantidade de atributos carimbados — não inflar a ponto de acoplar a central aos bancos de domínio; contrabalança SM-3 (dado profundo é Dashboard App na fase 2).

## 8. Cross-Cutting NFRs

- **Desacoplamento:** nenhuma chamada síncrona da central aos bancos de domínio no caminho de atendimento (AD-2). O contexto chega empurrado, no disparo.
- **Segurança:** segredos (tokens Twilio/Chatwoot, credenciais Gmail) fora do repositório; validação de assinatura nos webhooks (o webhook Twilio inbound já valida `X-Twilio-Signature` no monorepo). ⚠️ O `/twilio/callback` da própria central **não valida assinatura nenhuma** — quem o nega é a **borda** (`deploy/ngrok-policy.yml`, HTTP 403). A proteção puramente topológica acabou quando a central ganhou URL pública (AD-11.1).
- **Privacidade / LGPD:** retenção de conversas configurável; base legal e política de acesso definidas; dados sensíveis (CPF/CNPJ) tratados como internos.
- **Observabilidade:** logs e healthcheck de cada serviço; alerta na saúde dos canais (Twilio e IMAP).
- **Confiabilidade:** o fan-out do inbound alimenta a confirmação de sacado **e** a central; a confirmação (dinheiro) nunca pode ficar refém da central (chat).

## 9. Constraints and Guardrails

- **Reputação de número (guardrail de negócio):** prospecção fria nunca por WhatsApp — sai por e-mail. O número oficial é exclusivo de cobrança e transacional.
- **Licença:** usar Chatwoot Community Edition (MIT); não habilitar features da pasta `enterprise/` sem licença.
- **Custo:** incremental limitado a um host para a stack Chatwoot; sem SaaS pago obrigatório.
- **Soberania:** todos os dados na infra da Flash (Postgres/Redis/anexos próprios).

## 10. Open Questions

**Resolvidas (2026-07-13):**
1. ✅ **Espelho dos disparos em massa:** o **monorepo empurra o outbound** para a conversa via API do Chatwoot (não depende só do inbound nativo). Ver AD-6.

**Em aberto (defaults assumidos, ajustáveis):**
2. ~~**Retenção de conversas (LGPD)**~~ **DECIDIDA.** 1825 dias (5 anos, prescrição civil comum de dívida) aprovados por escrito pelo operador em 2026-09-02; `scripts/retencao-conversas.sh` está no cron do host (domingo 04:10, com `flock`). Procedimento completo, incluindo o direito de exclusão do titular, em `docs/runbook-lgpd.md`. **Resíduo:** esta máquina não fica ligada às 4h de domingo — o cron existe, a execução não é garantida.
3. Onde a central executa e como se acessa — decisão de diretoria, fora do escopo das fases de simplificação. Hoje: localhost, sem ingresso.

## 11. Assumptions Index

- §4.1 — Deploy em host/VM próprio da Flash com Docker; o TLS é do ingresso, quando houver.
- §4.3 — Reaproveita o provider Twilio do monorepo (ABC WhatsAppProvider, webhook inbound, templates Meta); central conecta o mesmo número como inbox Twilio.
- §4.4 — Gmail conectado por **OAuth de usuário** (não service account: o grant JWT-bearer nunca emite `refresh_token`, e o Chatwoot exige um).
- §4.5 — Contexto empurrado no disparo, não reconciliado depois (AD-13).
