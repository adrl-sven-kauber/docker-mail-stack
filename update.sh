#!/usr/bin/env bash
# Pull new releases within the pinned version lines (compose.yaml) and recreate changed containers.
# Run weekly from cron, e.g.:  17 4 * * 0 /path/to/docker-mail-stack/update.sh
# Log: data/logs/update.log
set -euo pipefail
cd "$(dirname "$0")"
{
  echo "== $(date -u +%FT%TZ)"
  docker compose pull -q
  docker compose up -d --remove-orphans
  docker image prune -f >/dev/null      # old images only; never touches volumes
  docker compose images
} >> data/logs/update.log 2>&1
