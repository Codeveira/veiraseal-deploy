#!/usr/bin/env bash
# Dependency-free sanity checks for this deploy stack: shell scripts parse,
# and docker-compose.yml is valid Compose config. Doesn't need Docker
# running, just the `docker compose` CLI. Run before publishing changes.
#
# Usage: ./check.sh
set -euo pipefail
cd "$(dirname "$0")"

fail=0

for f in backup.sh upgrade.sh; do
    if bash -n "$f"; then
        echo "ok: $f parses"
    else
        echo "FAIL: $f has a syntax error"
        fail=1
    fi
done

# `docker compose config` needs a .env to resolve ${VARS}; use .env.example
# (copied to a throwaway file, never touching a real .env) so this check
# has no side effects and needs no secrets.
tmp_env="$(mktemp)"
cp .env.example "$tmp_env"
if docker compose --env-file "$tmp_env" config >/dev/null; then
    echo "ok: docker-compose.yml is valid"
else
    echo "FAIL: docker-compose.yml did not validate"
    fail=1
fi
rm -f "$tmp_env"

if [ "$fail" -eq 0 ]; then
    echo "all checks passed"
else
    exit 1
fi
