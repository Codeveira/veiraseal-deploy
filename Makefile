.DEFAULT_GOAL := help

.PHONY: help check init up down restart logs ps build-image backup deploy upgrade clean monitoring-up monitoring-down

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*## "}{printf "  %-14s %s\n", $$1, $$2}'

check: ## Validate scripts + docker-compose.yml (no Docker daemon needed to run, only the CLI)
	./check.sh

init: ## Create the vault (run once; prints the recovery key — save it offline)
	mkdir -p data backup
	chmod 777 data # image runs as a fixed distroless nonroot UID (65532)
	docker compose run --rm veira-init

up: ## Start (or restart) the veira service in the background
	docker compose up -d veira

down: ## Stop the stack
	docker compose down

restart: down up ## Restart the veira service

logs: ## Follow the veira service logs
	docker compose logs -f veira

ps: ## Show container + health status
	docker compose ps

build-image: ## Build the image from ../veiraseal instead of pulling one
	docker compose build veira

backup: ## Snapshot the vault into ./backup/
	./backup.sh

# The one target meant to be the whole deploy operation, so a human or a
# CI/CD job never has to assemble the steps themselves: backs up ./data
# (via backup.sh), pulls IMAGE_TAG from .env (or the tag set by
# `./upgrade.sh <tag>` beforehand), recreates the veira container, and
# polls `docker compose ps` until the healthcheck reports healthy (or
# warns after 60s without one). Safe to re-run; refuses to continue if the
# backup step fails, and refuses to start if another backup.sh/upgrade.sh
# is already running here (deploy.lock).
deploy: ## Deploy an update: backup, pull IMAGE_TAG, recreate, wait for healthy
	./upgrade.sh

upgrade: deploy ## Alias for `deploy` (kept for anyone/any script still typing `make upgrade`)

clean: ## Stop the stack and remove containers (keeps ./data and ./backup)
	docker compose down --remove-orphans

monitoring-up: ## Start the optional Prometheus + Grafana stack (needs GRAFANA_ADMIN_PASSWORD in .env, and an Extended+ licence)
	docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d prometheus grafana

monitoring-down: ## Stop the monitoring stack
	docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down
