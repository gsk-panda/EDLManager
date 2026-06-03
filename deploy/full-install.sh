#!/usr/bin/env bash
#
# EDL Manager - Full Installation Script for RHEL 9.7
# =====================================================
# This script performs a complete installation:
#   1. Cleans up old installations
#   2. Syncs project files to the deployment directory
#   3. Runs the main install-rhel.sh script
#
# Usage:
#   sudo ./deploy/full-install.sh
#
set -euo pipefail

# ==================== Color output helpers ====================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

log()     { printf "${GREEN}==> ${NC}%s\n" "$*"; }
info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die()     { error "$*"; exit 1; }
prompt()  { printf "${CYAN}[?]${NC} %s" "$*"; }

# ==================== Pre-flight checks ====================
[ "$(id -u)" -eq 0 ] || die "This script must be run as root (use sudo)."
command -v dnf >/dev/null || die "dnf not found -- this script requires RHEL 9."
command -v rsync >/dev/null || { warn "rsync not installed, installing..."; dnf -y install rsync; }

# Get the source directory (where this script's repo is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -f "$SOURCE_REPO/src/app.js" ] || die "Cannot find app source at $SOURCE_REPO"

info "Source repository: $SOURCE_REPO"
echo ""

# ==================== Configuration Gathering ====================
cat << "BANNER"
╔═══════════════════════════════════════════════════════════════╗
║       EDL Manager - RHEL 9.7 Installation Wizard             ║
║                                                               ║
║  This wizard will guide you through the installation of      ║
║  EDL Manager. You'll be prompted for configuration values.   ║
║                                                               ║
║  Press Ctrl+C at any time to abort.                          ║
╚═══════════════════════════════════════════════════════════════╝

BANNER

log "Step 1: Deployment Directories"
echo ""

DEPLOY_DIR="/home/SNC/121135-adm/edl-manager"
prompt "Deployment directory [${DEPLOY_DIR}]: "
read -r INPUT
DEPLOY_DIR="${INPUT:-$DEPLOY_DIR}"

APP_DIR="/opt/EDLManager"
prompt "Application install directory [${APP_DIR}]: "
read -r INPUT
APP_DIR="${INPUT:-$APP_DIR}"

echo ""
log "Step 2: Network Configuration"
echo ""

BASE_URL="https://panovision.example.com/edl"
prompt "Base URL (where the app will be served) [${BASE_URL}]: "
read -r INPUT
BASE_URL="${INPUT:-$BASE_URL}"

SERVER_NAME="panovision.example.com"
prompt "Server hostname [${SERVER_NAME}]: "
read -r INPUT
SERVER_NAME="${INPUT:-$SERVER_NAME}"

PORT="3010"
prompt "Application port [${PORT}]: "
read -r INPUT
PORT="${INPUT:-$PORT}"

BIND_ADDR="127.0.0.1"
prompt "Bind address (127.0.0.1 for reverse proxy, 0.0.0.0 for direct) [${BIND_ADDR}]: "
read -r INPUT
BIND_ADDR="${INPUT:-$BIND_ADDR}"

echo ""
log "Step 3: Database Configuration"
echo ""

prompt "Install local PostgreSQL? (y/n) [n]: "
read -r WITH_PG
WITH_PG="${WITH_PG:-n}"

WITH_POSTGRES_FLAG=""
if [[ "$WITH_PG" =~ ^[Yy] ]]; then
    WITH_POSTGRES_FLAG="--with-postgres"
    info "Local PostgreSQL will be installed and configured automatically."
    
    DB_NAME="edl"
    prompt "Database name [${DB_NAME}]: "
    read -r INPUT
    DB_NAME="${INPUT:-$DB_NAME}"
    
    DB_USER="edl"
    prompt "Database user [${DB_USER}]: "
    read -r INPUT
    DB_USER="${INPUT:-$DB_USER}"
    
    prompt "Database password (leave blank to auto-generate): "
    read -rs DB_PASS
    echo ""
    
    DB_HOST="127.0.0.1"
    DB_PORT="5432"
    
    if [ -n "$DB_PASS" ]; then
        DATABASE_URL="postgres://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    else
        DATABASE_URL=""  # Let install-rhel.sh generate password
        info "Database password will be auto-generated during installation."
    fi
