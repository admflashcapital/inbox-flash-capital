---
title: Inbox Flash Capital — Product Brief
created: 2026-07-13
updated: 2026-09-02
phase: 1-analysis
skill: bmad-product-brief
---

# Product Brief: Inbox Flash Capital

## Executive Summary

A Flash Capital fala com o mercado por mais de um canal ao mesmo tempo: um número oficial (Twilio/Meta API) usado para cobrança e transacional, e caixas de e-mail no Gmail. Cada canal vive numa ferramenta diferente, sem histórico unificado e sem rastreabilidade — o operador troca de app o dia inteiro e ninguém enxerga a conversa inteira de um cliente.

O **Inbox Flash Capital** é uma central de atendimento omnichannel self-hosted (baseada no **Chatwoot**, open-source) que consolida todos esses números e caixas de e-mail **numa única tela**. Ele funciona como **espelho** das conversas — não é dono de nenhum dado de negócio — e cada conversa de cobrança chega com o contexto do título já carimbado nela: CNPJ, valor em aberto, dias de atraso. Esse dado não é reconciliado depois; o monorepo o conhece no instante do disparo e o empurra junto.

Por que agora: o provedor que a central precisa **já está rodando** na infra da Flash (Twilio, no monorepo), e o motor de disparo já emite o espelho. Falta a camada que junta tudo num cockpit único de atendimento. O ganho é imediato — histórico único, resposta mais rápida — e o custo incremental é baixo porque reaproveita infraestrutura existente.

## The Problem

- **Conversas fragmentadas.** O mesmo cliente pode ter recebido uma cobrança pelo número oficial e trocado e-mails pelo Gmail. Ninguém consegue ver essa história junta. O contexto se perde a cada handoff entre pessoas e canais.
- **O atendente não sabe com quem está falando.** A conversa chega como um número de telefone. Quem é o sacado, qual título, quanto está em aberto, há quantos dias — tudo isso mora no monorepo, e até agora não acompanhava a mensagem.
- **Sem rastreabilidade nem governança.** Não há registro persistente de conversa (no CRM o histórico do agente é efêmero — só as últimas mensagens; no monorepo cada disparo é um registro isolado, sem thread bidirecional). Isso é um risco operacional e de compliance (LGPD) num negócio financeiro.
- **Risco de reputação de número.** Misturar prospecção fria com cobrança no mesmo número colocaria o canal de dinheiro refém da atividade mais arriscada. Um número queimado leva a cobrança junto — por isso prospecção fria sai por e-mail, nunca por WhatsApp.

## The Solution

Uma central única onde **cada número/caixa é uma inbox** dentro do Chatwoot, e o operador atende tudo de um lugar só:

- **Chatwoot self-hosted** roda na infra da Flash, via imagem oficial Docker, com versão fixada — dados 100% na casa, sem lock-in de fornecedor.
- **WhatsApp oficial** (Twilio/Meta API) entra como inbox de cobrança/transacional.
- **Gmail** entra como canal de e-mail — cada thread vira uma conversa na mesma tela.
- **Contexto carimbado no disparo:** o mesmo caminho de código que espelha a mensagem grava `titulo_id`, CNPJ, valor em aberto e dias de atraso nos atributos da conversa. O Chatwoot não consulta os bancos — recebe o dado pronto, na hora.

O princípio inegociável: **o Chatwoot é espelho e cockpit, não fonte da verdade.** Twenty e Supabase continuam donos dos dados de domínio; a central só reflete conversas e mostra contexto.

## What Makes This Different

- **Reaproveita a infra existente, não reconstrói.** A Twilio já está no monorepo, com provider abstrato, webhook inbound e conceito multi-número prontos. A central é a cola que faltava, não um sistema do zero.
- **Espelho desacoplado.** Ao não tornar o Chatwoot dono de nada, elimina-se o acoplamento perigoso de amarrar o financeiro à disponibilidade de uma ferramenta de chat.
- **Soberania de dados e custo baixo.** Open-source, self-hosted, dados na própria infra; o incremental é essencialmente operar mais uma stack de containers — medida em **864 MiB** ociosa.
- **Assimetria proposital entre chat e dinheiro.** Central fora do ar → o espelho perde; a cobrança **não para**. Nunca o contrário. Todo caminho do espelho é best-effort: falha vira log, jamais exceção que suba.

## Who This Serves

- **Operação (usuário primário).** Atende quem já opera, resolve dúvidas de operações e documentação. Precisa do histórico completo e do contexto da operação ao lado da conversa.
- **Cobrança (usuário primário).** Dispara pelo monorepo e acompanha na central; precisa ver a resposta do cliente na **mesma thread** do disparo, com a situação do título ao lado.
- **Gestão (usuário secundário).** Precisa de visão de volume, tempo de resposta e rastreabilidade para governança e LGPD.

## Success Criteria

- **Painel único:** as conversas dos canais em escopo (WhatsApp oficial, Gmail) visíveis numa só tela, sem o operador abrir outra ferramenta. Com a ressalva honesta de que o espelho não tem retry: o painel é tão completo quanto o uptime de quem o alimenta.
- **Histórico preservado:** toda conversa fica persistida e recuperável por contato (hoje isso não existe).
- **Contexto no ponto de contato:** ao abrir uma conversa de cobrança, o operador vê CNPJ, título, valor em aberto e dias de atraso sem consultar outro sistema.
- **Reputação protegida:** zero prospecção fria por WhatsApp; o número oficial é exclusivo de cobrança e transacional.
- **Tempo de primeira resposta** menor e mensurável após a consolidação.

## Scope

**Dentro (MVP):**
- Chatwoot self-hosted na infra da Flash (stack Docker: web + Sidekiq + Postgres/pgvector + Redis + backup).
- 2 inboxes consolidadas: WhatsApp oficial (Twilio/Meta) e e-mail (Gmail).
- Espelho dos disparos do monorepo, com a resposta do cliente caindo na mesma thread.
- Contexto do título carimbado nos atributos da conversa, no instante do disparo.

**Fora (MVP):**
- Serviço de sync reconciliando identidade entre Twenty e Supabase — decidido contra: o contexto chega no disparo.
- Sincronização bidirecional profunda e painel iframe (Dashboard App) com dado ao vivo — fase 2.
- Motor de disparo em massa dentro do Chatwoot (a cobrança em massa continua no pipeline do monorepo) — fase 2.
- SSO / embutir a central dentro da plataforma interna — fase 2.
- Agente de IA respondendo dentro do Chatwoot.

## Vision

Em 2–3 anos, o Inbox Flash Capital é a **camada de atendimento única de toda a Flash**: todos os canais (WhatsApp, e-mail, e novos como Instagram/webchat) num cockpit só, com contexto de operação ao vivo ao lado de cada conversa, respostas assistidas por IA e automações de roteamento por segmento — sem nunca abrir mão do princípio de que a central espelha e orquestra, mas os dados de negócio moram nos sistemas de domínio.
