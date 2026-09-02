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

O Inbox Flash Capital consolida numa única tela todos os canais de conversa da Flash — múltiplos números de WhatsApp e caixas de e-mail — funcionando como **espelho** das conversas e **cockpit** dos operadores, sem ser dono de nenhum dado de negócio. Cada canal é uma inbox; cada contato aparece enriquecido com o contexto que já vive no CRM (Twenty) e na plataforma interna (Supabase), casado por telefone e documento. O operador deixa de trocar de ferramenta e passa a ver a história inteira de cada cliente num lugar só, com o contexto certo ao lado da conversa. A central roda self-hosted na infra da Flash, reaproveitando os provedores de WhatsApp já existentes (Evolution e Twilio), com soberania total sobre os dados.

## 2. Target User

### 2.1 Jobs To Be Done

- **Como atendente de prospecção:** quando um lead pescado me chama no WhatsApp, quero reconhecê-lo e enviar o formulário Jotform sem sair da tela, para converter o contato em lead qualificado.
- **Como atendente de relacionamento:** quando um cliente que já opera me procura, quero ver o histórico completo e a situação da operação ao lado da conversa, para responder com contexto sem consultar outro sistema.
- **Como responsável por cobrança:** quando falo com um inadimplente, quero ver em que etapa da régua ele está e o valor em aberto na própria conversa, para conduzir a cobrança certa.
- **Como gestão:** quero visão de volume, tempo de resposta e um histórico auditável de todas as conversas, para governança e conformidade LGPD.
- **Como time de tecnologia:** quero uma central desacoplada dos sistemas de domínio, para que uma indisponibilidade da central nunca derrube cobrança ou operação.

### 2.2 Non-Users (v1)

- Clientes finais (cedentes/sacados) não usam a central diretamente — ela é ferramenta interna de atendimento. O cliente continua no WhatsApp/e-mail de sempre.
- O time que roda disparo em massa de cobrança/prospecção continua no pipeline atual do monorepo no MVP; a central ainda não é motor de campanha.

### 2.3 Key User Journeys

- **UJ-1. Rafael recepciona um lead pescado e manda o Jotform.**
  - **Persona + contexto:** Rafael, prospecção, recebe leads que vieram de campanhas de e-mail e chamaram no número novo de WhatsApp.
  - **Entry state:** autenticado no Chatwoot, inbox "WhatsApp Prospecção" aberta.
  - **Path:** chega uma conversa nova de número desconhecido → o agente N8N já respondeu a saudação e mandou o link Jotform automaticamente → Rafael vê a conversa espelhada com a label `lead-frio` → confirma que o link foi enviado e adiciona uma nota.
  - **Climax:** o contato aparece na central com histórico e label, sem Rafael ter feito nada manual no primeiro toque.
  - **Resolution:** conversa fica registrada; quando o lead responde o Jotform, o CRM cria o lead e a label muda para `lead-qualificado`.
  - **Edge case:** se o número já for cliente ativo (casou por telefone), a conversa entra já com `cliente-ativo` e é roteada para relacionamento, não prospecção.

- **UJ-2. Marina atende um cliente que já opera, com contexto completo.**
  - **Persona + contexto:** Marina, relacionamento, atende quem já tem operação ativa.
  - **Entry state:** autenticada, recebe atribuição de uma conversa no WhatsApp oficial/relacionamento.
  - **Path:** abre a conversa → na barra lateral vê nome, CNPJ, `cliente-ativo`, status da operação e link clicável para o registro no Supabase/Twenty → responde com base no contexto.
  - **Climax:** responde certo de primeira porque o contexto estava do lado, sem abrir outro sistema.
  - **Resolution:** conversa resolvida e etiquetada; histórico preservado para a próxima interação.