else
    prompt "Database URL (e.g., postgres://user:pass@host:5432/dbname): "
    read -r DATABASE_URL
    [ -n "$DATABASE_URL" ] || die "Database URL is required when not using --with-postgres."
fi

echo ""
log "Step 4: Authentication Configuration"
echo ""

AUTH_MODE="local"
prompt "Authentication mode (local/oidc) [${AUTH_MODE}]: "
read -r INPUT
AUTH_MODE="${INPUT:-$AUTH_MODE}"

if [ "$AUTH_MODE" = "local" ]; then
    ADMIN_USER="admin"
    prompt "Admin username [${ADMIN_USER}]: "
    read -r INPUT
    ADMIN_USER="${INPUT:-$ADMIN_USER}"
    
    prompt "Admin password (leave blank to auto-generate): "
    read -rs LOCAL_ADMIN_PASSWORD
    echo ""
    
    if [ -z "$LOCAL_ADMIN_PASSWORD" ]; then
        info "Admin password will be auto-generated and displayed after installation."
    fi
elif [ "$AUTH_MODE" = "oidc" ]; then
    info "You'll need to configure OIDC settings in /etc/edlmanager/edlmanager.env after installation."
    prompt "OIDC Issuer URL (optional, can configure later): "
    read -r OIDC_ISSUER
    
    prompt "OIDC Client ID (optional, can configure later): "
    read -r OIDC_CLIENT_ID
    
    prompt "OIDC Client Secret (optional, can configure later): "
    read -rs OIDC_CLIENT_SECRET
    echo ""
    
    prompt "Admin emails (comma-separated, optional): "
    read -r ADMIN_EMAILS
fi

echo ""
log "Step 5: Apache/TLS Configuration (optional)"
echo ""
info "If SSL certificates are not found, a placeholder vhost will be created."

SSL_CERT=""
SSL_KEY=""
prompt "SSL Certificate path (leave blank for auto-detection) []: "
read -r SSL_CERT

if [ -n "$SSL_CERT" ]; then
    prompt "SSL Key path []: "
    read -r SSL_KEY
    
    if [ ! -f "$SSL_CERT" ]; then
        warn "Certificate file not found at: $SSL_CERT"
        prompt "Continue anyway? (y/n) [y]: "
        read -r CONTINUE
        CONTINUE="${CONTINUE:-y}"
        [[ "$CONTINUE" =~ ^[Yy] ]] || die "Aborted by user."
    fi
fi

# ==================== Conflict Detection ====================
echo ""
log "Checking for conflicts with existing services..."
echo ""

CONFLICTS_FOUND=0

# Extract the path from BASE_URL (e.g., /edl from https://example.com/edl)
URL_PATH=$(echo "$BASE_URL" | sed -E 's|^https?://[^/]+||')
if [ -z "$URL_PATH" ] || [ "$URL_PATH" = "/" ]; then
    URL_PATH="(root)"
else
    info "Will be serving at path: $URL_PATH"
fi

# Check for existing systemd services (excluding edlmanager itself)
info "Checking for conflicting systemd services..."
CONFLICTING_SERVICES=$(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | \
    grep -v edlmanager | awk '{print $1}' | grep -E 'node|web|http|app' || true)
if [ -n "$CONFLICTING_SERVICES" ]; then
    warn "Found running web/app services that might conflict:"
    echo "$CONFLICTING_SERVICES" | sed 's/^/    - /'
fi

# Check if edlmanager service already exists and is running
if systemctl is-active edlmanager >/dev/null 2>&1; then
    warn "edlmanager service is already running!"
    info "This installation will stop and replace it."
    ((CONFLICTS_FOUND++))
fi

