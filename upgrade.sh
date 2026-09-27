#!/usr/bin/env bash
# Zero-surprise upgrade: back up first, then pull the new image and
# recreate the container. Refuses to continue if the backup step fails.
#
# Usage: ./upgrade.sh [IMAGE_TAG]
#   ./upgrade.sh            # pull whatever IMAGE_TAG is set to in .env
#   ./upgrade.sh 0.2.0      # upgrade to a specific tag
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -ge 1 ]; then
    tag="$1"
    if grep -q '^IMAGE_TAG=' .env 2>/dev/null; then
        sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=${tag}/" .env
    else
        echo "IMAGE_TAG=${tag}" >>.env
    fi
    echo "IMAGE_TAG set to ${tag}"
fi

echo "==> backing up before upgrade"
./backup.sh

echo "==> pulling image"
docker compose pull veira

echo "==> recreating container"
docker compose up -d veira

echo "==> waiting for it to come back healthy"
for _ in $(seq 1 30); do
    status="$(docker compose ps --format '{{.Health}}' veira 2>/dev/null || true)"
    if [ "$status" = "healthy" ]; then
        echo "upgrade complete: veira is healthy"
        exit 0
    fi
    sleep 2
done

echo "warning: veira did not report healthy within 60s; check 'docker compose logs veira'" >&2
exit 1
