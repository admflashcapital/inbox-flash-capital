# ═══════════════════════════════════════════════════════════════════
# Inbox Flash Capital — atalhos de operação da central (EPIC-1)
# ═══════════════════════════════════════════════════════════════════
# A stack vive em `deploy/`. Todo alvo daqui roda o compose de lá, então
# você não precisa lembrar do -f nem entrar na pasta.
# Runbooks: docs/runbook-deploy.md · runbook-upgrade.md · runbook-backup.md
.DEFAULT_GOAL := help

COMPOSE := docker compose -f deploy/docker-compose.yml --env-file deploy/.env

.PHONY: help up down restart logs ps config check smoke migrate backup restore-check retencao evolution evolution-status

help: ## Lista os comandos disponíveis
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

up: ## Sobe a central inteira e espera ficar saudável (STORY-1.1)
	$(COMPOSE) up -d --wait

down: ## Para a stack (mantém os dados nos volumes)
	$(COMPOSE) down

restart: ## Reinicia os containers (prova de persistência — critério da 1.1)
	$(COMPOSE) restart

logs: ## Logs em tempo real. Uso: make logs s=chatwoot-web
	$(COMPOSE) logs -f $(s)

ps: ## Estado dos containers
	$(COMPOSE) ps

config: ## Valida o compose (sintaxe + interpolação do .env)
	$(COMPOSE) config --quiet && echo "compose OK"

check: ## Verifica as invariantes de arquitetura (AD-7/8/9) — rode antes de commitar
	deploy/scripts/verificar-invariantes.sh

smoke: ## Semeia dados, reinicia e prova a persistência (dev/staging — STORY-1.1)
	deploy/scripts/smoke-test.sh

evolution: ## Liga o número de prospecção à central (STORY-2.1)
	deploy/scripts/conectar-evolution.sh

evolution-status: ## Mostra a integração Evolution↔central que está valendo
	deploy/scripts/conectar-evolution.sh --status

migrate: ## Roda as migrações do Chatwoot (usado no upgrade — STORY-1.3)
	$(COMPOSE) run --rm chatwoot-init

backup: ## Backup do banco + anexos (STORY-1.4)
	deploy/scripts/backup.sh

restore-check: ## Restaura o último backup num ambiente limpo e valida (STORY-1.4)
	deploy/scripts/restore.sh --verificar

retencao: ## Simula o expurgo de conversas antigas (LGPD). Apagar: scripts/retencao-conversas.sh --executar
	deploy/scripts/retencao-conversas.sh --simular
