.PHONY: validate deploy-k8s deploy-docker backup backup-app restore-dry-run restore up bootstrap bootstrap-stage bootstrap-apply

validate:
	bash scripts/validate.sh

up:
	bash scripts/up.sh

# Disaster-recovery rebuild (see config/hosts.yaml + scripts/bootstrap.sh).
#   make bootstrap              # full preview (all stages, dry-run)
#   make bootstrap-stage N=3    # single stage preview
#   make bootstrap-apply N=1    # apply a single stage (stage must support --apply)
bootstrap:
	bash scripts/bootstrap.sh

bootstrap-stage:
	bash scripts/bootstrap.sh --stage $(N)

bootstrap-apply:
	bash scripts/bootstrap.sh --stage $(N) --apply

deploy-k8s:
	bash scripts/deploy-k8s.sh

# deploy-docker: deploy compose stacks on ONE host. You must say which.
#   make deploy-docker HOST=identity
# This is a thin wrapper over bootstrap.sh stage 5, which deploys REMOTELY
# to the host named in config/hosts.yaml (the Makefile itself is not the
# deploy mechanism — see scripts/bootstrap.sh). Host names come from
# config/hosts.yaml; unknown names are refused.
#   identity, files, operations, authentik, immich, apps, archives,
#   paperless, stash, scrutiny, burndev, synology
deploy-docker:
	@test -n "$(HOST)" || (echo "ERROR: specify make deploy-docker HOST=<name> (name from config/hosts.yaml)"; exit 1)
	@bash scripts/bootstrap.sh --stage 5 --only=$(HOST)

backup:
	bash scripts/backup.sh
	bash scripts/backup-app-data.sh

backup-app:
	bash scripts/backup-app-data.sh

restore-dry-run:
	bash scripts/restore-app-data.sh --dry-run

restore:
	bash scripts/restore-app-data.sh --force
