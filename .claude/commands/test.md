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
- `docker compose -f deploy/docker-compose.yml config -q` — o compose é válido?
- `docker compose -f deploy/docker-compose.yml ps` — serviços Up + health checks verdes?
- `caddy validate --config deploy/Caddyfile` — se o caddy estiver instalado

Relate: total passando/falhando, arquivos com problema de lint/type, serviços não-saudáveis.

Lembretes do projeto:
- **Sem código = sem pytest.** Story de configuração não inventa teste — o verde dela é o critério
  de aceite verificado ao vivo. Diga isso explicitamente em vez de forçar uma suíte vazia a passar.
- O coração da suíte do EPIC-5 são os testes do **Serviço de Sync**: resolução de identidade
  (E.164 + documento), regra de merge (auto vs. sugestão), **idempotência** do push e **retry com
  backoff**. Toda regra de reconciliação nova = teste novo.
