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

# Apache front end. SERVER_NAME is the public hostname; SSL_CERT/SSL_KEY are only
# needed when the installer has to create a brand-new dedicated vhost (i.e. the
# hostname isn't already configured). Let's Encrypt paths are auto-detected.
SERVER_NAME="${SERVER_NAME:-panovision.sncorp.com}"
SSL_CERT="${SSL_CERT:-}"
SSL_KEY="${SSL_KEY:-}"

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

# ---------------- Apache front end ----------------
log "Configuring Apache for https://${SERVER_NAME}/edl"
dnf -y install mod_ssl >/dev/null 2>&1 || true

if [ ! -d /etc/httpd/conf.d ]; then
  echo "WARN: /etc/httpd/conf.d not found -- is httpd installed? Skipping Apache."
else
  SNIPPET=/etc/httpd/conf.d/edlmanager.conf.example
  sed "s#127.0.0.1:3010#127.0.0.1:${PORT}#g" \
    "$SRC_DIR/deploy/edlmanager-apache.conf" > "$SNIPPET"

  # Is this hostname already served by a vhost (e.g. the other apps)?
  ESC_NAME="$(printf '%s' "$SERVER_NAME" | sed 's/\./\\./g')"
  EXISTING="$(grep -rilE "ServerName[[:space:]]+${ESC_NAME}" /etc/httpd/conf /etc/httpd/conf.d 2>/dev/null || true)"

  if [ -n "$EXISTING" ]; then
    APACHE_MODE="merge"
    echo "Found an existing vhost for ${SERVER_NAME}:"
    echo "$EXISTING" | sed 's/^/    /'
    echo "Staged proxy snippet at ${SNIPPET}. Merge it into that vhost; uncomment its"
    echo "root-redirect line to make /edl the landing page. Then: apachectl configtest && systemctl reload httpd"
  else
    # No vhost for this hostname -> safe to add a dedicated one (needs a cert).
    if [ -z "$SSL_CERT" ] && [ -f "/etc/letsencrypt/live/${SERVER_NAME}/fullchain.pem" ]; then
      SSL_CERT="/etc/letsencrypt/live/${SERVER_NAME}/fullchain.pem"
      SSL_KEY="/etc/letsencrypt/live/${SERVER_NAME}/privkey.pem"
    fi
    VHOST=/etc/httpd/conf.d/edlmanager-vhost.conf
    if [ -n "$SSL_CERT" ] && [ -f "$SSL_CERT" ] && [ -f "${SSL_KEY:-/nonexistent}" ]; then
      TARGET="$VHOST"; ACTIVATE=1
    else
      TARGET="${VHOST}.example"; ACTIVATE=0
      SSL_CERT="${SSL_CERT:-/etc/pki/tls/certs/${SERVER_NAME}.crt}"
      SSL_KEY="${SSL_KEY:-/etc/pki/tls/private/${SERVER_NAME}.key}"
    fi
    cat > "$TARGET" <<VH
# Generated by install-rhel.sh -- dedicated vhost making /edl the main site.
<VirtualHost *:80>
    ServerName ${SERVER_NAME}
    RedirectMatch 301 ^/(.*)\$ https://${SERVER_NAME}/\$1
</VirtualHost>
<VirtualHost *:443>
    ServerName ${SERVER_NAME}
    SSLEngine on
    SSLCertificateFile    ${SSL_CERT}
    SSLCertificateKeyFile ${SSL_KEY}
    RedirectMatch 302 ^/\$ /edl/
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    ProxyPass        /edl  http://127.0.0.1:${PORT}/edl  retry=0
    ProxyPassReverse /edl  http://127.0.0.1:${PORT}/edl
    ErrorLog  /var/log/httpd/edlmanager_error.log
    CustomLog /var/log/httpd/edlmanager_access.log combined
</VirtualHost>
VH
    if [ "$ACTIVATE" -eq 1 ]; then
      APACHE_MODE="vhost"
      if apachectl configtest 2>/tmp/edl_cfgtest; then
        systemctl reload httpd
        echo "Installed and reloaded dedicated vhost: $VHOST"
      else
        mv "$VHOST" "${VHOST}.example"
        echo "WARN: apachectl configtest failed -- backed out to ${VHOST}.example. Details:"
        cat /tmp/edl_cfgtest
        APACHE_MODE="vhost-staged"
      fi
    else
      APACHE_MODE="vhost-staged"
      echo "No TLS cert found. Wrote ${TARGET} with placeholder cert paths."
      echo "Set SSL_CERT/SSL_KEY (or edit the file), rename to ${VHOST}, then:"
      echo "  apachectl configtest && systemctl reload httpd"
    fi
  fi
fi

# ---------------- done ----------------
cat <<DONE

============================================================================
 EDL Manager installed.

 Service : systemctl status edlmanager   (logs: journalctl -u edlmanager -f)
 Listens : ${BIND_ADDR}:${PORT}  (loopback only)
 URL     : ${BASE_URL}
DONE

case "${APACHE_MODE:-none}" in
  vhost)
    cat <<DONE
 Apache  : dedicated vhost active. https://${SERVER_NAME}/ now lands on /edl.
DONE
    ;;
  vhost-staged)
    cat <<DONE
 Apache  : vhost written but NOT active (set the TLS cert path, then configtest + reload httpd).
DONE
    ;;
  merge)
    cat <<DONE
 Apache  : ${SERVER_NAME} already has a vhost. Merge /etc/httpd/conf.d/edlmanager.conf.example
           into it (uncomment the root-redirect line to make /edl the landing page),
           then: apachectl configtest && systemctl reload httpd
DONE
    ;;
  *)
    echo " Apache  : not configured (httpd not detected)."
    ;;
esac

if [ "$AUTH_MODE" = "local" ]; then
  cat <<DONE
 Test login: ${ADMIN_USER} / ${ADMIN_PASS}
   (stored in ${ENV_FILE}; change it there and restart the service)
DONE
fi
echo "============================================================================"
