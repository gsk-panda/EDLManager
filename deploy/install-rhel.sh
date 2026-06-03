#!/usr/bin/env bash
#
# EDL Manager installer for RHEL 9.x
# ----------------------------------
# Installs Node.js, deploys the app to /opt/edlmanager as a hardened systemd
# service bound to 127.0.0.1, and stages an Apache reverse-proxy snippet.
# It does NOT modify Apache automatically (other apps share that server) and it
# does NOT install PostgreSQL unless you pass --with-postgres.
#
# Usage (run as root from the repository root, or from anywhere):
#   sudo ./deploy/install-rhel.sh                       # use an existing DB via DATABASE_URL
#   sudo DATABASE_URL=postgres://edl:pw@db:5432/edl ./deploy/install-rhel.sh
#   sudo ./deploy/install-rhel.sh --with-postgres       # also stand up a local PostgreSQL
#
# Override any default with an environment variable, e.g.:
#   sudo PORT=3020 BASE_URL=https://panovision.sncorp.com/edl ./deploy/install-rhel.sh
#
set -euo pipefail

# ---------------- configuration (override via env) ----------------
APP_USER="${APP_USER:-edlmgr}"
APP_DIR="${APP_DIR:-/opt/edlmanager}"
ENV_DIR="${ENV_DIR:-/etc/edlmanager}"
ENV_FILE="$ENV_DIR/edlmanager.env"
NODE_MAJOR="${NODE_MAJOR:-20}"

BASE_URL="${BASE_URL:-https://panovision.sncorp.com/edl}"
PORT="${PORT:-3010}"
BIND_ADDR="${BIND_ADDR:-127.0.0.1}"

AUTH_MODE="${AUTH_MODE:-local}"
ADMIN_USER="${ADMIN_USER:-admin}"

# Database: either supply a full DATABASE_URL, or let --with-postgres build one.
DATABASE_URL="${DATABASE_URL:-}"
DB_NAME="${DB_NAME:-edl}"
DB_USER="${DB_USER:-edl}"
DB_PASS="${DB_PASS:-}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"

WITH_POSTGRES=0
for a in "$@"; do
  case "$a" in
    --with-postgres) WITH_POSTGRES=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $a" >&2; exit 2 ;;
  esac
done

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."
command -v dnf >/dev/null || die "dnf not found -- this script targets RHEL 9."

# Repo root = parent of this script's directory.
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$SRC_DIR/src/app.js" ] || die "Cannot find app source at $SRC_DIR (run from the repo)."

# ---------------- packages ----------------
log "Installing Node.js ${NODE_MAJOR} and the PostgreSQL client"
dnf -y module reset nodejs >/dev/null 2>&1 || true
dnf -y module enable "nodejs:${NODE_MAJOR}" >/dev/null 2>&1 || true
dnf -y install nodejs postgresql policycoreutils >/dev/null
node --version

# ---------------- optional local PostgreSQL ----------------
if [ "$WITH_POSTGRES" -eq 1 ]; then
  log "Setting up a local PostgreSQL server"
  dnf -y install postgresql-server >/dev/null
  if [ ! -s /var/lib/pgsql/data/PG_VERSION ]; then
    postgresql-setup --initdb
  fi
  # Require a password over loopback TCP (scram), leave existing rules intact.
  HBA=/var/lib/pgsql/data/pg_hba.conf
  if ! grep -qE '^host\s+all\s+all\s+127\.0\.0\.1/32\s+scram-sha-256' "$HBA"; then
    sed -i 's/^\(host\s\+all\s\+all\s\+127\.0\.0\.1\/32\s\+\).*/\1scram-sha-256/' "$HBA" || true
    grep -qE '127\.0\.0\.1/32\s+scram-sha-256' "$HBA" || \
      echo "host all all 127.0.0.1/32 scram-sha-256" >> "$HBA"
  fi
  systemctl enable --now postgresql
  [ -n "$DB_PASS" ] || DB_PASS="$(openssl rand -base64 18 | tr -d '/+=')"
  sudo -u postgres psql -v ON_ERROR_STOP=0 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  ELSE
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASS}';
  END IF;
END \$\$;
SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec
SQL
  systemctl reload postgresql || systemctl restart postgresql
  DATABASE_URL="postgres://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
fi

[ -n "$DATABASE_URL" ] || die "No DATABASE_URL. Set DATABASE_URL=... or pass --with-postgres."

# ---------------- service account ----------------
if ! id "$APP_USER" >/dev/null 2>&1; then
  log "Creating service account $APP_USER"
  useradd --system --home-dir "$APP_DIR" --shell /sbin/nologin "$APP_USER"
