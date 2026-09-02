
> **Reescopo 2026-09-02** — EPIC-2 (Evolution) e EPIC-5 (Sync) **cancelados**; Caddy, Makefile e a rede `flash-canais` saem (AD-10..AD-13 em `docs/architecture.md`). O que segue vale até a Fase 1 rodar.
>
> **Não abrir gate nem story do EPIC-2 ou do EPIC-5** — os dois foram cancelados; o escopo vigente é de **16 stories**. Os alvos `make …` continuam válidos até a Fase 1.3, quando viram `bash scripts/…`.

---
description: Estado atual do projeto — épico, progresso, próxima story
---

Leia `PROGRESS.md` e retorne, em PT-BR:

- **Épico atual** — o primeiro com stories pendentes
- **Progresso** — X de Y stories `[x]` no épico atual, e no total (de 19)
- **Próxima story** — id + título + os FRs que ela realiza
- **Gate do épico atual** — o critério da linha **Gate** desse épico
- **Bloqueadores** — qualquer story marcada `[!]`, e se o épico depende de outro ainda aberto
  (EPIC-1 bloqueia tudo; EPIC-5 precisa de ≥1 canal vivo)
