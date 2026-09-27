#!/usr/bin/env bash
# Take a consistent, encrypted-at-rest backup of a running Veira Seal
# instance and drop it into ./backup/. Safe to run on a live server (the
# backup is a SQLite VACUUM INTO snapshot, not a raw file copy).
#
# Usage: ./backup.sh
# Cron:  */30 * * * * cd /path/to/veiraseal-deploy && ./backup.sh >>backup/backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p backup

# The container has no shell (distroless) so there's no `rm`/`mv` inside it
# to clean up with — instead write straight into ./data, which is the same
# bind mount as the container's /data, and move it from the host side.
docker compose exec -T veira /veira server backup -db /data/veira.db -out "/data/backup-${stamp}.db"
mv "data/backup-${stamp}.db" "backup/veira-${stamp}.db"

echo "backup: backup/veira-${stamp}.db"

# Keep the last 30 backups only; the vault's own recovery key and key file
# are what actually protect this data, so pruning old snapshots is safe.
ls -1t backup/veira-*.db 2>/dev/null | tail -n +31 | xargs -r rm -f
