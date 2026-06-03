#!/usr/bin/env bash
#
# EDL Manager - Post-Installation Verification Script
# ====================================================
# Run this script after installation to verify everything is working correctly.
#
# Usage:
#   sudo ./deploy/verify-install.sh
#
set -euo pipefail

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# Status indicators
PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}!${NC}"
INFO="${BLUE}ℹ${NC}"

# Counters
CHECKS=0
PASSED=0
FAILED=0
WARNINGS=0

check() {
    ((CHECKS++))
    printf "  [%2d] %-50s " "$CHECKS" "$1"
}

pass() {
    ((PASSED++))
    printf "${PASS} %s\n" "${1:-OK}"
}

fail() {
    ((FAILED++))
    printf "${FAIL} %s\n" "${1:-FAILED}"
}

warn() {
    ((WARNINGS++))
    printf "${WARN} %s\n" "${1:-WARNING}"
}

info() {
    printf "${INFO} %s\n" "$*"
}

section() {
    echo ""
    printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${BLUE}  %s${NC}\n" "$*"
    printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Configuration
APP_DIR="${APP_DIR:-/opt/EDLManager}"
DEPLOY_DIR="${DEPLOY_DIR:-/home/SNC/121135-adm/edl-manager}"
ENV_FILE="${ENV_FILE:-/etc/edlmanager/edlmanager.env}"
SERVICE_NAME="edlmanager"

cat << "BANNER"
╔═══════════════════════════════════════════════════════════════╗
║     EDL Manager - Installation Verification Tool             ║
╚═══════════════════════════════════════════════════════════════╝

BANNER

# ==================== System Checks ====================
section "System Requirements"

check "Running as root"
if [ "$(id -u)" -eq 0 ]; then
    pass
else
    fail "Must run as root (use sudo)"
fi

check "RHEL 9.x detected"
if [ -f /etc/redhat-release ] && grep -q "release 9" /etc/redhat-release; then
    VERSION=$(cat /etc/redhat-release)
    pass "$VERSION"
else
    fail "Not RHEL 9.x"
fi

check "Node.js installed"
if command -v node >/dev/null 2>&1; then
    NODE_VERSION=$(node --version)
    pass "$NODE_VERSION"
else
    fail "Node.js not found"
fi

check "PostgreSQL client installed"
if command -v psql >/dev/null 2>&1; then
    PSQL_VERSION=$(psql --version | awk '{print $3}')
    pass "$PSQL_VERSION"
else
    fail "psql not found"
fi

check "rsync installed"
if command -v rsync >/dev/null 2>&1; then
    pass
else
    warn "rsync not installed (needed for updates)"
fi

# ==================== Directory Checks ====================
section "Directory Structure"

check "Application directory exists"
if [ -d "$APP_DIR" ]; then
    pass "$APP_DIR"
else
    fail "$APP_DIR not found"
fi

check "Application files present"
if [ -f "$APP_DIR/src/app.js" ]; then
    pass
else
    fail "Missing app.js"
fi

check "Deployment directory exists"
if [ -d "$DEPLOY_DIR" ]; then
    pass "$DEPLOY_DIR"
else
    warn "$DEPLOY_DIR not found"
fi

check "node_modules installed"
if [ -d "$APP_DIR/node_modules" ]; then
    MODULE_COUNT=$(find "$APP_DIR/node_modules" -maxdepth 1 -type d | wc -l)
    pass "$MODULE_COUNT modules"
else
    fail "node_modules not found"
fi

check "Database schema present"
if [ -f "$APP_DIR/schema.sql" ]; then
    pass
else
    fail "schema.sql missing"
fi

# ==================== Service Account ====================
section "Service Account"

APP_USER="${APP_USER:-edlmgr}"

check "Service account exists"
if id "$APP_USER" >/dev/null 2>&1; then
    pass "$APP_USER"
else
    fail "User $APP_USER not found"
fi

check "Application directory ownership"
if [ -d "$APP_DIR" ]; then
    OWNER=$(stat -c '%U' "$APP_DIR")
    if [ "$OWNER" = "$APP_USER" ]; then
        pass "Owned by $APP_USER"
    else
        fail "Owned by $OWNER (should be $APP_USER)"
    fi
fi

# ==================== Configuration ====================
section "Configuration"

check "Environment file exists"
if [ -f "$ENV_FILE" ]; then
    pass "$ENV_FILE"
else
    fail "$ENV_FILE not found"
fi

check "Environment file permissions"
if [ -f "$ENV_FILE" ]; then
    PERMS=$(stat -c '%a' "$ENV_FILE")
    if [ "$PERMS" = "600" ]; then
        pass "600"
    else
        warn "Permissions are $PERMS (should be 600)"
    fi
fi

check "Environment file ownership"
if [ -f "$ENV_FILE" ]; then
    OWNER=$(stat -c '%U' "$ENV_FILE")
    if [ "$OWNER" = "$APP_USER" ]; then
        pass "Owned by $APP_USER"
    else
        warn "Owned by $OWNER (should be $APP_USER)"
    fi
fi

if [ -f "$ENV_FILE" ]; then
    # Load environment variables
    source "$ENV_FILE" 2>/dev/null || true
    
    check "DATABASE_URL configured"
    if [ -n "${DATABASE_URL:-}" ]; then
        # Mask password in output
        MASKED_URL=$(echo "$DATABASE_URL" | sed -E 's/:([^:@]+)@/:***@/')
        pass "$MASKED_URL"
    else
        fail "DATABASE_URL not set"
    fi
    
    check "BASE_URL configured"
    if [ -n "${BASE_URL:-}" ]; then
        pass "$BASE_URL"
    else
        fail "BASE_URL not set"
    fi
    
    check "SESSION_SECRET configured"
    if [ -n "${SESSION_SECRET:-}" ]; then
        LENGTH=${#SESSION_SECRET}
        pass "$LENGTH characters"
    else
        fail "SESSION_SECRET not set"
    fi
    
    check "AUTH_MODE configured"
    if [ -n "${AUTH_MODE:-}" ]; then
        pass "$AUTH_MODE"
    else
        fail "AUTH_MODE not set"
    fi
fi

# ==================== Database ====================
section "Database Connectivity"

if [ -n "${DATABASE_URL:-}" ]; then
    check "Database connection"
    if psql "$DATABASE_URL" -c "SELECT 1" >/dev/null 2>&1; then
        pass "Connected"
    else
        fail "Cannot connect to database"
    fi
    
    check "Database tables exist"
    TABLES=$(psql "$DATABASE_URL" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null || echo "0")
    if [ "$TABLES" -gt 0 ]; then
        pass "$TABLES tables"
    else
        fail "No tables found (schema not applied?)"
    fi
    
    check "Required tables present"
    REQUIRED_TABLES=("edls" "edl_entries" "users" "audit_log")
    MISSING_TABLES=()
    for TABLE in "${REQUIRED_TABLES[@]}"; do
        if ! psql "$DATABASE_URL" -t -c "SELECT 1 FROM information_schema.tables WHERE table_name = '$TABLE'" 2>/dev/null | grep -q 1; then
            MISSING_TABLES+=("$TABLE")
        fi
    done
    if [ ${#MISSING_TABLES[@]} -eq 0 ]; then
        pass "All present"
    else
        fail "Missing: ${MISSING_TABLES[*]}"
    fi
else
    check "Database connection"
    warn "DATABASE_URL not available"
fi

# ==================== Systemd Service ====================
section "Systemd Service"

check "Service file exists"
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    pass
else
    fail "/etc/systemd/system/${SERVICE_NAME}.service not found"
fi

check "Service is enabled"
if systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
    pass
else
    warn "Service not enabled (won't start on boot)"
fi

check "Service is active"
if systemctl is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    pass "Running"
else
    fail "Service not running"
fi

check "Service has no errors"
if systemctl status "$SERVICE_NAME" >/dev/null 2>&1; then
    pass
else
    fail "Service has errors (check journalctl -u $SERVICE_NAME)"
fi

# ==================== Network ====================
section "Network Connectivity"

PORT="${PORT:-3010}"
BIND_ADDR="${BIND_ADDR:-127.0.0.1}"

check "Application listening on port"
if ss -tlnp | grep -q ":$PORT "; then
    pass "Port $PORT"
else
    fail "Not listening on port $PORT"
fi

check "Local HTTP endpoint responds"
if curl -sf "http://${BIND_ADDR}:${PORT}/" >/dev/null 2>&1; then
    pass
else
    warn "Cannot reach http://${BIND_ADDR}:${PORT}/"
fi

# ==================== Apache/Web Server ====================
section "Web Server (Apache)"

check "Apache (httpd) installed"
if command -v httpd >/dev/null 2>&1; then
    HTTPD_VERSION=$(httpd -v | head -n1 | awk '{print $3}')
    pass "$HTTPD_VERSION"
else
    warn "httpd not found (manual proxy setup may be needed)"
fi

if command -v httpd >/dev/null 2>&1; then
    check "Apache is running"
    if systemctl is-active httpd >/dev/null 2>&1; then
        pass
    else
        warn "httpd not running"
    fi
    
    check "Apache configuration exists"
    if [ -f /etc/httpd/conf.d/edlmanager-vhost.conf ] || [ -f /etc/httpd/conf.d/edlmanager.conf.example ]; then
        pass
    else
        warn "No Apache config found"
    fi
    
    check "Apache config is valid"
    if apachectl configtest 2>&1 | grep -q "Syntax OK"; then
        pass
    else
        warn "Apache config has errors"
    fi
    
    check "mod_ssl installed"
    if httpd -M 2>&1 | grep -q ssl_module; then
        pass
    else
        warn "mod_ssl not loaded"
    fi
    
    check "Proxy modules loaded"
    MISSING_MODS=()
    for MOD in proxy_module proxy_http_module headers_module; do
        if ! httpd -M 2>&1 | grep -q "$MOD"; then
            MISSING_MODS+=("$MOD")
        fi
    done
    if [ ${#MISSING_MODS[@]} -eq 0 ]; then
        pass
    else
        warn "Missing: ${MISSING_MODS[*]}"
    fi
fi

# ==================== SELinux ====================
section "SELinux"

check "SELinux status"
if command -v getenforce >/dev/null 2>&1; then
    SELINUX_STATUS=$(getenforce)
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        pass "Enforcing"
    elif [ "$SELINUX_STATUS" = "Permissive" ]; then
        warn "Permissive (should be Enforcing in production)"
    else
        pass "Disabled"
    fi
else
    pass "Not installed"
fi

if command -v getsebool >/dev/null 2>&1; then
    check "httpd_can_network_connect"
    SEBOOL=$(getsebool httpd_can_network_connect 2>/dev/null | awk '{print $3}')
    if [ "$SEBOOL" = "on" ]; then
        pass "Enabled"
    else
        warn "Disabled (Apache may not be able to proxy)"
    fi
fi

# ==================== Firewall ====================
section "Firewall"

check "Firewalld installed"
if command -v firewall-cmd >/dev/null 2>&1; then
    pass
else
    pass "Not installed"
fi

if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    check "HTTPS port open"
    if firewall-cmd --list-services | grep -q https; then
        pass
    else
        warn "HTTPS not open (may need: firewall-cmd --permanent --add-service=https)"
    fi
fi

# ==================== Cron/Scheduled Tasks ====================
section "Scheduled Tasks"

check "Expiry sweeper configured"
if [ -f /etc/cron.d/edlmanager ] || crontab -u "$APP_USER" -l 2>/dev/null | grep -q expire-sweeper; then
    pass
else
    warn "No cron job found (expired entries won't be cleaned up)"
fi

# ==================== Summary ====================
section "Verification Summary"

echo ""
printf "  Total Checks:   %3d\n" "$CHECKS"
printf "  ${GREEN}Passed:         %3d${NC}\n" "$PASSED"
printf "  ${RED}Failed:         %3d${NC}\n" "$FAILED"
printf "  ${YELLOW}Warnings:       %3d${NC}\n" "$WARNINGS"
echo ""

if [ "$FAILED" -eq 0 ]; then
    if [ "$WARNINGS" -eq 0 ]; then
        printf "${GREEN}✓ All checks passed! Installation looks good.${NC}\n"
        EXIT_CODE=0
    else
        printf "${YELLOW}⚠ All critical checks passed, but there are warnings.${NC}\n"
        printf "  Review the warnings above and address if necessary.\n"
        EXIT_CODE=0
    fi
else
    printf "${RED}✗ Some checks failed. Please review and fix the issues above.${NC}\n"
    EXIT_CODE=1
fi

# ==================== Recommendations ====================
if [ "$WARNINGS" -gt 0 ] || [ "$FAILED" -gt 0 ]; then
    echo ""
    section "Recommendations"
    
    if [ "$FAILED" -gt 0 ]; then
        echo "  Critical issues detected. Review the following:"
        echo "    1. Check service status: systemctl status $SERVICE_NAME"
        echo "    2. View logs: journalctl -u $SERVICE_NAME -n 50"
        echo "    3. Verify configuration: cat $ENV_FILE"
        echo "    4. Test database: psql \"\$DATABASE_URL\" -c 'SELECT 1'"
    fi
    
    if [ "$WARNINGS" -gt 0 ]; then
        echo "  Optional improvements:"
        [ ! -f /etc/cron.d/edlmanager ] && echo "    - Set up expiry sweeper cron job"
        command -v firewall-cmd >/dev/null 2>&1 && ! firewall-cmd --list-services 2>/dev/null | grep -q https && \
            echo "    - Open HTTPS in firewall: firewall-cmd --permanent --add-service=https"
        ! systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1 && \
            echo "    - Enable service on boot: systemctl enable $SERVICE_NAME"
    fi
fi

echo ""
info "For more information, see:"
info "  - Service logs: journalctl -u $SERVICE_NAME -f"
info "  - Quick reference: $DEPLOY_DIR/deploy/QUICK-REFERENCE.md"
info "  - Full documentation: $DEPLOY_DIR/deploy/FULL-INSTALL.md"
echo ""

exit $EXIT_CODE
