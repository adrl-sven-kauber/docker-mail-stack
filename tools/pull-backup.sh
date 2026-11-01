#!/usr/bin/env bash
# Run on ANOTHER machine: pull the server's mirror (made by backup.sh) into dated snapshots.
# Unchanged files are hard-linked to the previous snapshot, so a day costs only what changed.
# Usage: pull-backup.sh user@server [remote-mirror-dir] [local-dir] [days-to-keep]
#   cron, e.g.: 30 4 * * * SSH_AUTH_SOCK= /path/pull-backup.sh me@mail.example.com
# Uses one SSH connection per run (friendly to fail2ban). The log says STALE if the mirror is old.
set -euo pipefail
SERVER="${1:?usage: pull-backup.sh user@server [remote-mirror-dir] [local-dir] [days]}"
REMOTE="${2:-mail-backups/mirror}"
DEST="${3:-$HOME/backups/mail}"
KEEP="${4:-30}"
SNAP="$DEST/snapshots"; LOG="$DEST/backup.log"
mkdir -p "$SNAP"; chmod 700 "$DEST"
TODAY=$(date -u +%F)
LAST=$(find "$SNAP" -mindepth 1 -maxdepth 1 -type d -name '20*' ! -name "$TODAY" | sort | tail -1)
TMP="$SNAP/.incoming-$TODAY"
rm -rf "$TMP"
if rsync -a --delete -e "ssh -o BatchMode=yes -o ConnectTimeout=20" ${LAST:+--link-dest="$LAST"} \
     "$SERVER:$REMOTE/" "$TMP/"; then
  rm -rf "${SNAP:?}/$TODAY"; mv "$TMP" "$SNAP/$TODAY"
  STAMP=$(cat "$SNAP/$TODAY/.last-backup" 2>/dev/null || echo unknown)
  AGE_H=$(( ( $(date -u +%s) - $(date -u -d "$STAMP" +%s 2>/dev/null || echo 0) ) / 3600 ))
  [ "$AGE_H" -le 36 ] && S=ok || S="STALE mirror (made $STAMP)"
  N=$(find "$SNAP/$TODAY/data/mail" \( -path '*/cur/*' -o -path '*/new/*' \) -type f 2>/dev/null | wc -l)
  echo "$(date -u +%FT%TZ) $S snapshot=$TODAY messages=$N" >> "$LOG"
else
  echo "$(date -u +%FT%TZ) FAILED rsync from $SERVER" >> "$LOG"; rm -rf "$TMP"; exit 1
fi
find "$SNAP" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | head -n -"$KEEP" | xargs -r rm -rf
