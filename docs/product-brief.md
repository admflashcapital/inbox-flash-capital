---
title: Inbox Flash Capital — Product Brief
created: 2026-07-13
updated: 2026-07-13
phase: 1-analysis
skill: bmad-product-brief
---

# Product Brief: Inbox Flash Capital

> ### ⚠️ REESCOPO — 2026-09-02
>
> **O MVP cai de 3 canais para 2** — WhatsApp Oficial (Twilio) e E-mail (Gmail). O canal de prospecção via Evolution foi cancelado junto com o EPIC-2, e o Serviço de Sync (EPIC-5) também. O Chatwoot é **painel de acompanhamento dos disparos da cobrança/operacional**, e **nunca** um site público (AD-11).
>
> Ver **AD-10..AD-13** em `inbox/docs/architecture.md`, **ADR-010** em `crm/docs/07_Decisoes.md`, e o `HANDOFF-espelho-chatwoot.md`.


## Executive Summary

A Flash Capital fala com o mercado por vários canais e várias identidades ao mesmo tempo: um WhatsApp de relacionamento próximo com quem já opera, um número oficial (Twilio/Meta API) usado para cobrança e transacional, caixas de e-mail no Gmail, e um novo número de prospecção que recepciona os leads "pescados". Hoje cada canal vive numa ferramenta diferente, sem histórico unificado, sem visão única do contato e sem rastreabilidade — o operador troca de app o dia inteiro e ninguém enxerga a conversa inteira de um cliente.

O **Inbox Flash Capital** é uma central de atendimento omnichannel self-hosted (baseada no **Chatwoot**, open-source) que consolida todos esses números e caixas de e-mail **numa única tela**. Ele funciona como **espelho** das conversas — não é dono de nenhum dado de negócio — e enriquece cada contato com o contexto "mastigado" que já existe no CRM (Twenty) e na plataforma interna (Supabase): quem é a pessoa, CNPJ, estágio no funil, situação de operação e de cobrança, com link clicável para o registro-fonte.

Por que agora: os dois provedores de WhatsApp que a central precisa **já estão rodando** na infra da Flash (Evolution API no CRM, Twilio no monorepo). Falta a camada que junta tudo num cockpit único de atendimento. O ganho é imediato — histórico único, resposta mais rápida, reputação de número protegida por segmentação de risco — e o custo incremental é baixo porque reaproveita infraestrutura existente.

## The Problem

- **Conversas fragmentadas.** O mesmo cliente pode ter falado pelo WhatsApp de relacionamento, recebido uma cobrança pelo número oficial e trocado e-mails pelo Gmail. Ninguém consegue ver essa história junta. O contexto se perde a cada handoff entre pessoas e canais.
- **Contatos fragmentados em dois bancos isolados.** O comercial trabalha leads no **Twenty** (Postgres do CRM); a operação trabalha **cedentes/sacados** no **Supabase** (monorepo). São bancos separados, sem sincronização. O mesmo CNPJ pode existir nos dois lados sem qualquer ligação, e o atendente não sabe com quem está falando.
- **Sem rastreabilidade nem governança.** Não há registro persistente de conversa (no CRM o histórico do agente é efêmero — só as últimas mensagens; no monorepo cada disparo é um registro isolado, sem thread bidirecional). Isso é um risco operacional e de compliance (LGPD) num negócio financeiro.
- **Risco de reputação de número.** Misturar prospecção fria, cobrança e relacionamento no mesmo número coloca o canal de dinheiro (cobrança) refém da atividade mais arriscada (prospecção). Um número queimado leva os outros usos junto.

## The Solution

Uma central única onde **cada número/caixa é uma inbox** dentro do Chatwoot, e o operador atende tudo de um lugar só:

- **Chatwoot self-hosted** roda na infra da Flash, via imagem oficial Docker, com versão fixada — dados 100% na casa, sem lock-in de fornecedor.
- **WhatsApp de prospecção** (número novo pré-pago) entra via **Evolution API** — integração nativa Evolution↔Chatwoot.
- **WhatsApp oficial** (Twilio/Meta API) entra como inbox de cobrança/transacional.
- **Gmail** entra como canal de e-mail — cada thread vira uma conversa na mesma tela.
- **Enriquecimento de contato "mastigado":** um serviço de sincronização empurra **labels** (segmento/estado: `lead-frio`, `cliente-ativo`, `em-cobranca`…) e **atributos** (CNPJ, status da operação, dias de atraso, links) para o Chatwoot, casando a identidade por **telefone (E.164) + documento (CPF/CNPJ)**. O Chatwoot não consulta os bancos — recebe o dado pronto.

