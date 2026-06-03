# Deploying on RHEL 9 behind Apache (subpath `/edl`)

This deploys EDL Manager as a hardened systemd service bound to `127.0.0.1`, with
Apache fronting it at `https://example.com` so the site **lands on
`/edl`**. Because other apps share this Apache, the installer configures the web
front end *safely*: it detects whether the hostname already has a vhost and either
adds a dedicated one (when it's free) or stages a snippet for you to merge (when
it's already in use) — it never overwrites an existing vhost.

## How the subpath works

The app reads its mount path from `BASE_URL`. With
`BASE_URL=https://example.com/edl` it mounts everything under `/edl`
(routes, links, redirects, and the session cookie are all scoped to `/edl`), and
firewall feed URLs become:

```
https://example.com/edl/<slug>.txt
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
8. Configures Apache (see below).

Common overrides (any can be set as env vars): `PORT` (default 3010), `BASE_URL`,
`SERVER_NAME` (default `example.com`), `SSL_CERT`/`SSL_KEY`,
`AUTH_MODE` (default `local`), `ADMIN_USER`, `BIND_ADDR`.

## How Apache gets configured

The installer checks whether `SERVER_NAME` already has a vhost
(`grep ServerName` across `/etc/httpd/conf*`), then takes one of two paths:

- **Hostname is free** → it writes a dedicated vhost
  (`/etc/httpd/conf.d/edlmanager-vhost.conf`) that redirects HTTP→HTTPS, proxies
  `/edl`, and redirects the bare root `/` to `/edl/` (making it the main site).
  It needs a TLS cert: Let's Encrypt at
  `/etc/letsencrypt/live/<host>/` is auto-detected, otherwise pass
  `SSL_CERT=/path/fullchain.pem SSL_KEY=/path/privkey.pem`. It runs
  `apachectl configtest` and only reloads httpd if the test passes; on failure it
  backs the file out so the running config is never broken. If no cert is found,
  the vhost is written as `.example` with placeholder paths for you to finish.

- **Hostname already has a vhost** (your other apps) → it does **not** touch it.
  It stages `/etc/httpd/conf.d/edlmanager.conf.example`; merge those directives
  into your existing `<VirtualHost *:443>`. To make `/edl` the landing page,
  uncomment the `RedirectMatch 302 ^/$ /edl/` line (it only affects the bare root;
  other apps' sub-paths keep working). Then:

  ```bash
  apachectl configtest && systemctl reload httpd
  ```

Either way, confirm the required modules are present (default on RHEL):

```bash
httpd -M | grep -E 'proxy_module|proxy_http_module|headers_module|ssl_module'
```

## Point a firewall at a list

In PAN-OS, set the EDL Source to `https://example.com/edl/<slug>.txt`
(the exact URL is shown on each list's page in the UI). No authentication is
configured on the firewall side.

## Switching to SSO later

Edit `/etc/edlmanager/edlmanager.env`: set `AUTH_MODE=oidc` and fill in the
`OIDC_*` values (the file has them commented, including the correct redirect URI
`https://example.com/edl/callback`). Then:

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