# Check for Apache configurations with /edl path
if [ -d /etc/httpd/conf.d ]; then
    info "Checking Apache configurations for $URL_PATH..."
    APACHE_CONFLICTS=$(grep -rl "ProxyPass.*$URL_PATH" /etc/httpd/conf.d 2>/dev/null || true)
    if [ -n "$APACHE_CONFLICTS" ]; then
        warn "Found Apache configurations already using $URL_PATH:"
        echo "$APACHE_CONFLICTS" | sed 's/^/    - /'
        ((CONFLICTS_FOUND++))
    fi
    
    # Check for Location blocks
    LOCATION_CONFLICTS=$(grep -rl "<Location.*$URL_PATH" /etc/httpd/conf.d 2>/dev/null || true)
    if [ -n "$LOCATION_CONFLICTS" ]; then
        warn "Found Location blocks for $URL_PATH:"
        echo "$LOCATION_CONFLICTS" | sed 's/^/    - /'
        ((CONFLICTS_FOUND++))
    fi
fi

# Check if port is already in use
info "Checking if port $PORT is available..."
if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
    PROCESS_ON_PORT=$(ss -tlnp 2>/dev/null | grep ":$PORT " | head -n1)
    warn "Port $PORT is already in use:"
    echo "    $PROCESS_ON_PORT"
    ((CONFLICTS_FOUND++))
fi

# Check for processes serving the path
if command -v curl >/dev/null 2>&1; then
    if curl -sf "http://localhost$URL_PATH" >/dev/null 2>&1 || \
       curl -sf "https://${SERVER_NAME}${URL_PATH}" >/dev/null 2>&1; then
        warn "Found existing service responding at $URL_PATH"
        ((CONFLICTS_FOUND++))
    fi
fi

echo ""
if [ "$CONFLICTS_FOUND" -gt 0 ]; then
    cat << "WARNING"
╔═══════════════════════════════════════════════════════════════╗
║                    ⚠  CONFLICTS DETECTED  ⚠                  ║
╚═══════════════════════════════════════════════════════════════╝
WARNING
    warn "Found $CONFLICTS_FOUND potential conflict(s) that need attention."
    echo ""
    warn "Actions that will be taken:"
    warn "  - Existing edlmanager service will be stopped and replaced"
    warn "  - Apache configs may need manual cleanup after installation"
    warn "  - Port conflicts will need manual resolution"
    echo ""
    prompt "Do you want to continue despite these conflicts? (yes/no): "
    read -r CONFLICT_CONFIRM
    if [[ "$CONFLICT_CONFIRM" != "yes" ]]; then
        echo ""
        error "Installation aborted due to conflicts."
        echo ""
        info "To resolve conflicts before installing:"
        info "  1. Stop conflicting services: systemctl stop <service-name>"
        info "  2. Remove conflicting Apache configs from /etc/httpd/conf.d/"
        info "  3. Free up port $PORT if it's in use"
        info "  4. Re-run this installation script"
        echo ""
        exit 1
    fi
    echo ""
    info "Continuing installation - conflicts will be handled during cleanup..."
else
    info "✓ No conflicts detected. Safe to proceed."
fi

# ==================== Confirmation Summary ====================
echo ""
cat << "DIVIDER"
═══════════════════════════════════════════════════════════════
DIVIDER

log "Installation Summary"
echo ""
echo "  Deployment dir:     $DEPLOY_DIR"
echo "  Application dir:    $APP_DIR"
echo "  Base URL:           $BASE_URL"
echo "  Server name:        $SERVER_NAME"
echo "  Port:               $PORT"
echo "  Bind address:       $BIND_ADDR"
echo "  Auth mode:          $AUTH_MODE"
if [ "$AUTH_MODE" = "local" ]; then
    echo "  Admin user:         $ADMIN_USER"
fi
if [ -n "$WITH_POSTGRES_FLAG" ]; then
    echo "  PostgreSQL:         Local (will be installed)"
    echo "  Database name:      $DB_NAME"
    echo "  Database user:      $DB_USER"
