#!/usr/bin/env bash
set -euo pipefail

# Pre-flight validation for the homelab repo.
# Run before deploying to catch common issues: syntax errors, secrets in
# tracked files, missing env files, unpinned images, stale mounts.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

PASS=0
FAIL=0

ok()   { echo "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }

header() { echo ""; echo "── $* ──"; }

# ── Shell syntax ──────────────────────────────────────────────────────────────

header "Shell syntax (bash -n)"
for f in scripts/*.sh; do
  if bash -n "$f" 2>&1; then
    ok "$f"
  else
    fail "$f (syntax error)"
  fi
done

# ── shellcheck lint ──────────────────────────────────────────────────────────
if command -v shellcheck >/dev/null 2>&1; then
  header "shellcheck lint"
  for f in scripts/*.sh; do
    if shellcheck -x -S error "$f" 2>&1; then
      ok "$f"
    else
      fail "$f (shellcheck warnings)"
    fi
  done
fi

# ── YAML parse / lint ────────────────────────────────────────────────────────

header "YAML parse"
YAML_FILES=$(find . -path './docker/*/data' -prune -o \( -name '*.yml' -o -name '*.yaml' \) -print | grep -v '.disabled$' | sort)

if command -v yamllint >/dev/null 2>&1; then
  for f in $YAML_FILES; do
    if yamllint -d '{extends: relaxed, rules: {line-length: disable}}' "$f" >/dev/null 2>&1; then
      ok "$f"
    else
      fail "$f (yamllint)"
    fi
  done
elif command -v python3 >/dev/null 2>&1; then
  for f in $YAML_FILES; do
    # Skip K8s manifests that use Go template substitution ({{ ... }})
    if grep -q '{{.*}}' "$f" 2>/dev/null; then
      ok "$f (has template vars, skipping YAML parse)"
      continue
    fi
    if python3 -c "
import yaml, sys
try:
    list(yaml.safe_load_all(open('$f')))
except Exception as e:
    sys.exit(1)
" 2>/dev/null; then
      ok "$f"
    else
      fail "$f (YAML parse)"
    fi
  done
else
  echo "  SKIP: no yamllint or python3 available"
fi

# ── Unpinned Docker images ───────────────────────────────────────────────────

header "Unpinned Docker images"
UNPINNED=$(grep -Hn 'image:.*:latest' docker/*/compose.yaml 2>/dev/null | grep -v 'TODO' || true)
if [ -z "$UNPINNED" ]; then
  ok "No unpinned :latest images (without TODO)"
else
  fail "Unpinned images found:$UNPINNED"
fi

UNTAGGED=$(grep -Hn 'image:' docker/*/compose.yaml 2>/dev/null | grep -v ':' | grep -v 'TODO' | grep 'image:' || true)
# Filter out lines that are comments
if [ -n "$UNTAGGED" ]; then
  fail "Untagged images found:$UNTAGGED"
else
  ok "No untagged images"
fi

DEVELOP=$(grep -Hn ':develop' docker/*/compose.yaml 2>/dev/null || true)
if [ -z "$DEVELOP" ]; then
  ok "No :develop images"
else
  fail ":develop images found:$DEVELOP"
fi

# ── Missing .env / .env.example ──────────────────────────────────────────────

header "Environment files"
for stack in docker/*/; do
  stack_name="$(basename "$stack")"
  if [ -f "$stack/.env" ]; then
    ok "$stack_name: .env present"
  elif [ -f "$stack/.env.example" ]; then
    ok "$stack_name: .env absent but .env.example present"
  elif grep -q '\${' "$stack/compose.yaml" 2>/dev/null; then
    # Compose file references env vars but no .env or .env.example exists
    fail "$stack_name: compose.yaml uses env vars but no .env or .env.example"
  else
    ok "$stack_name: no env vars needed"
  fi
done

# ── NAS mount ─────────────────────────────────────────────────────────────────

header "NAS mount"
if mountpoint -q /mnt/syn 2>/dev/null; then
  ok "/mnt/syn mounted"
else
  fail "/mnt/syn not mounted"
fi

# ── Docker compose config parse ──────────────────────────────────────────────

header "Docker compose config"
if command -v docker >/dev/null 2>&1; then
  for f in docker/*/compose.yaml; do
    stack_dir="$(dirname "$f")"
    stack="$(basename "$stack_dir")"
    if docker compose -f "$f" config --quiet 2>/dev/null; then
      ok "$stack"
    else
      fail "$stack (docker compose config failed)"
    fi
  done
else
  echo "  SKIP: docker not available"
fi

# ── K8s dry-run ──────────────────────────────────────────────────────────────

header "K8s manifest dry-run"
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  for f in $(find kubernetes -name '*.yml' -not -name '*.disabled' -not -name '*.example.yml' -not -name '*-values.yml' -not -name 'prometheus-additional-scrape.yml' -not -path '*/policies/*' | sort); do
    if kubectl apply --dry-run=client -f "$f" >/dev/null 2>&1; then
      ok "$f"
    else
      fail "$f"
    fi
  done
  # Policies are allowed to fail dry-run (NetworkPolicy needs running cluster)
  for f in $(find kubernetes/policies -name '*.yml' | sort); do
    if kubectl apply --dry-run=client -f "$f" >/dev/null 2>&1; then
      ok "$f"
    else
      echo "  WARN  $f (dry-run issue, may be cluster-only)"
    fi
  done
else
  echo "  SKIP: kubectl not available or no cluster access"
fi

# ── Secret scan ───────────────────────────────────────────────────────────────

header "Secret scan (API keys / default passwords in tracked files)"
# Check for hex API key patterns (Sonarr-style) and default passwords
SECRETS=$(git grep -n -E '(key|password|token|secret):\s*[a-f0-9]{20,}' -- '*.yml' '*.yaml' 2>/dev/null || true)
SECRETS_EXAMPLE=$(git grep -n -E '(key|password|token|secret):\s*[a-f0-9]{20,}' -- '*example*' 2>/dev/null || true)
# Remove example files from findings
REAL_SECRETS=$(comm -23 <(echo "$SECRETS" | sort) <(echo "$SECRETS_EXAMPLE" | sort) 2>/dev/null || true)
if [ -z "$REAL_SECRETS" ]; then
  ok "No hex API keys in tracked non-example files"
else
  fail "Possible secrets in tracked files:$REAL_SECRETS"
fi

# Check for changeme / default passwords in tracked files
CHANGEME=$(git grep -n -i -E '(changeme|change-me|replace-me|your-.*-here)' -- '*.yml' '*.yaml' 2>/dev/null | grep -v '.example' | grep -v '.disabled' | grep -v 'compose.yaml' || true)
if [ -z "$CHANGEME" ]; then
  ok "No default/placeholder passwords in tracked config"
else
  fail "Default/placeholder values found:$CHANGEME"
fi

# Docker Compose KEY=value secret check (long base64/hex strings in env vars)
header "Docker Compose secrets (long key/password values)"
COMPOSE_SECRETS=$(git grep -n -E '-\s+(PRIVATE_KEY|PRESHARED_KEY|SECRET_KEY|API_KEY|ACCESS_KEY|TOKEN)\s*=\s*[A-Za-z0-9+/=_-]{20,}' -- 'docker/*/compose.yaml' 2>/dev/null || true)
COMPOSE_PW=$(git grep -n -E '-\s+(PASSWORD|PASSWD|DB_PASS)\s*=\s*[A-Za-z0-9!@#$%^&*()_+=-]{6,}' -- 'docker/*/compose.yaml' 2>/dev/null | grep -v '\${' || true)
COMPOSE_REAL="${COMPOSE_SECRETS}
${COMPOSE_PW}"
COMPOSE_REAL=$(echo "$COMPOSE_REAL" | grep -v '^$' || true)
if [ -z "$COMPOSE_REAL" ]; then
  ok "No long secret values in compose.yaml files"
else
  fail "Hardcoded secrets in compose.yaml (use env vars instead):$COMPOSE_REAL"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo "  Validation: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