- **UJ-3. Carla conduz uma cobrança vendo a régua.**
  - **Persona + contexto:** Carla, cobrança, fala com inadimplentes pelo número oficial.
  - **Entry state:** autenticada, filtra a inbox pela label `em-cobranca`.
  - **Path:** o disparo de cobrança saiu pelo pipeline do monorepo e foi espelhado como mensagem na conversa → o cliente respondeu → Carla vê `regua-etapa-2`, dias de atraso e valor em aberto nos atributos → negocia.
  - **Climax:** a resposta do cliente e o disparo estão na mesma thread, com a situação de cobrança visível.
  - **Resolution:** Carla atualiza o resultado; a mudança de etapa da régua (feita no sistema de origem) reflete a nova label.

- **UJ-4. Bruno atende um e-mail que virou conversa.**
  - **Persona + contexto:** Bruno, operação, monitora a caixa Gmail de atendimento.
  - **Entry state:** autenticado, inbox "E-mail" aberta.
  - **Path:** chega um e-mail → vira uma conversa na central, casada ao mesmo contato do WhatsApp por e-mail/documento → Bruno responde de dentro do Chatwoot → o cliente recebe por e-mail normalmente.
  - **Climax:** e-mail e WhatsApp do mesmo cliente aparecem sob o mesmo contato.
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
- **Provedor** — serviço que conecta um número ao Chatwoot. Dois no MVP: **Evolution API** (WhatsApp não-oficial via Baileys) e **Twilio** (WhatsApp oficial via Meta API).
- **Evolution API** — servidor self-hosted de WhatsApp (Baileys), multi-instância. Já existe na infra do CRM.
- **Instância (Evolution)** — uma sessão/conexão de um número dentro do Evolution. **Instância A** = número novo de prospecção (escopo MVP).
- **Twilio / número oficial** — número WhatsApp Business API oficial (Meta), já em uso no monorepo para cobrança/transacional.
- **Serviço de Sync (Ponte)** — serviço próprio que empurra labels e atributos para o Chatwoot e resolve identidade de contato por telefone/documento. Único componente construído do zero.
- **Twenty** — CRM open-source (fonte da verdade do funil comercial). Entidade central: **Lead** (empresa+contato achatados; tem CNPJ, telefone, e-mail).
- **Supabase (monorepo)** — Postgres da plataforma interna (fonte da verdade operacional). Entidades: **cedentes**, **sacados**, **perfil**.
- **Label (Etiqueta)** — marcador de segmento/estado no Chatwoot, filtrável e acionável por automação. Ex.: `lead-frio`, `lead-qualificado`, `cliente-ativo`, `em-cobranca`, `regua-etapa-N`, `inadimplente`.
- **Atributo custom** — dado-ponto exibido na barra lateral do Contato/Conversa. Ex.: `cnpj`, `status_operacao`, `dias_atraso`, `valor_em_aberto`, `link_twenty`, `link_supabase`.
- **Identidade de contato** — chave dupla de reconciliação: **telefone em E.164** + **documento (CPF/CNPJ)**.
- **Agente N8N** — automação já existente no CRM que recepciona leads no WhatsApp e envia o Jotform. Convive com a central no número de prospecção.
- **Jotform** — formulário de captação de lead enviado ao contato na recepção da prospecção.
- **Régua de cobrança** — máquina de estados de cobrança cuja lógica vive no worker/API do monorepo; cada transição empurra label/atributo para a central.

## 4. Features

### 4.1 Plataforma Chatwoot self-hosted

**Description:** Stand up da instância Chatwoot na infra da Flash, via imagem oficial Docker com versão fixada, servindo como base de todas as inboxes. Roda como espelho/cockpit e é o sistema da verdade **apenas** de conversas e da identidade de contato de conversa. Realiza UJ-5 e sustenta UJ-1..UJ-4. `[ASSUMPTION: deploy num host/VM próprio da Flash com Docker; TLS via Caddy, mesmo padrão já usado no CRM.]`

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

### 4.2 Canal WhatsApp Prospecção (Evolution — Instância A)

**Description:** Conecta o número novo (pré-pago) como inbox de prospecção, via Evolution API, usando a integração nativa Evolution↔Chatwoot. Esse número opera **só em modo inbound** (recepção de leads pescados); nenhuma prospecção fria sai por ele. Convive com o Agente N8N que já recepciona e envia o Jotform. Realiza UJ-1. `[ASSUMPTION: usa-se a integração nativa da Evolution com o Chatwoot; o número entra como um device vinculado (Baileys), sem migrar para Cloud API.]`

