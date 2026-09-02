
> **Escopo: 16 stories**, nos épicos 1, 3, 4 e 6. `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).

---
description: Verifica o gate de saída de um épico. Uso: /gate EPIC-1
---

Verifique o gate do épico $ARGUMENTS conforme a linha **Gate** dele em `PROGRESS.md`.

1. Confirme que TODAS as stories do épico estão `[x]`.
2. Rode a verificação correspondente **ao vivo** — o gate não passa por leitura de código. Exemplos:
   - **EPIC-1:** `docker compose up -d --wait && docker compose ps` (todos Up + health verdes); UI
     responde em `127.0.0.1:${CHATWOOT_HOST_PORT}` e **nada** publica fora da loopback; restart
     preserva conversas; imagem com tag fixa (grep por `latest` deve dar zero); restore de backup num
     ambiente limpo recompõe conversas + anexos.
   - **EPIC-3:** inbound no número oficial cai na inbox; resposta dentro da janela de 24h sai;
     disparo do monorepo aparece como outbound na thread correta.
   - **EPIC-4:** e-mail vira conversa; resposta volta na mesma thread; contato não duplica; a
     conversa carrega os `custom_attributes` carimbados pelo monorepo no disparo (AD-13), inclusive
     quando a thread foi **reusada**, não só quando foi criada.
   - **EPIC-6:** papéis negam acesso indevido; retenção configurada; alerta de conexão dispara.
3. Reporte **PASS** ou **FAIL** com a **evidência** (saída do comando, print do estado, id da
   mensagem que chegou). Gate sem evidência é FAIL.
4. **Coerência de docs (no PASS):** o fechamento de épico é o checkpoint para alinhar os `docs/` à
   realidade as-built. Confira se algum desvio do épico precisa de nota em
   `docs/architecture.md`/`docs/prd.md` e atualize a seção "Estado atual" do `CLAUDE.md` raiz + o
   "Registro de sessões" do `PROGRESS.md`.

Não avance para o próximo épico sem PASS — os gates existem por razão.
