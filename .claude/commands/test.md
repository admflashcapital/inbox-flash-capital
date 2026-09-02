
> **Reescopo 2026-09-02** — EPIC-2 (Evolution) e EPIC-5 (Sync) **cancelados**; Caddy, Makefile e a rede `flash-canais` saem (AD-10..AD-13 em `docs/architecture.md`). O que segue vale até a Fase 1 rodar.
>
> **Não abrir gate nem story do EPIC-2 ou do EPIC-5** — os dois foram cancelados; o escopo vigente é de **16 stories**. Os alvos `make …` continuam válidos até a Fase 1.3, quando viram `bash scripts/…`.

---
description: Roda testes, lint e as verificações de infra da central
---

Execute o que estiver instalado/existir e relate o resultado (ferramentas do Serviço de Sync vêm do
`.venv` — use `.venv/bin/<tool>` se o venv não estiver ativado):

**Código (Serviço de Sync):**
- `.venv/bin/pytest -q --tb=short` — se houver testes em `sync-service/tests/`
- `.venv/bin/ruff check .`
- `.venv/bin/mypy .` — se mypy estiver instalado

**Infra (quando houver a raiz do repo):**
- `docker compose config` — o compose é válido?
- `docker compose ps` — serviços Up + health checks verdes?
- `bash scripts/verificar-invariantes.sh` — invariantes de arquitetura do EPIC-1 (tag fixa `-ce`, banco isolado sem cross-DB,
  usuário não-superusuário, só o Caddy publicando porta, `.env` fora do git)
- `caddy validate --config (removido — Caddy)` — se o caddy estiver instalado

**Canal Prospecção (EPIC-2, quando a Evolution estiver no ar):**
- `(removido — Evolution)` — N8N **e** central recebem o mesmo evento? (AD-5 — o risco nº 1 do MVP)
- `(removido — Evolution)` — o número de prospecção segue **só inbound**, sem campanha e dentro da rampa?
- `(removido — Evolution)` — há mensagem duplicada no espelho? (idempotência do AD-5)

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