else
    echo "  PostgreSQL:         Remote/Existing"
    echo "  Database URL:       ${DATABASE_URL:0:30}..."
fi
if [ -n "$SSL_CERT" ]; then
    echo "  SSL Certificate:    $SSL_CERT"
    echo "  SSL Key:            $SSL_KEY"
fi

echo ""
warn "DESTRUCTIVE ACTIONS:"
warn "  - /opt/EDLManager will be deleted"
warn "  - $DEPLOY_DIR will be deleted"
echo ""

prompt "Proceed with installation? (yes/no): "
read -r CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Installation aborted by user. (Type 'yes' to proceed)"

# ==================== Cleanup Old Installations ====================
echo ""
log "Cleaning up old installations..."

# Stop existing edlmanager service if running
if systemctl is-active edlmanager >/dev/null 2>&1; then
    info "Stopping existing edlmanager service..."
    systemctl stop edlmanager
    info "✓ Stopped edlmanager service"
fi

if systemctl is-enabled edlmanager >/dev/null 2>&1; then
    info "Disabling edlmanager service..."
    systemctl disable edlmanager >/dev/null 2>&1
    info "✓ Disabled edlmanager service"
fi

# Remove old Apache configs for this app (but not the whole vhost)
if [ -d /etc/httpd/conf.d ]; then
    info "Checking for old EDL Manager Apache configs..."
    OLD_CONFIGS=$(find /etc/httpd/conf.d -name "edlmanager*" -type f 2>/dev/null || true)
    if [ -n "$OLD_CONFIGS" ]; then
        info "Found old Apache configs, backing up..."
        for CONFIG in $OLD_CONFIGS; do
            BACKUP="${CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
            cp "$CONFIG" "$BACKUP"
            info "  Backed up: $CONFIG → $BACKUP"
        done
        info "Old configs backed up (will be replaced during installation)"
    fi
fi

if [ -d "/opt/EDLManager" ]; then
    info "Removing /opt/EDLManager"
    rm -rf /opt/EDLManager
    info "✓ Removed /opt/EDLManager"
else
    info "✓ /opt/EDLManager does not exist (skipped)"
fi

if [ -d "$DEPLOY_DIR" ]; then
    info "Removing $DEPLOY_DIR"
    rm -rf "$DEPLOY_DIR"
    info "✓ Removed $DEPLOY_DIR"
else
    info "✓ $DEPLOY_DIR does not exist (skipped)"
fi

# ==================== Sync Project Files ====================
echo ""
log "Syncing project files to $DEPLOY_DIR"

mkdir -p "$DEPLOY_DIR"
rsync -av --delete \
    --exclude '.git' \
    --exclude 'node_modules' \
    --exclude '.env' \
    --exclude '*.log' \
    --exclude '.vscode' \
    --exclude '.idea' \
    "$SOURCE_REPO/" "$DEPLOY_DIR/"

info "✓ Project files synced successfully"
info "  Source: $SOURCE_REPO"
info "  Target: $DEPLOY_DIR"

# ==================== Build Environment Variables ====================
echo ""
log "Preparing installation environment"

INSTALL_ENV=()
INSTALL_ENV+=("APP_DIR=$APP_DIR")
INSTALL_ENV+=("BASE_URL=$BASE_URL")
INSTALL_ENV+=("SERVER_NAME=$SERVER_NAME")
INSTALL_ENV+=("PORT=$PORT")
INSTALL_ENV+=("BIND_ADDR=$BIND_ADDR")
INSTALL_ENV+=("AUTH_MODE=$AUTH_MODE")

if [ "$AUTH_MODE" = "local" ]; then
    INSTALL_ENV+=("ADMIN_USER=$ADMIN_USER")
    [ -n "$LOCAL_ADMIN_PASSWORD" ] && INSTALL_ENV+=("LOCAL_ADMIN_PASSWORD=$LOCAL_ADMIN_PASSWORD")
fi

if [ -n "$DATABASE_URL" ]; then
    INSTALL_ENV+=("DATABASE_URL=$DATABASE_URL")
fi

