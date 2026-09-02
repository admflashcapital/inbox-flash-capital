
> **Escopo: 16 stories** (EPIC-2 e EPIC-5 estão fora). `compose.yaml`, `.env` e `scripts/` na raiz; `docker compose up -d --wait` é o comando único; a central escuta em `127.0.0.1:3001` e fala com o monorepo pela rede `flash-espelho`. Decisões em `docs/architecture.md` (AD-10..AD-13).
>
> **Não abrir gate nem story do EPIC-2 ou do EPIC-5** — estão fora do escopo. Use `bash scripts/…` e `docker compose …`.

---
description: Roda testes, lint e as verificações de infra da central
---

Execute o que estiver instalado/existir e relate o resultado (ferramentas do Serviço de Sync vêm do
`.venv` — use `.venv/bin/<tool>` se o venv não estiver ativado):

**Código (Serviço de Sync):**
**Não há suíte de testes neste repo** — nem código de aplicação. O Chatwoot é imagem oficial sem
fork (AD-7) e o Serviço de Sync foi cancelado (AD-13). O verde aqui são os verificadores.

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
  `whatsapp:+E164`, zero campanha (AD-6), `/twilio/callback` fechado pelo `RELAY_TOKEN`
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
- O coração da suíte do EPIC-5 são os testes do **Serviço de Sync**: resolução de identidade
  (E.164 + documento), regra de merge (auto vs. sugestão), **idempotência** do push e **retry com
  backoff**. Toda regra de reconciliação nova = teste novo.
