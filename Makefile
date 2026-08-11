.PHONY: validate deploy-k8s deploy-docker backup backup-app restore-dry-run restore up

validate:
	bash scripts/validate.sh

up:
	bash scripts/up.sh

deploy-k8s:
	bash scripts/deploy-k8s.sh

deploy-docker:
	cd docker/caddy       && docker compose up -d
	cd docker/immich      && docker compose up -d
	cd docker/vikunja     && docker compose up -d
	cd docker/scanopy     && docker compose up -d
	cd docker/actual-budget && docker compose up -d
	cd docker/rackpeek    && docker compose up -d
	cd docker/tasks-md    && docker compose up -d
	cd docker/lldap       && docker compose up -d
	cd docker/karakeep    && docker compose up -d
	cd docker/downtify    && docker compose up -d
	cd docker/llmeter     && docker compose up -d
	cd docker/ollama      && docker compose up -d
	cd docker/filebrowser-quantum && docker compose up -d

backup:
	bash scripts/backup.sh
	bash scripts/backup-app-data.sh

backup-app:
	bash scripts/backup-app-data.sh

restore-dry-run:
	bash scripts/restore-app-data.sh --dry-run

restore:
	bash scripts/restore-app-data.sh --force