**Functional Requirements:**

#### FR-4: Inbox de prospecção espelhada
Atendente de prospecção pode ver, na central, toda conversa recebida no número de prospecção, com mensagens inbound e outbound refletidas em tempo hábil.
**Consequences (testable):**
- Mensagem enviada pelo lead ao número aparece como conversa/mensagem na inbox "WhatsApp Prospecção".
- Resposta enviada pela central chega ao lead no WhatsApp.
- Mídia (imagem/documento) recebida é anexada à conversa.

#### FR-5: Convivência com o Agente N8N (dois consumidores)
O Agente N8N pode continuar recepcionando o lead e enviando o Jotform, e a central pode espelhar essa conversa **sem** um consumidor engolir o evento do outro.
**Consequences (testable):**
- Uma mensagem inbound é entregue tanto ao fluxo do N8N quanto ao Chatwoot.
- A saudação + link Jotform disparados pelo N8N aparecem na conversa da central.
- Não há mensagem perdida nem duplicada de forma sistemática entre os dois consumidores.
**Out of Scope:**
- Reescrever o Agente N8N ou movê-lo para dentro do Chatwoot.

#### FR-6: Aquecimento e proteção do número
Operação pode operar o número novo em ritmo de aquecimento para reduzir risco de bloqueio.
**Consequences (testable):**
- O número não dispara outbound frio em massa.
- Existe orientação/limite documentado de volume inicial crescente.

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

### 4.5 Enriquecimento de Contato (contexto mastigado)

**Description:** Um Serviço de Sync (a Ponte) empurra para o Chatwoot, via API, labels de segmento/estado e atributos de domínio, resolvendo a identidade do contato por telefone (E.164) + documento (CPF/CNPJ). O fluxo é **orientado a evento e unidirecional** (sistemas de domínio → Chatwoot); o Chatwoot nunca consulta os bancos de domínio em runtime. Sustenta UJ-2 e UJ-3. Este é o único componente construído do zero.

**Functional Requirements:**

#### FR-11: Resolução de identidade de contato
O serviço pode reconciliar uma conversa recebida a um contato conhecido no Twenty e/ou Supabase por telefone e/ou documento, sem duplicar.
**Consequences (testable):**
- Telefone normalizado para E.164 antes de casar (reaproveitando normalizadores já existentes nos dois projetos).
- Um contato reconhecido nos dois sistemas resulta num único Contato no Chatwoot, com links para ambos.
- Número/e-mail desconhecido gera um Contato novo marcado como não reconhecido (ex.: label `nao-identificado`).

#### FR-12: Push de labels de segmento/estado
O serviço pode aplicar/atualizar labels no Contato/Conversa quando o estado muda nos sistemas de domínio.
**Consequences (testable):**
- Transição de estado no domínio (ex.: lead converteu, entrou na régua, virou inadimplente) reflete a label correspondente no Chatwoot em tempo hábil.
- As labels são as do Glossário (dicionário fechado, sem sinônimos).

#### FR-13: Push de atributos de domínio
O serviço pode preencher atributos custom do Contato (cnpj, status_operacao, dias_atraso, valor_em_aberto, link_twenty, link_supabase).
**Consequences (testable):**
- Ao abrir uma conversa, o operador vê os atributos preenchidos na barra lateral.
- Cada atributo de link abre o registro-fonte no Twenty/Supabase.

#### FR-14: Direção de fluxo e desacoplamento
A central pode operar mesmo se um sistema de domínio estiver indisponível (o enriquecimento degrada, o atendimento não para).
**Consequences (testable):**
- Indisponibilidade do Twenty/Supabase não impede receber/responder mensagens; apenas o enriquecimento fica desatualizado até normalizar.
- O Chatwoot não faz chamadas síncronas aos bancos de domínio no caminho de atendimento.

