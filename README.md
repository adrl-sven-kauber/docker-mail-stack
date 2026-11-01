# docker-mail-stack

Your own mail server for one or a few domains, in two containers:

- **[docker-mailserver](https://github.com/docker-mailserver/docker-mailserver) 16**: Postfix, Dovecot (IMAP), rspamd (spam filter, greylisting, DKIM signing, SPF/DMARC checks), fail2ban.
- **[Roundcube](https://roundcube.net) 1.7** webmail, with filters and vacation replies (Sieve).

It runs on a 2 GB droplet next to other sites (about 400 MB RAM for both containers). Mail is stored as plain Maildir files, so backups are file copies. This is the setup behind the [Set up e-mail with Docker](https://www.svenkauber.com/blog/set-up-e-mail-with-docker) posts on svenkauber.com.

## What you need

- A Linux server with Docker (Compose v2) and a public IPv4 address whose **reverse DNS (PTR)** matches your mail host name or domain. On DigitalOcean, naming the droplet after the domain sets the PTR.
- Outbound port 25 open. Some providers block it on new accounts; ask them.
- nginx and certbot on the host (for the certificate and the webmail).
- Access to your domains' DNS.

## Setup

1. **DNS, part 1.** Pick a mail host name, e.g. `mail.example.com`, and add an **A record** pointing to the server.
2. **Certificate**, on the host:
   ```sh
   sudo certbot certonly --nginx -d mail.example.com --deploy-hook "docker restart mailserver"
   ```
   The deploy hook restarts the mail server after every renewal. On the first run it reports an error, because the container doesn't exist yet. That's fine.
3. **Configure:**
   ```sh
   git clone https://github.com/adrl-sven-kauber/docker-mail-stack.git ~/mail && cd ~/mail
   cp .env.example .env    # set MAIL_HOSTNAME, POSTMASTER_ADDRESS, ROUNDCUBEMAIL_DES_KEY
   chmod 600 .env
   ```
4. **Start, and add mailboxes and aliases:**
   ```sh
   docker compose up -d
   docker exec mailserver setup email add you@example.com 'a-long-password'
   docker exec mailserver setup alias add info@example.com you@example.com
   ```
5. **DKIM keys**, one per domain:
   ```sh
   DKIM_SELECTOR=mail tools/add-dkim.sh example.com example.org
   ```
   It prints the TXT record to publish for each domain. Existing keys are kept, because their public half is already in DNS.
6. **DNS, part 2**, for every domain:

   | Type | Name | Value |
   |---|---|---|
   | MX | `@` | `10 mail.example.com` |
   | TXT | `@` | `v=spf1 a:mail.example.com mx -all` |
   | TXT | `mail._domainkey` | the value from `add-dkim.sh` |
   | TXT | `_dmarc` | `v=DMARC1; p=none` (tighten to `quarantine` once reports look clean) |

   Remove any old MX records (forwarding services, registrar e-mail forwarding). Some registrars only use your MX records after you switch their "mail settings" to *Custom MX*. DNS panels can also lag: if the nameservers still serve an old zone, compare the SOA serial (`dig SOA example.com @<nameserver>`) with what the panel shows.
7. **Webmail:** copy `nginx/webmail.conf.example` to `/etc/nginx/sites-available/`, replace the host name, enable it, then run `sudo nginx -t && sudo systemctl reload nginx`. Log in at `https://mail.example.com` with the full address.
8. **Test.** Send yourself a mail from Gmail and back. In Gmail, "Show original" should show **SPF, DKIM and DMARC: PASS**. A new server often lands in Spam at first: mark it "Not spam".

Mail app settings: IMAP `mail.example.com` port 993 SSL/TLS; SMTP `mail.example.com` port 587 STARTTLS (or 465 SSL/TLS); user name = full address.

## Everyday tasks

```sh
docker exec mailserver setup email update you@example.com 'new-password'
docker exec mailserver setup email list
docker exec mailserver supervisorctl status            # postfix, dovecot, rspamd, fail2ban
docker exec mailserver postqueue -p                    # outgoing queue
docker exec mailserver fail2ban-client status dovecot  # banned IPs; unban: fail2ban-client unban <ip>
docker logs --since 1h mailserver
```

## Updates

The images are pinned to a version line (`docker-mailserver:16`, `roundcubemail:1.7.x-apache`). `update.sh` pulls new releases within those lines and recreates the containers. Run it weekly from cron:

```
17 4 * * 0 /home/you/mail/update.sh
```

Move to a new major version by hand, after reading its changelog. For example, v16 moved to Debian 13 and Dovecot 2.4, where a custom `dovecot.cf` in the old syntax no longer loads. Back up `config/` first.

## Backups

- `backup.sh` (cron on the server, e.g. `30 3 * * *`) mirrors everything except logs to `~/mail-backups/mirror`: mailboxes, accounts, DKIM keys, Roundcube's database. The mirror is readable by your user. The copy runs in a small container, because the mail files belong to the container user (uid 5000).
- `tools/pull-backup.sh user@server` (cron on **another** machine, e.g. `30 4 * * *`) pulls that mirror into dated snapshots. Unchanged files are hard-linked to the previous snapshot, so each day costs only the changes. It keeps 30 days, uses one SSH connection per run, and logs `STALE` if the mirror is more than 36 hours old.

**Restore:**
1. `docker compose down`. Never add `-v`.
2. Copy a snapshot back. For `data/mail`, copy through a container and `chown -R 5000:5000`.
3. Delete the `dovecot*.index*` files.
4. `docker compose up -d`.

## Moving old mail in

Copy the old server's Maildirs to `data/mail/<domain>/<user>/` while the server is stopped, `chown -R 5000:5000`, and delete the `dovecot*.index*` files. If every message then shows the copy date, the file times were lost somewhere along the way. `tools/fix-maildir-dates.py` restores them from each message's `Date:` header (instructions in the file).

## Things that cost me time

- **DKIM for several domains:** `setup config dkim domain a.com,b.com` in rspamd mode creates *one* broken key named `a.com,b.com`. Run it per domain. Each run also leaves `dkim_signing.conf` with only the first domain. `tools/add-dkim.sh` handles both.
- **Docker-published ports bypass ufw.** That's why webmail binds to `127.0.0.1`. Ports 25, 465, 587 and 993 are meant to be public.
- **fail2ban vs. webmail:** Roundcube logs in from the Docker network. If fail2ban banned that address, nobody could use webmail. `config/fail2ban-jail.cf` ignores the stack's subnet, and Roundcube limits failed logins itself (3 per minute).
- **Testing SPF from inside the container fails**, because there the mail host name resolves to the container itself. Test from outside (Gmail headers, mail-tester.com).
- **Home connections often block outgoing port 25.** Test port 25 from the server or another server.
- **IPv6:** if the host has no IPv6, Postfix still tries it first and delays delivery. `config/postfix-main.cf` sets `inet_protocols = ipv4`.

## History

The 2016 version of this setup ([blog post](https://www.svenkauber.com/blog/set-up-e-mail-with-docker)) added greylisting to docker-mailserver by hand. That became [docker-mailserver PR #495](https://github.com/docker-mailserver/docker-mailserver/pull/495) (merged February 2017). Today rspamd's built-in greylisting does the job.

## License

MIT
