# Full Installation Guide for RHEL 9.7

This guide covers using the `full-install.sh` script for a complete EDL Manager deployment on RHEL 9.7.

## What This Script Does

The `full-install.sh` script performs a **complete, clean installation** of EDL Manager:

1. **Conflict Detection Phase**
   - Checks for existing services at the same URL path (e.g., `/edl`)
   - Detects if the port is already in use
   - Scans Apache configurations for conflicting proxy rules
   - Identifies running edlmanager service
   - Warns you before proceeding if conflicts are found

2. **Cleanup Phase**
   - Stops and disables existing edlmanager service (if running)
   - Backs up old Apache configurations
   - Removes `/opt/EDLManager` (if exists)
   - Removes `/home/SNC/121135-adm/edl-manager` (if exists)

3. **Sync Phase**
   - Syncs the entire project to `/home/SNC/121135-adm/edl-manager`
   - Excludes unnecessary files (.git, node_modules, .env, etc.)

4. **Installation Phase**
   - Runs the main `install-rhel.sh` script with your configuration
   - Installs all dependencies, configures the service, and sets up Apache

## Prerequisites

- **RHEL 9.7** server with root access
- Repository cloned or transferred to the server
- (Optional) SSL certificates if using HTTPS
- (Optional) OIDC provider credentials if using SSO

## Quick Start

### 1. Transfer the Project to Your RHEL Server

```bash
# From your development machine, copy to the server
scp -r /path/to/EDLManager user@rhel-server:/tmp/

# Or clone from git
git clone <your-repo-url> /tmp/EDLManager
```

### 2. Run the Installation Script

```bash
cd /tmp/EDLManager
sudo ./deploy/full-install.sh
```

### 3. Follow the Interactive Prompts

The script will ask you for:

#### Deployment Directories
- **Deployment directory**: Where to sync the project [`/home/SNC/121135-adm/edl-manager`]
- **Application directory**: Where to install the app [`/opt/EDLManager`]

#### Network Configuration
- **Base URL**: Public URL where the app will be served [`https://panovision.example.com/edl`]
- **Server hostname**: Your server's hostname [`panovision.example.com`]
- **Port**: Application port [`3010`]
- **Bind address**: Network interface to bind to [`127.0.0.1`]

#### Database Configuration
- **Install local PostgreSQL?**: Whether to install and configure PostgreSQL locally
  - If **yes**: Database name, user, and password (optional)
  - If **no**: Full DATABASE_URL connection string

#### Authentication Configuration
- **Auth mode**: `local` (username/password) or `oidc` (SSO)
  - For **local**: Admin username and password
  - For **oidc**: OIDC issuer, client ID, client secret, admin emails