**Notes:** `[NOTE FOR PM]` A profundidade da reconciliação (só telefone? telefone+documento com merge automático vs. sugestão de merge?) é a decisão de engenharia mais sensível — detalhada na Architecture.

### 4.6 Operação de atendimento (nativo Chatwoot)

**Description:** Uso das capacidades nativas do Chatwoot para operar o atendimento: múltiplas inboxes numa tela, atribuição de conversas a agentes, labels, respostas rápidas (canned responses), notas internas e relatórios. Sem desenvolvimento — é configuração. Realiza UJ-5.

**Functional Requirements:**

#### FR-15: Cockpit unificado e papéis
Operador pode atender todas as inboxes em escopo numa interface única, e gestão pode definir papéis/permissões de agentes.
**Consequences (testable):**
- As 3 inboxes aparecem para os agentes autorizados numa só tela.
- Agentes têm papéis (admin/agente) e só veem o que lhes cabe.

#### FR-16: Atribuição, labels e respostas rápidas
Operador pode assumir/atribuir conversas, aplicar labels manualmente e usar respostas rápidas.
**Consequences (testable):**
- Atribuição manual e automática (por inbox) funcionam.
- Respostas rápidas configuradas ficam disponíveis na composição.

## 5. Non-Goals (Explicit)

- A central **não é fonte da verdade** de dados de negócio (contatos de domínio, contratos, operações, cobrança) — esses moram no Twenty e no Supabase.
- A central **não é motor de disparo em massa** no MVP — cobrança/prospecção em massa continuam no pipeline do monorepo.
- A central **não faz prospecção fria por WhatsApp** — prospecção fria sai por e-mail; WhatsApp de prospecção é inbound-iniciado.
- A central **não substitui** o CRM (Twenty) nem a plataforma interna (monorepo).
- Não há **fork do Chatwoot** no MVP — usa-se imagem oficial + pontos de extensão (API, webhooks, automações, atributos custom).
- Não há **agente de IA** respondendo dentro do Chatwoot no MVP.

## 6. MVP Scope

### 6.1 In Scope

- Chatwoot self-hosted (web + Sidekiq + Postgres/pgvector + Redis) na infra da Flash, versão fixada, com backup.
- Inbox WhatsApp Prospecção via Evolution (número novo, instância A), convivendo com o Agente N8N, modo inbound.
- Inbox WhatsApp Oficial via Twilio/Meta, com espelho dos disparos do monorepo.
- Inbox E-mail via Gmail.
- Serviço de Sync (Ponte) v1: resolução de identidade por telefone+documento e push de labels + atributos.
- Operação nativa: cockpit único, papéis, atribuição, labels, respostas rápidas, relatórios.

### 6.2 Out of Scope for MVP

- Número de relacionamento (Evolution instância B) — fase 2. `[NOTE FOR PM: emocionalmente relevante; revisar se o cronograma permitir incluir cedo, pois é baixo esforço — só espelho, sem agente.]`
- Dashboard App (iframe) com dado de operação ao vivo — fase 2 (MVP usa só atributos empurrados).
- Sincronização bidirecional (central → domínio) — fase 2; MVP é unidirecional.
- Disparo em massa originado na central / campanhas Chatwoot — fase 2.
- SSO e embutir a central na plataforma interna (:3000) — fase 2.
- Novos canais (Instagram, webchat, Telegram) — futuro.

## 7. Success Metrics

**Primary**
- **SM-1**: Cobertura de canais — % das conversas dos 3 canais visíveis na central. Target: 100%. Valida FR-4, FR-7, FR-9.
- **SM-2**: Tempo de primeira resposta (TPR) — mediana do tempo entre inbound e primeira resposta humana, por inbox. Target: reduzir vs. baseline pré-central. Valida FR-15, FR-16.
- **SM-3**: Contexto no ponto de contato — % de conversas de contatos conhecidos que abrem com labels+atributos preenchidos. Target: ≥ 90% dos contatos que existem no domínio. Valida FR-11, FR-12, FR-13.

