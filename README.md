# EDL Manager

A web app for managing Palo Alto **External Dynamic Lists**. Authenticated users
(via OIDC) create, edit, and delete EDLs and their entries; each EDL is served at
a public `.txt` URL that a firewall fetches anonymously over HTTPS.

## Design: two planes

- **Management plane** — humans, authenticated via OIDC, doing CRUD. Sessions,
  CSRF, audit logging.
- **Serving plane** — `GET <BASE_URL>/<slug>.txt`, public and unauthenticated, returning
  `text/plain`. Mounted before sessions/auth so the firewall fetch path stays
  stateless. A disabled or missing EDL returns **404, never 200 + empty body**
  (an empty 200 would clear the list on the firewall).

## Features

- IP / Domain / URL lists with per-type validation and normalization.
- Per-entry **comment** — kept in the UI/audit for every type, and emitted inline
  on the wire only for IP lists (`IP # comment`), since PAN-OS supports inline
  comments on IP lists only.
- Per-entry **expiry** (`expires_at`): expired entries are filtered at serve time
  and removed by a sweeper.
- **Soft disable** an entry (pull it from the served list without deleting it).
- **Audit log**: user, action, and before/after captured per change.
- **Bulk import** in the UI and a CLI importer for migrating existing text files.
- **Export** / "view raw" to see exactly what the firewall receives.
- **ETag / 304** conditional responses, and a **fetch log** (when/who pulled each list).
- Optional **random (unguessable) slug** per EDL.

## Quick test with Docker

Brings up Postgres (schema auto-loads on first run) and the app in **local auth
mode** — no OIDC needed.

```bash
docker compose up --build
```

Then open http://localhost:3000 and sign in with the test credentials:

| Username | Password       |
|----------|----------------|
| `admin`  | `ChangeMe123!` |

Both are set in `docker-compose.yml` (`LOCAL_ADMIN_USER` / `LOCAL_ADMIN_PASSWORD`)
— change them there. The local admin is created with the `admin` role on first
login. To reset all data: `docker compose down -v` (drops the `edl-pgdata` volume).

When you're ready for SSO, set `AUTH_MODE=oidc` and the `OIDC_*` vars and restart;
no code changes — the local login path is simply not used.

## Requirements

- Node.js 18+
- PostgreSQL 13+
- An OIDC provider (Entra ID, Authentik, Okta, …)

## Setup

```bash
cp .env.example .env        # then edit it
npm install
psql "$DATABASE_URL" -f schema.sql
npm start                   # or: npm run dev
```

Register an OIDC application with your IdP and set the redirect URI to
`<BASE_URL>/callback`. Put the issuer, client ID/secret, and redirect URI in `.env`.
Emails listed in `ADMIN_EMAILS` get the `admin` role on first login; everyone else
gets `editor`. (Role enforcement middleware is wired in `src/auth.js` —
`requireRole('admin')` — but not yet applied to routes, so all authenticated users
can currently edit.)

## Run behind nginx (TLS termination)

Set `TRUST_PROXY=1`. The firewall fetch endpoint needs a valid public cert — this
pairs naturally with an ACME automation. Example proxy block:

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Point a Palo Alto firewall at a list

`Objects > External Dynamic Lists > Add`: choose the matching type (IP / Domain /
URL), set the Source to the list's URL (shown on its page), and pick a check
interval. No authentication is configured on the firewall side.

## Expiry sweeper (cron)

Serving already hides expired entries; the sweeper deletes them and writes an
audit record:

```cron
*/5 * * * * cd /opt/edl-manager && node scripts/expire-sweeper.js >> /var/log/edl-sweep.log 2>&1
```

## Import existing text files

```bash
node scripts/import.js --slug block-malicious-ips --file ./old-list.txt
```

## Format rules enforced

Entries are validated by EDL type on both manual add and bulk import, matching the
PAN-OS 11.1 formatting guidelines. Invalid entries are reported (with line numbers
on import), never silently passed through to be skipped by the firewall.

- **IP**: single address (v4/v6), CIDR (`addr/mask`), or range (`start-end`).
  Inline comments are supported on the wire (`203.0.113.5 # note`).
- **Domain**: token separators `. / ? & = ; +`; a `*` wildcard must be its own
  token and may only be prepended (`*.example.com`, `*.work`); `^` means exact
  match (`^example.com`); no protocol prefix; max 255 chars. URLs/IPs rejected.
- **URL**: scheme is stripped; a `*` must be a standalone token between
  separators (`*.example.com/`, `example.com/path/*`); paths allowed.

The served feed contains entries only — no header or standalone comment lines,
because PAN-OS does not support standalone comment lines on any list type and
would skip them. The CLI importer also accepts the native PAN-OS `IP <space>
comment` form so existing IP lists import cleanly.

## Operational notes

- **Empty list on the wire**: an enabled EDL with no active entries serves an
  empty body (`200`), and PAN-OS will clear the object on its next fetch — correct
  behavior when you intend the list to be empty. A disabled or unknown list
  returns `404` instead, so the firewall keeps its last good copy. If a list must
  never clear, keep at least one benign entry (e.g. a TEST-NET `198.51.100.0/24`
  placeholder for IP lists).
- **Entry caps** vary by platform and PAN-OS version — confirm against your 11.1.x
  boxes.
- **Public exposure**: anyone with a URL can read that list. Use a random slug for
  anything sensitive, and never serve an allow-list of internal addressing publicly.

## Not yet wired (schema hooks present)

- **Roles** beyond authentication (admin/editor/viewer enforcement on routes).
- **API write tokens** (`api_tokens` table) for automated entry insertion from a
  SOAR/threat-feed pipeline.
- **Multi-tenant** scoping (`edls.owner` column reserved for it).
