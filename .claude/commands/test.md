---
description: Roda testes, lint e as verificações de infra da central
---

Execute o que estiver instalado/existir e relate o resultado (ferramentas do Serviço de Sync vêm do
`.venv` — use `.venv/bin/<tool>` se o venv não estiver ativado):

**Código (Serviço de Sync):**
- `.venv/bin/pytest -q --tb=short` — se houver testes em `sync-service/tests/`
- `.venv/bin/ruff check .`
- `.venv/bin/mypy .` — se mypy estiver instalado

**Infra (quando houver `deploy/`):**
- `make config` — o compose é válido?
- `make ps` — serviços Up + health checks verdes?
- `make check` — invariantes de arquitetura do EPIC-1 (tag fixa `-ce`, banco isolado sem cross-DB,
  usuário não-superusuário, só o Caddy publicando porta, `.env` fora do git)
- `caddy validate --config deploy/Caddyfile` — se o caddy estiver instalado

**Canais (EPIC-2, quando a Evolution estiver no ar):**
- `make fanout` — N8N **e** central recebem o mesmo evento? (AD-5 — o risco nº 1 do MVP)
- `make aquecimento` — o número de prospecção segue **só inbound**, sem campanha e dentro da rampa?
- `make dedup` — há mensagem duplicada no espelho? (idempotência do AD-5)

Relate: total passando/falhando, arquivos com problema de lint/type, serviços não-saudáveis.

Lembretes do projeto:
- **Sem código = sem pytest.** Story de configuração não inventa teste — o verde dela é o critério
  de aceite verificado ao vivo. Diga isso explicitamente em vez de forçar uma suíte vazia a passar.
- O coração da suíte do EPIC-5 são os testes do **Serviço de Sync**: resolução de identidade
  (E.164 + documento), regra de merge (auto vs. sugestão), **idempotência** do push e **retry com
  backoff**. Toda regra de reconciliação nova = teste novo.