#### Apache/TLS Configuration
- **SSL Certificate path**: Path to your SSL cert (auto-detected from Let's Encrypt)
- **SSL Key path**: Path to your SSL private key

## Installation Examples

### Example 1: Local Auth with Local PostgreSQL

```bash
sudo ./deploy/full-install.sh
```

When prompted:
- Deployment directory: `[press Enter for default]`
- Application directory: `[press Enter for default]`
- Base URL: `https://edl.mycompany.com/edl`
- Server hostname: `edl.mycompany.com`
- Port: `[press Enter for 3010]`
- Install PostgreSQL: `y`
- Database name: `[press Enter for edl]`
- Database password: `[leave blank for auto-generate]`
- Auth mode: `[press Enter for local]`
- Admin username: `admin`
- Admin password: `[leave blank for auto-generate]`
- SSL cert: `[leave blank for auto-detection]`

### Example 2: OIDC with External Database

```bash
sudo ./deploy/full-install.sh
```

When prompted:
- Base URL: `https://panovision.example.com/edl`
- Server hostname: `panovision.example.com`
- Install PostgreSQL: `n`
- Database URL: `postgres://edl:SecurePass123@db.example.com:5432/edl`
- Auth mode: `oidc`
- OIDC Issuer: `https://login.microsoftonline.com/tenant-id/v2.0`
- OIDC Client ID: `your-client-id-here`
- OIDC Client Secret: `your-client-secret-here`
- Admin emails: `admin@example.com,manager@example.com`
- SSL cert: `/etc/letsencrypt/live/panovision.example.com/fullchain.pem`
- SSL key: `/etc/letsencrypt/live/panovision.example.com/privkey.pem`

### Example 3: Non-Interactive (Environment Variables)

You can also pre-set environment variables to skip some prompts:

```bash
sudo \
  BASE_URL="https://edl.example.com/edl" \
  SERVER_NAME="edl.example.com" \
  PORT="3010" \
  AUTH_MODE="local" \
  DATABASE_URL="postgres://edl:pass@localhost:5432/edl" \
  ./deploy/full-install.sh
```

## Handling Conflicts

If the installation script detects conflicts (existing services at `/edl`, port in use, etc.), it will:

1. **Display detailed information** about each conflict
2. **Ask for confirmation** before proceeding
3. **Automatically handle** known conflicts during cleanup:
   - Stops the existing `edlmanager` service
   - Backs up old Apache configurations with timestamp
   - Frees up the application directory

### What to Do If Conflicts Are Detected

**Option 1: Let the script handle it (Recommended)**
- Type `yes` when prompted
- The script will stop conflicting services and back up configs
- Old Apache configs are saved with `.backup-YYYYMMDD-HHMMSS` extension

**Option 2: Manual cleanup first**
```bash
# Stop conflicting service
sudo systemctl stop <service-name>

# Remove conflicting Apache config
sudo rm /etc/httpd/conf.d/<conflicting-config>.conf

# Free up the port
sudo kill <pid-using-port>

# Re-run installation
sudo ./deploy/full-install.sh
```

**Option 3: Use a different path/port**
- When prompted, specify a different `BASE_URL` (e.g., `/edl-manager` instead of `/edl`)
- Or use a different `PORT` (e.g., `3020` instead of `3010`)

### Restoring Old Configs (If Needed)

If you need to restore a backed-up Apache configuration:

```bash
# List backups
ls -la /etc/httpd/conf.d/*.backup-*

# Restore a backup
sudo cp /etc/httpd/conf.d/edlmanager-vhost.conf.backup-20260603-095800 \
        /etc/httpd/conf.d/edlmanager-vhost.conf

# Test and reload
sudo apachectl configtest && sudo systemctl reload httpd
```

## Post-Installation Tasks

### 1. Verify Service Status

```bash
sudo systemctl status edlmanager
```

Expected output:
```
● edlmanager.service - EDL Manager
   Loaded: loaded (/etc/systemd/system/edlmanager.service; enabled)
   Active: active (running) since ...
```

### 2. Check Logs

```bash
sudo journalctl -u edlmanager -f
```

### 3. Configure Apache (if needed)

If Apache wasn't automatically configured, follow the instructions printed at the end of installation.

For existing vhosts:
```bash
# Merge the example config
sudo cat /etc/httpd/conf.d/edlmanager.conf.example

# Add to your existing vhost, then:
sudo apachectl configtest
sudo systemctl reload httpd
```

### 4. Set Up Expiry Sweeper

The sweeper removes expired entries from lists:

```bash
sudo tee /etc/cron.d/edlmanager << 'EOF'
# EDL Manager - Remove expired entries every 5 minutes
*/5 * * * * edlmgr cd /opt/EDLManager && /usr/bin/node scripts/expire-sweeper.js >/dev/null 2>&1
EOF
```

### 5. Test Access

Open your browser and navigate to the Base URL (e.g., `https://edl.example.com/edl`)

For local auth, credentials are:
- **Username**: (from prompt, default: `admin`)
- **Password**: (check install output or `/etc/edlmanager/edlmanager.env`)

## Configuration Files

After installation, these files contain your configuration:

| File | Purpose |
|------|---------|
| `/etc/edlmanager/edlmanager.env` | Application environment variables (DATABASE_URL, AUTH_MODE, etc.) |
| `/etc/systemd/system/edlmanager.service` | systemd service definition |
| `/etc/httpd/conf.d/edlmanager*.conf` | Apache reverse proxy configuration |
| `/opt/EDLManager/` | Application files |
| `/home/SNC/121135-adm/edl-manager/` | Deployment staging area |

## Updating the Application

To update to a new version:

1. Update your source repository:
```bash
cd /tmp/EDLManager
git pull origin main  # or however you update
```

2. Re-run the full install script:
```bash
sudo ./deploy/full-install.sh
```

The script will:
- Clean up old installations
- Sync the new version
- Reinstall with your previous settings (you'll be prompted again)

**Note**: Your database data is preserved. Only the application code is replaced.

## Troubleshooting

### Service Won't Start

```bash
# Check logs for errors
sudo journalctl -u edlmanager -n 50

# Verify environment file
sudo cat /etc/edlmanager/edlmanager.env

# Test database connection
psql "$DATABASE_URL" -c "SELECT 1"
```

### Can't Access via Browser

```bash
# Check if app is listening
sudo ss -tlnp | grep 3010

# Check Apache status
sudo systemctl status httpd

# Test Apache config
sudo apachectl configtest

# Check firewall
sudo firewall-cmd --list-all
```

### Database Connection Issues

```bash
# Test connection manually
psql "postgres://edl:password@host:5432/edl" -c "SELECT 1"

# Check PostgreSQL is running (if local)
sudo systemctl status postgresql

# Review PostgreSQL logs
sudo journalctl -u postgresql -n 50
```

### Permission Errors

```bash
# Fix application directory permissions
sudo chown -R edlmgr:edlmgr /opt/EDLManager
sudo chmod 600 /etc/edlmanager/edlmanager.env
sudo chown edlmgr:edlmgr /etc/edlmanager/edlmanager.env
```

## Uninstallation

To completely remove EDL Manager:

```bash
# Stop and disable service
sudo systemctl stop edlmanager
sudo systemctl disable edlmanager

# Remove files
sudo rm -rf /opt/EDLManager
sudo rm -rf /home/SNC/121135-adm/edl-manager
sudo rm -rf /etc/edlmanager
sudo rm /etc/systemd/system/edlmanager.service

# Remove Apache config
sudo rm /etc/httpd/conf.d/edlmanager*

# Reload systemd and Apache
sudo systemctl daemon-reload
sudo systemctl reload httpd

# Optionally remove PostgreSQL database
sudo -u postgres psql -c "DROP DATABASE IF EXISTS edl"
sudo -u postgres psql -c "DROP ROLE IF EXISTS edl"

# Remove service user
sudo userdel edlmgr
```

## Security Notes

1. **Environment File**: Contains sensitive credentials
   - Located at `/etc/edlmanager/edlmanager.env`
   - Permissions set to `600` (owner read/write only)
   - Owner is the service account (`edlmgr`)

2. **Database Passwords**: 
   - Auto-generated passwords are cryptographically random
   - Stored only in the environment file
   - Not logged or displayed (except once during installation)

3. **Session Secrets**:
   - Auto-generated using `openssl rand -hex 32`
   - Unique per installation

4. **SSL/TLS**:
   - Required for production use
   - Let's Encrypt certificates auto-detected
   - Firewall lists must be fetched over HTTPS

5. **SELinux**:
   - The installer sets `httpd_can_network_connect=1`
   - Allows Apache to proxy to the Node.js app

## Support

For issues or questions:
1. Check the logs: `sudo journalctl -u edlmanager -f`
2. Review the main documentation: `README.md` and `deploy/DEPLOY-RHEL.md`
3. Verify all configuration in `/etc/edlmanager/edlmanager.env`

## Advanced Configuration

### Custom Deployment Directory

```bash
# When prompted for "Deployment directory", enter your custom path:
/custom/path/to/deployment
```

### Custom Application Directory

```bash
# When prompted for "Application install directory", enter your custom path:
/custom/app/directory
```

### Using Environment Variables

```bash
# Set variables before running the script
export BASE_URL="https://custom.example.com/edl"
export SERVER_NAME="custom.example.com"
export PORT="3020"
export APP_DIR="/opt/custom-edl"
export AUTH_MODE="oidc"

sudo -E ./deploy/full-install.sh
```

The script will use these as defaults but still prompt for confirmation.
