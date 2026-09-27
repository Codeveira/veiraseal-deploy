#!/usr/bin/env bash
# Sanity checks for this deploy stack: shell scripts parse, docker-compose.yml
# and the monitoring overlay are valid Compose config, and the Grafana
# dashboard is valid JSON. Doesn't need Docker running, just the
# `docker compose` CLI and python3 (already needed nowhere else here, but
# ubiquitous). Run before publishing changes.
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

# The monitoring overlay requires GRAFANA_ADMIN_PASSWORD (compose's `:?`
# guard); .env.example deliberately leaves it commented out (it's optional),
# so set a throwaway value just for this validation pass.
echo "GRAFANA_ADMIN_PASSWORD=check" >>"$tmp_env"
if docker compose --env-file "$tmp_env" -f docker-compose.yml -f docker-compose.monitoring.yml config >/dev/null; then
    echo "ok: docker-compose.monitoring.yml merges and validates"
else
    echo "FAIL: docker-compose.monitoring.yml did not validate"
    fail=1
fi
rm -f "$tmp_env"

if python3 -c "import json; json.load(open('monitoring/grafana/dashboards/veiraseal.json'))" 2>/dev/null; then
    echo "ok: veiraseal.json dashboard is valid JSON"
else
    echo "FAIL: monitoring/grafana/dashboards/veiraseal.json is not valid JSON"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "all checks passed"
else
    exit 1
fi
