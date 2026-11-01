#!/usr/bin/env bash
# Nightly: mirror this directory (config, DKIM keys, accounts, mailboxes, Roundcube DB; not logs)
# to $BACKUP_DIR/mirror, owned by the calling user, so another machine can pull it with rsync
# (tools/pull-backup.sh). Mail files belong to the container user (uid 5000), so the copy runs
# in a small container.  Cron, e.g.:  30 3 * * * /path/to/docker-mail-stack/backup.sh
set -euo pipefail
cd "$(dirname "$0")"
BACKUP_DIR="${BACKUP_DIR:-$HOME/mail-backups}"
DST="$BACKUP_DIR/mirror"
mkdir -p "$DST"; chmod 700 "$BACKUP_DIR" "$DST"
docker image inspect mail-backup-rsync >/dev/null 2>&1 || \
  printf 'FROM alpine:3\nRUN apk add --no-cache rsync\n' | docker build -q -t mail-backup-rsync - >/dev/null
docker run --rm -v "$PWD":/src:ro -v "$DST":/dst mail-backup-rsync \
  rsync -a --delete --chown="$(id -u):$(id -g)" --exclude /data/logs/ /src/ /dst/
date -u +%FT%TZ > "$DST/.last-backup"
echo "$(date -u +%FT%TZ) ok $(du -sh "$DST" | cut -f1)" >> "$BACKUP_DIR/backup.log"
