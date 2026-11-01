#!/usr/bin/env bash
# Create rspamd DKIM keys for one or more domains and (re)write the signing config for ALL
# domains that have a key. Prints the DNS TXT records to publish.
#   tools/add-dkim.sh example.com example.org        (selector: $DKIM_SELECTOR, default "mail")
# Why: `setup config dkim domain a.com,b.com` in rspamd mode creates ONE broken key named
# "a.com,b.com", and each per-domain run overwrites dkim_signing.conf with only its own domain.
set -euo pipefail
cd "$(dirname "$0")/.."
SEL="${DKIM_SELECTOR:-mail}"
C="${MAILSERVER:-mailserver}"          # container name
[ $# -ge 1 ] || { echo "usage: $0 domain [domain...]" >&2; exit 1; }
for d in "$@"; do
  # Never replace an existing key: its public half is already in DNS.
  if docker exec "$C" test -f "/tmp/docker-mailserver/rspamd/dkim/rsa-2048-$SEL-$d.private.txt"; then
    echo "$d: key with selector $SEL exists, kept"
  else
    docker exec "$C" setup config dkim keysize 2048 selector "$SEL" domain "$d" </dev/null >/dev/null 2>&1
  fi
done
docker exec -i "$C" sh -s "$SEL" <<'SH'
set -e
SEL="$1"; DIR=/tmp/docker-mailserver/rspamd/dkim
OUT=/tmp/docker-mailserver/rspamd/override.d/dkim_signing.conf
{
  echo '# Written by tools/add-dkim.sh: one entry per domain with a key in rspamd/dkim/.'
  echo 'enabled = true;'
  echo 'sign_authenticated = true;'
  echo 'sign_local = false;'
  echo 'try_fallback = false;'
  echo 'use_domain = "header";'
  echo 'use_redis = false;'
  echo 'use_esld = true;'
  echo 'allow_username_mismatch = true;'
  echo 'check_pubkey = true;'
  echo 'domain {'
  for k in "$DIR"/rsa-*-"$SEL"-*.private.txt; do
    d=${k##*-"$SEL"-}; d=${d%.private.txt}
    case "$d" in *,*) continue;; esac
    printf '    %s {\n        path = "%s";\n        selector = "%s";\n    }\n' "$d" "$k" "$SEL"
  done
  echo '}'
} > "$OUT"
SH
docker exec "$C" supervisorctl restart rspamd >/dev/null
for d in "$@"; do
  echo "== $d: TXT record ${SEL}._domainkey.$d"
  docker exec "$C" sh -c "tr -d '\n' < /tmp/docker-mailserver/rspamd/dkim/rsa-2048-$SEL-$d.public.dns.txt"; echo
done