if [ -n "$WITH_POSTGRES_FLAG" ]; then
    INSTALL_ENV+=("DB_NAME=$DB_NAME")
    INSTALL_ENV+=("DB_USER=$DB_USER")
    [ -n "$DB_PASS" ] && INSTALL_ENV+=("DB_PASS=$DB_PASS")
fi

if [ -n "$SSL_CERT" ]; then
    INSTALL_ENV+=("SSL_CERT=$SSL_CERT")
    INSTALL_ENV+=("SSL_KEY=$SSL_KEY")
fi

# OIDC settings
if [ "$AUTH_MODE" = "oidc" ]; then
    [ -n "$OIDC_ISSUER" ] && INSTALL_ENV+=("OIDC_ISSUER=$OIDC_ISSUER")
    [ -n "$OIDC_CLIENT_ID" ] && INSTALL_ENV+=("OIDC_CLIENT_ID=$OIDC_CLIENT_ID")
    [ -n "$OIDC_CLIENT_SECRET" ] && INSTALL_ENV+=("OIDC_CLIENT_SECRET=$OIDC_CLIENT_SECRET")
    [ -n "$ADMIN_EMAILS" ] && INSTALL_ENV+=("ADMIN_EMAILS=$ADMIN_EMAILS")
fi

# ==================== Run Installation Script ====================
echo ""
log "Running install-rhel.sh from $DEPLOY_DIR"
echo ""

cd "$DEPLOY_DIR"

# Execute the install script with environment variables
env "${INSTALL_ENV[@]}" bash "$DEPLOY_DIR/deploy/install-rhel.sh" $WITH_POSTGRES_FLAG

# ==================== Post-Installation ====================
echo ""
cat << "SUCCESS"
╔═══════════════════════════════════════════════════════════════╗
║                 ✓ INSTALLATION COMPLETE                      ║
╚═══════════════════════════════════════════════════════════════╝
SUCCESS

log "Post-Installation Information"
echo ""
info "Service Management:"
echo "  • Status:  systemctl status edlmanager"
echo "  • Logs:    journalctl -u edlmanager -f"
echo "  • Restart: systemctl restart edlmanager"
echo ""
info "Configuration:"
echo "  • App:     $APP_DIR"
echo "  • Env:     /etc/edlmanager/edlmanager.env"
echo "  • Deploy:  $DEPLOY_DIR"
echo ""
info "Access:"
echo "  • URL:     $BASE_URL"
if [ "$AUTH_MODE" = "local" ]; then
    echo "  • User:    $ADMIN_USER"
    echo "  • Pass:    (check installation output above or /etc/edlmanager/edlmanager.env)"
fi
echo ""

if [ "$AUTH_MODE" = "oidc" ] && [ -z "$OIDC_ISSUER" ]; then
    warn "OIDC Configuration Required:"
    echo "  Edit /etc/edlmanager/edlmanager.env and add:"
    echo "    OIDC_ISSUER=https://login.microsoftonline.com/<tenant-id>/v2.0"
    echo "    OIDC_CLIENT_ID=your-client-id"
    echo "    OIDC_CLIENT_SECRET=your-client-secret"
    echo "    OIDC_REDIRECT_URI=$BASE_URL/callback"
    echo "    OIDC_SCOPES=openid profile email"
    echo "    ADMIN_EMAILS=admin@example.com"
    echo ""
    echo "  Then restart: systemctl restart edlmanager"
    echo ""
fi

info "Recommended Next Steps:"
echo "  1. Verify the service is running: systemctl status edlmanager"
echo "  2. Check Apache configuration (if applicable)"
echo "  3. Set up the expiry sweeper cron job:"
echo "     echo '*/5 * * * * edlmgr cd $APP_DIR && /usr/bin/node scripts/expire-sweeper.js >/dev/null 2>&1' | sudo tee /etc/cron.d/edlmanager"
echo "  4. Test access to $BASE_URL"
echo ""

log "Installation log saved to: /var/log/edlmanager-install.log"
echo ""