fi

# ---------------- deploy app ----------------
log "Deploying application to $APP_DIR"
mkdir -p "$APP_DIR"
# rsync the repo but never ship local junk or secrets.
rsync -a --delete \
  --exclude '.git' --exclude 'node_modules' --exclude 'deploy' \
  --exclude '.env' --exclude '*.tar.gz' \
  "$SRC_DIR"/ "$APP_DIR"/
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

log "Installing production dependencies"
runuser -u "$APP_USER" -- env HOME="$APP_DIR" npm --prefix "$APP_DIR" install --omit=dev --no-audit --no-fund

# ---------------- database schema ----------------
log "Applying database schema"
PGPASSWORD="${DB_PASS:-}" psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$APP_DIR/schema.sql" >/dev/null
echo "schema applied"

# ---------------- environment file ----------------
log "Writing $ENV_FILE"
mkdir -p "$ENV_DIR"
SESSION_SECRET="$(openssl rand -hex 32)"
ADMIN_PASS=""
{
  echo "NODE_ENV=production"
  echo "BASE_URL=${BASE_URL}"
  echo "PORT=${PORT}"
  echo "BIND_ADDR=${BIND_ADDR}"
  echo "TRUST_PROXY=1"
  echo "DATABASE_URL=${DATABASE_URL}"
  echo "SESSION_SECRET=${SESSION_SECRET}"
  echo "AUTH_MODE=${AUTH_MODE}"
  if [ "$AUTH_MODE" = "local" ]; then
    ADMIN_PASS="${LOCAL_ADMIN_PASSWORD:-$(openssl rand -base64 15 | tr -d '/+=')}"
    echo "LOCAL_ADMIN_USER=${ADMIN_USER}"
    echo "LOCAL_ADMIN_PASSWORD=${ADMIN_PASS}"
  fi
  echo "# --- switch to SSO by setting AUTH_MODE=oidc and filling these in ---"
  echo "# OIDC_ISSUER="
  echo "# OIDC_CLIENT_ID="
  echo "# OIDC_CLIENT_SECRET="
  echo "# OIDC_REDIRECT_URI=${BASE_URL}/callback"
  echo "# OIDC_SCOPES=openid profile email"
  echo "# ADMIN_EMAILS="
} > "$ENV_FILE"
chown "$APP_USER:$APP_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# ---------------- systemd ----------------
log "Installing and starting the systemd service"
install -m 644 "$SRC_DIR/deploy/edlmanager.service" /etc/systemd/system/edlmanager.service
systemctl daemon-reload
systemctl enable --now edlmanager.service
sleep 2
systemctl --no-pager --full status edlmanager.service | head -n 6 || true

# ---------------- SELinux ----------------
log "Allowing Apache to connect to the local Node service (SELinux)"
setsebool -P httpd_can_network_connect 1 || \
  echo "WARN: could not set httpd_can_network_connect (is SELinux installed?)"

# ---------------- Apache snippet (staged, not activated) ----------------
log "Staging the Apache reverse-proxy snippet"
APACHE_EXAMPLE=/etc/httpd/conf.d/edlmanager.conf.example
if [ -d /etc/httpd/conf.d ]; then
  sed "s#127.0.0.1:3010#127.0.0.1:${PORT}#g" \
    "$SRC_DIR/deploy/edlmanager-apache.conf" > "$APACHE_EXAMPLE"
  echo "Wrote $APACHE_EXAMPLE (review and merge into your existing vhost)."
else
  echo "WARN: /etc/httpd/conf.d not found -- is httpd installed on this host?"
fi

# ---------------- done ----------------
cat <<DONE

============================================================================
 EDL Manager installed.

 Service : systemctl status edlmanager   (logs: journalctl -u edlmanager -f)
 Listens : ${BIND_ADDR}:${PORT}  (loopback only)
 URL     : ${BASE_URL}

 NEXT (manual) -- wire up Apache without disturbing the other apps:
   1. Paste the directives from ${APACHE_EXAMPLE}
      into your existing <VirtualHost *:443> for panovision.sncorp.com.
   2. apachectl configtest && systemctl reload httpd
   3. Browse to ${BASE_URL}
DONE

if [ "$AUTH_MODE" = "local" ]; then
  cat <<DONE
 Test login: ${ADMIN_USER} / ${ADMIN_PASS}
   (stored in ${ENV_FILE}; change it there and restart the service)
DONE
fi
echo "============================================================================"