**Secondary**
- **SM-4**: Persistência/rastreabilidade — % de conversas com histórico completo recuperável por contato. Target: 100%. Valida FR-1, FR-10.
- **SM-5**: Saúde do número de prospecção — número não bloqueado durante o período de aquecimento. Valida FR-6.

**Counter-metrics (não otimizar)**
- **SM-C1**: Volume de mensagens automáticas no número de prospecção — não aumentar para "parecer produtivo"; aumentaria risco de bloqueio. Contrabalança SM-1/SM-5.
- **SM-C2**: Quantidade de atributos empurrados — não inflar o enriquecimento a ponto de acoplar a central aos bancos de domínio; contrabalança SM-3 (preferir Dashboard App na fase 2 para dado profundo).

## 8. Cross-Cutting NFRs

- **Desacoplamento:** nenhuma chamada síncrona da central aos bancos de domínio no caminho de atendimento (FR-14).
- **Segurança:** segredos (tokens Evolution/Twilio/Chatwoot, credenciais Gmail) fora do repositório; TLS em todo tráfego externo; validação de assinatura nos webhooks (o webhook Twilio inbound já valida `X-Twilio-Signature` no monorepo).
- **Privacidade / LGPD:** retenção de conversas configurável; base legal e política de acesso definidas; dados sensíveis (CPF/CNPJ) tratados como internos.
- **Observabilidade:** logs e healthcheck de cada serviço; alerta na saúde da conexão Evolution (o CRM já tem cron de saúde do WhatsApp que pode inspirar).
- **Confiabilidade:** entrega de mensagens tolerante a falha transitória; a convivência N8N↔Chatwoot no número de prospecção não pode perder mensagens (FR-5).

## 9. Constraints and Guardrails

- **Reputação de número (guardrail de negócio):** prospecção fria nunca no número oficial; número de prospecção só inbound; cobrança isolada.
- **Licença:** usar Chatwoot Community Edition (MIT); não habilitar features da pasta `enterprise/` sem licença.
- **Custo:** incremental limitado a um host para a stack Chatwoot + o Serviço de Sync; sem SaaS pago obrigatório.
- **Soberania:** todos os dados na infra da Flash (Postgres/Redis/anexos próprios).

## 10. Open Questions

**Resolvidas (2026-07-13):**
1. ✅ **Instância Evolution permanece no compose do CRM**, alimentando o agente N8N e o Chatwoot (fan-out de eventos). Ver AD-5 na Architecture.
2. ✅ **Reconciliação:** merge **automático** quando telefone (E.164) **e** documento casam; **sugestão de merge** para revisão humana quando só uma das chaves casa. Ver AD-3.
3. ✅ **Espelho dos disparos em massa:** o **monorepo empurra o outbound** para a conversa via API do Chatwoot (não depende só do inbound nativo). Ver AD-6.

**Em aberto (defaults assumidos, ajustáveis):**
4. Retenção de conversas (LGPD): qual janela e qual base legal? `[default: reter enquanto houver relação comercial + prazo legal; confirmar com jurídico.]`
5. Domínio/subdomínio da central (ex.: `atendimento.flashcapital.com.br`) e onde hospedar (VM dedicada vs. host existente).
6. Gmail: conta única de atendimento ou várias caixas? Conexão por IMAP/SMTP direto atende, ou precisa de OAuth Google? `[default: uma caixa de atendimento via IMAP/SMTP no MVP.]`

## 11. Assumptions Index

- §4.1 — Deploy em host/VM próprio da Flash com Docker; o TLS é do ingresso, quando houver.
- §4.2 — Integração nativa Evolution↔Chatwoot; número entra como device vinculado (Baileys), sem migrar para Cloud API.
- §4.3 — Reaproveita o provider Twilio do monorepo (ABC WhatsAppProvider, webhook inbound, templates Meta); central conecta o mesmo número como inbox Twilio.
- §4.4 — Gmail conectado via IMAP/SMTP; modelo caixa de suporte.
- §4.5 — Enriquecimento unidirecional e orientado a evento; identidade por telefone E.164 + documento.
