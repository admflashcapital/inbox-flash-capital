---
description: Encerra a story, atualiza PROGRESS.md + docs e commita. Uso: /done 2.1
---

Para encerrar a STORY-$ARGUMENTS:

1. **Verde antes de commitar:**
   - Story de **código** (Serviço de Sync): `pytest -q --tb=short` — se falhar, PARE e corrija.
   - Story de **configuração/infra**: confirme o critério de aceite **ao vivo** (a UI responde, a
     mensagem chegou na inbox, o restore recompôs os dados) e que o artefato foi versionado
     (a raiz do repo, `docs/`, `.env.example` sincronizado). Sem evidência, não encerre.
   - Segredo novo? Ele entra no `.env` (local) e no `.env.example` (placeholder + comentário) —
     **nunca** o valor no repo, no chat ou no runbook.

2. **PROGRESS.md:** mude `[ ]` → `[x]` na linha da STORY-$ARGUMENTS e atualize o "Progresso total".

3. **Documentar (NÃO pule — evita o gap de docs desatualizadas):**
   - **Registro de sessões** (`PROGRESS.md`): adicione/atualize a linha do dia com o que a story
     entregou (1 frase).
   - **Passo manual?** Se a story dependeu de configuração fora do repo (QR da Evolution, app no
     Google, template Meta na Twilio, DNS), documente no runbook de `docs/` — senão o conhecimento
     morre nesta sessão.
   - **Desvio as-built?** Se a story divergiu de `docs/architecture.md` (provider diferente,
     comportamento inesperado, decisão nova): adicione uma **nota as-built** no doc relevante — sem
     reescrever a spec de intenção — e grave uma **memória** se for reutilizável.
   - **CLAUDE.md (raiz):** se a story fechou um épico ou mudou a próxima pendente, atualize a seção
     "Estado atual do repositório".
   - **Dívida técnica** (`PROGRESS.md`): registre o que ficou pendente e marque o que foi resolvido.

4. **Commit (uma story = um commit):**
   `git add -A && git commit -m "feat(EPIC-N): STORY-$ARGUMENTS — <descrição>"`
   O hook `commit-guard.sh` roda gitleaks + pytest automaticamente — não commita com secret ou
   teste falhando.

5. Pegue o hash (`git rev-parse --short HEAD`) e preencha a coluna **Commit** da story no
   `PROGRESS.md` (entra no próximo commit).

6. Mostre a próxima story pendente (`/status`).
