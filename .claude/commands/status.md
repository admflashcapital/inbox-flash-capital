
> **Escopo: 16 stories** (EPIC-2 e EPIC-5 estão fora). `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).
>
> **Não abrir gate nem story do EPIC-2 ou do EPIC-5** — estão fora do escopo. Use `bash scripts/…` e `docker compose …`.

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
