
> **Escopo: 19 stories** no inventário, das quais **11 vivas** (épicos 1, 3, 4 e 6) — os épicos 2 e 5 foram cancelados. `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).


---
description: Estado atual do projeto — épico, progresso, próxima story
---

Leia `PROGRESS.md` e retorne, em PT-BR:

- **Épico atual** — o primeiro com stories pendentes
- **Progresso** — X de Y stories `[x]` no épico atual, e no total (de 19)
- **Próxima story** — id + título + os FRs que ela realiza
- **Gate do épico atual** — o critério da linha **Gate** desse épico
- **Bloqueadores** — qualquer story marcada `[!]`, e se o épico depende de outro ainda aberto
  (EPIC-1 bloqueia tudo; os canais 3 e 4 correm em paralelo; o 6 fecha o MVP)
