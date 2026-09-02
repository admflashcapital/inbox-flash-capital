
> **Escopo: 16 stories**, nos épicos 1, 3, 4 e 6. `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).


---
description: Roda testes, lint e as verificações de infra da central
---

Execute o que estiver instalado/existir e relate o resultado.

**Código:** **não há suíte de testes neste repo**, nem código de aplicação — o Chatwoot é imagem
oficial sem fork (AD-7). O verde aqui são os verificadores de `scripts/`.

**Infra:**
- `docker compose config --quiet` — o compose é válido?
- `docker compose ps` — serviços Up + health checks verdes?
- `bash scripts/verificar-invariantes.sh` — invariantes de arquitetura (tag fixa `-ce`, banco isolado
  sem cross-DB, usuário não-superusuário, **nada publicando fora de `127.0.0.1`**, `.env` fora do
  git, simetria `.env` × `.env.example` nos dois sentidos, e a prova viva da API da central)
- `bash -n scripts/*.sh` — sintaxe dos scripts
- `docker network inspect flash-espelho --format '{{range .Containers}}{{.Name}} {{end}}'` —
  precisa listar **exatamente** `fastapi_api` e `inbox-flash-capital-chatwoot-web-1`

**Canal Oficial (EPIC-3 — é o canal de DINHEIRO, não pule):**
- `bash scripts/verificar-canal-oficial.sh` — `medium=whatsapp` (janela de 24h ativa), templates Meta sincronizados, número em
  `whatsapp:+E164`, zero campanha (AD-6), `RELAY_TOKEN` presente (é contrato com o monorepo; **nada o exige na borda** enquanto não houver ingresso)
- `bash scripts/conectar-twilio.sh --status` — a inbox oficial que está valendo

**Canal E-mail (EPIC-4, quando o OAuth do Gmail estiver concluído):**
- `bash scripts/verificar-canal-email.sh` — `provider=google`, **`refresh_token` gravado** (sem ele o canal morre em 1h, calado)
  e o job `trigger_imap_email_inboxes_job` registrado (é ele que busca o e-mail **e** mantém o token
  fresco para o SMTP de saída)
- `bash scripts/conectar-gmail.sh --status` — a inbox de e-mail que está valendo

Relate: total passando/falhando, arquivos com problema de lint/type, serviços não-saudáveis.

Lembretes do projeto:
- **Sem código = sem pytest.** Story de configuração não inventa teste — o verde dela é o critério
  de aceite verificado ao vivo. Diga isso explicitamente em vez de forçar uma suíte vazia a passar.
- **O contexto da conversa é testado no MONOREPO**, não aqui: quem carimba os `custom_attributes`
  é o `chatwoot_mirror.py` (AD-13). O teste que importa é o do carimbo em conversa **reusada** —
  `_garantir_conversa` tem duas saídas e o reuso é o caminho comum.
