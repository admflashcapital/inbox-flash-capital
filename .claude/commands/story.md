
> **Escopo: 16 stories** (EPIC-2 e EPIC-5 estão fora). `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).
>
> **Não abrir gate nem story do EPIC-2 ou do EPIC-5** — estão fora do escopo. Use `bash scripts/…` e `docker compose …`.

---
description: Carrega o contexto de uma story para implementar. Uso: /story 2.1
---

Leia a seção **Story $ARGUMENTS** em `docs/epics-and-stories.md` (as stories vivem todas nesse
arquivo — não há um arquivo por story).

Depois leia `.claude/memory/conventions.md`, `.claude/memory/decisions.md`,
`.claude/memory/security.md` e `.claude/memory/skills.md`.
Releia a **regra de ouro** no CLAUDE.md raiz (o Chatwoot é espelho, nunca fonte da verdade) e o
AD correspondente aos FRs da story em `docs/architecture.md`.

Responda, em PT-BR:

1. **O que será implementado** (3 linhas) e **quais FRs/ADs** a story realiza
2. **Natureza da story** — declare qual das duas:
   - **Código** (scripts, seed, verificadores): TDD obrigatório → siga o item 4
   - **Configuração/infra** (subir container, conectar inbox, configurar label/papel/retenção):
     não force pytest. O "verde" é o **critério de aceite verificado ao vivo** + o artefato
     versionado (`compose.yaml`, `scripts/`, `.env.example`, runbook em `docs/`)
3. **Arquivos a criar/modificar** — e, se a story exige passo manual fora do repo (criar app no
   Google, cadastrar template Meta na Twilio, cadastrar redirect URI), **liste o passo manual** e
   diga em qual runbook de `docs/` ele será documentado
4. **Skills a acionar** — pelo roteador (`.claude/memory/skills.md`): as do épico desta story +
   as transversais aplicáveis
5. **O primeiro teste / a primeira verificação** — o RED do ciclo TDD (story de código) ou o
   comando/checagem que prova o critério de aceite (story de configuração)

Aguarde a confirmação do Vitor antes de implementar.
