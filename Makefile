.DEFAULT_GOAL := help

.PHONY: help init up down restart logs ps build-image backup upgrade clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*## "}{printf "  %-14s %s\n", $$1, $$2}'

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

upgrade: ## Backup, then pull + recreate the veira container
	./upgrade.sh

clean: ## Stop the stack and remove containers (keeps ./data and ./backup)
	docker compose down --remove-orphans
