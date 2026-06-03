# Deploying on RHEL 9 behind Apache (subpath `/edl`)

This deploys EDL Manager as a hardened systemd service bound to `127.0.0.1`, with
Apache reverse-proxying `https://panovision.sncorp.com/edl` to it. It is designed
for a server that **already runs other apps on the same Apache**, so it never adds
a virtual host and never edits Apache automatically — you merge one small snippet
into your existing vhost.

## How the subpath works

The app reads its mount path from `BASE_URL`. With
`BASE_URL=https://panovision.sncorp.com/edl` it mounts everything under `/edl`
(routes, links, redirects, and the session cookie are all scoped to `/edl`), and
firewall feed URLs become:

```
https://panovision.sncorp.com/edl/<slug>.txt
```

Apache passes `/edl` through unchanged (no stripping), so the proxy config is just
a `ProxyPass`.

## One-shot install

From the repository root on the RHEL host:

```bash
# Using an existing PostgreSQL:
sudo DATABASE_URL='postgres://edl:PASSWORD@db-host:5432/edl' ./deploy/install-rhel.sh

# …or let the installer stand up a local PostgreSQL too:
sudo ./deploy/install-rhel.sh --with-postgres
```

The installer:
1. Installs Node.js 20 and the PostgreSQL client via `dnf` AppStream modules.
2. (`--with-postgres` only) installs/initializes PostgreSQL and creates the role/db.
3. Creates the `edlmgr` service account and deploys to `/opt/edlmanager`.
4. Runs `npm install --omit=dev` and applies `schema.sql`.
5. Writes `/etc/edlmanager/edlmanager.env` (mode 600) with a generated
   `SESSION_SECRET` and, in local-auth mode, a generated admin password (printed once).
6. Installs and starts the `edlmanager` systemd service (loopback-only).
7. Sets the SELinux boolean `httpd_can_network_connect`.
8. Stages the Apache snippet at `/etc/httpd/conf.d/edlmanager.conf.example` — **not active**.

Common overrides (any can be set as env vars): `PORT` (default 3010), `BASE_URL`,
`AUTH_MODE` (default `local`), `ADMIN_USER`, `BIND_ADDR`.

## Wire up Apache (manual, by design)

1. Open the existing `<VirtualHost *:443>` that serves `panovision.sncorp.com`.
2. Paste the four directives from `/etc/httpd/conf.d/edlmanager.conf.example`
   into it (next to the other apps' proxy lines):

   ```apache
   ProxyPreserveHost On
   RequestHeader set X-Forwarded-Proto "https"
   ProxyPass        /edl  http://127.0.0.1:3010/edl  retry=0
   ProxyPassReverse /edl  http://127.0.0.1:3010/edl
   ```
3. Test and reload (never reload without testing on a shared server):

   ```bash
   apachectl configtest && systemctl reload httpd
   ```

Confirm the required modules are present (default on RHEL):

```bash
httpd -M | grep -E 'proxy_module|proxy_http_module|headers_module'
```

## Point a firewall at a list

In PAN-OS, set the EDL Source to `https://panovision.sncorp.com/edl/<slug>.txt`
(the exact URL is shown on each list's page in the UI). No authentication is
configured on the firewall side.

## Switching to SSO later

Edit `/etc/edlmanager/edlmanager.env`: set `AUTH_MODE=oidc` and fill in the
`OIDC_*` values (the file has them commented, including the correct redirect URI
`https://panovision.sncorp.com/edl/callback`). Then:

```bash
systemctl restart edlmanager
```

Register that exact redirect URI with your IdP.

## Operating

```bash
systemctl status edlmanager
journalctl -u edlmanager -f          # logs (stdout/stderr go to journald)
systemctl restart edlmanager         # after editing the env file
```

Schedule the expiry sweeper (removes expired entries and audits them):

```bash
# /etc/cron.d/edlmanager
*/5 * * * * edlmgr cd /opt/edlmanager && /usr/bin/node scripts/expire-sweeper.js >/dev/null 2>&1
```

Import existing list files:

```bash
sudo runuser -u edlmgr -- env $(grep -v '^#' /etc/edlmanager/edlmanager.env | xargs) \
  node /opt/edlmanager/scripts/import.js --slug <slug> --file /path/to/list.txt
```

## SELinux note

Apache → Node (loopback) is blocked by default; the installer runs
`setsebool -P httpd_can_network_connect 1`. A tighter alternative is to label only
the app's port and use the relay boolean:

```bash
semanage port -a -t http_port_t -p tcp 3010
setsebool -P httpd_can_network_connect off
setsebool -P httpd_can_network_relay on
```
