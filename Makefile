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

# deploy-docker: deploy compose stacks on ONE host only. You must say which.
#   make deploy-docker HOST=identity
# Host map (source: docs/service-inventory.md, docs/docker-services.md,
# verified 2026-08-13). Unlisted/unknown hosts are refused on purpose so a
# stack can never be deployed onto the wrong LXC.
#   identity (110)    lldap
#   files    (114)    filebrowser-quantum
#   operations (115)  scanopy
#   authentik (118)   authentik
#   immich   (111)    immich
#   apps     (112)    vikunja rackpeek actual-budget tasks-md
#   archives (113)    karakeep
#   paperless (119)   paperless
#   stash    (123)    stash
#   scrutiny (124)    scrutiny-hub
#   burndev           ollama scrutiny-collector
#   synology          scrutiny-collector-synology
deploy-docker:
	@test -n "$(HOST)" || (echo "ERROR: specify make deploy-docker HOST=<label>"; echo "Valid: identity files operations authentik immich apps archives paperless stash scrutiny burndev synology"; exit 1)
	@case "$(HOST)" in \
	  identity)   STACKS="lldap" ;; \
	  files)      STACKS="filebrowser-quantum" ;; \
	  operations) STACKS="scanopy" ;; \
	  authentik)  STACKS="authentik" ;; \
	  immich)     STACKS="immich" ;; \
	  apps)       STACKS="vikunja rackpeek actual-budget tasks-md" ;; \
	  archives)   STACKS="karakeep" ;; \
	  paperless)  STACKS="paperless" ;; \
	  stash)      STACKS="stash" ;; \
	  scrutiny)   STACKS="scrutiny-hub" ;; \
	  burndev)    STACKS="ollama scrutiny-collector" ;; \
	  synology)   STACKS="scrutiny-collector-synology" ;; \
	  *) echo "ERROR: unknown host '$(HOST)'"; echo "Valid: identity files operations authentik immich apps archives paperless stash scrutiny burndev synology"; exit 1 ;; \
	esac; \
	for s in $$STACKS; do \
	  cf=""; \
	  [ -f "docker/$$s/compose.yaml" ] && cf="docker/$$s/compose.yaml"; \
	  [ -f "docker/$$s/docker-compose.yml" ] && cf="docker/$$s/docker-compose.yml"; \
	  if [ -z "$$cf" ]; then echo "ERROR: no compose.yaml/docker-compose.yml in docker/$$s"; exit 1; fi; \
	  echo "== deploying docker/$$s ($$cf) =="; \
	  (cd docker/$$s && docker compose -f "$$cf" up -d) || exit 1; \
	done

backup:
	bash scripts/backup.sh
	bash scripts/backup-app-data.sh

backup-app:
	bash scripts/backup-app-data.sh

restore-dry-run:
	bash scripts/restore-app-data.sh --dry-run

restore:
	bash scripts/restore-app-data.sh --force