O princípio inegociável: **o Chatwoot é espelho e cockpit, não fonte da verdade.** Twenty e Supabase continuam donos dos dados de domínio; a central só reflete conversas e mostra contexto.

## What Makes This Different

- **Reaproveita a infra existente, não reconstrói.** Evolution já está no CRM; Twilio já está no monorepo (com provider abstrato, webhook inbound e conceito multi-número prontos). A central é a cola que faltava, não um sistema do zero.
- **Espelho desacoplado.** Ao não tornar o Chatwoot dono de nada, elimina-se o acoplamento perigoso de amarrar o financeiro à disponibilidade de uma ferramenta de chat.
- **Soberania de dados e custo baixo.** Open-source, self-hosted, dados na própria infra; o incremental é essencialmente operar mais um container + um serviço de sync.
- **Segmentação de risco por número embutida no desenho.** Prospecção fria sai por e-mail; o WhatsApp de prospecção só responde a inbound; cobrança fica isolada no número oficial. A arquitetura protege a reputação por design.

## Who This Serves

- **Comercial / prospecção (usuário primário).** Recepciona leads pescados, envia o formulário Jotform, acompanha o funil. Precisa ver rápido "quem é esse número que chamou" e o estágio do lead.
- **Relacionamento / operação (usuário primário).** Atende quem já opera, resolve dúvidas de operações e documentação. Precisa do histórico completo e do contexto da operação ao lado da conversa.
- **Cobrança (usuário primário).** Dispara e acompanha cobrança pelo número oficial; precisa ver a régua e a situação de inadimplência no mesmo lugar da conversa.
- **Gestão (usuário secundário).** Precisa de visão de volume, tempo de resposta e rastreabilidade para governança e LGPD.

## Success Criteria

- **Painel único:** 100% das conversas dos canais em escopo (WhatsApp prospecção, WhatsApp oficial, Gmail) visíveis numa só tela, sem o operador abrir outra ferramenta.
- **Histórico preservado:** toda conversa fica persistida e recuperável por contato (hoje isso não existe).
- **Contexto no ponto de contato:** ao abrir uma conversa, o operador vê quem é (nome, CNPJ), segmento e situação (labels + atributos) sem precisar consultar outro sistema.
- **Reputação protegida:** zero mistura de prospecção fria no número de cobrança; número de prospecção operando só em modo inbound.
- **Tempo de primeira resposta** menor e mensurável após a consolidação.

## Scope

**Dentro (MVP):**
- Chatwoot self-hosted na infra da Flash (stack Docker: web + Sidekiq + Postgres/pgvector + Redis + Caddy TLS + backup).
- 3 inboxes consolidadas: WhatsApp prospecção (Evolution — número novo), WhatsApp oficial (Twilio/Meta), e-mail (Gmail).
- Convivência da instância de prospecção com o agente N8N já existente (dois consumidores do mesmo número).
- Enriquecimento mínimo de contato: serviço de sync empurrando labels + atributos e resolvendo identidade por telefone/documento.

**Fora (MVP):**
- Número de relacionamento (instância B do Evolution) — fase 2.
- Sincronização bidirecional profunda e painel iframe (Dashboard App) com dado ao vivo — fase 2.
- Motor de disparo em massa dentro do Chatwoot (cobrança/prospecção em massa continuam no pipeline atual do monorepo) — fase 2.
- SSO / embutir a central dentro da plataforma interna — fase 2.
- Agente de IA respondendo dentro do Chatwoot.

## Vision

Em 2–3 anos, o Inbox Flash Capital é a **camada de atendimento única de toda a Flash**: todos os canais (WhatsApp múltiplos, e-mail, e novos como Instagram/webchat) num cockpit só, com **identidade de contato unificada** entre CRM e plataforma interna, contexto de operação ao vivo ao lado de cada conversa, respostas assistidas por IA e automações de roteamento por segmento — sem nunca abrir mão do princípio de que a central espelha e orquestra, mas os dados de negócio moram nos sistemas de domínio.
