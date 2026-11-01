#!/usr/bin/env python3
"""Set each Maildir message file's mtime from its Date: header (fallback: the first Received: date).

IMAP servers report a message's "received" date from the file's mtime. Copying old mail around
(cp without -p, some backup tools) resets mtimes, and every message then shows the copy date.
Run with the mail server stopped, then delete dovecot.index* files so Dovecot rebuilds them:

  docker compose stop mailserver
  docker run --rm -v "$PWD/data/mail:/m" -v "$PWD/tools:/t:ro" --entrypoint python3 \
      ghcr.io/docker-mailserver/docker-mailserver:16 /t/fix-maildir-dates.py /m
  find data/mail -name 'dovecot*.index*' -delete     # as root or inside a container
  docker compose start mailserver
"""
import email
import email.utils
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
ok = fallback = skipped = 0
for dirpath, _, files in os.walk(root):
    if os.path.basename(dirpath) not in ("cur", "new"):
        continue
    for name in files:
        path = os.path.join(dirpath, name)
        try:
            with open(path, "rb") as fh:
                head = fh.read(65536).split(b"\r\n\r\n", 1)[0].split(b"\n\n", 1)[0]
            msg = email.message_from_bytes(head + b"\n\n")
            ts = None
            if msg.get("Date"):
                t = email.utils.parsedate_tz(str(msg["Date"]))
                if t:
                    ts = email.utils.mktime_tz(t)
                    ok += 1
            if ts is None:
                for r in msg.get_all("Received") or []:
                    t = email.utils.parsedate_tz(str(r).rsplit(";", 1)[-1].strip())
                    if t:
                        ts = email.utils.mktime_tz(t)
                        fallback += 1
                        break
            if ts is None or not 315532800 < ts < 4102444800:   # 1980..2100
                skipped += 1
                continue
            os.utime(path, (ts, ts))
        except OSError:
            skipped += 1
print(f"from Date: {ok}, from Received: {fallback}, left as is: {skipped}")
