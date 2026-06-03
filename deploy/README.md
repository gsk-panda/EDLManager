# EDL Manager Deployment Scripts

This directory contains all the scripts and configuration files needed to deploy EDL Manager on RHEL 9.7.

## 📁 Files Overview

| File | Description |
|------|-------------|
| **`full-install.sh`** | ⭐ **Main installation script** - Complete wizard-based installation |
| **`install-rhel.sh`** | Core installation logic (called by full-install.sh) |
| **`verify-install.sh`** | Post-installation verification tool |
| **`FULL-INSTALL.md`** | Comprehensive installation guide and examples |
| **`CONFLICT-DETECTION.md`** | Guide to handling existing services and conflicts |
| **`DEPLOY-RHEL.md`** | Technical deployment documentation |
| **`QUICK-REFERENCE.md`** | Command reference for daily operations |
| `edlmanager.service` | Systemd service definition |
| `edlmanager-apache.conf` | Apache proxy configuration snippet |
| `edlmanager-vhost.conf` | Apache virtual host template |

## 🚀 Quick Start

### For New Installations

```bash
# 1. Transfer the project to your RHEL server
scp -r /path/to/EDLManager user@rhel-server:/tmp/

# 2. SSH to the server
ssh user@rhel-server

# 3. Make scripts executable (if needed)
cd /tmp/EDLManager
chmod +x deploy/*.sh

# 4. Run the installation wizard
sudo ./deploy/full-install.sh
```

The wizard will:
- ✅ Prompt for all required configuration
- ✅ **Detect conflicts** with existing services at the same path
- ✅ Clean up any previous installations
- ✅ Sync project files
- ✅ Install dependencies
- ✅ Configure the database
- ✅ Set up systemd service
- ✅ Configure Apache reverse proxy

### Verify Installation

After installation completes:

```bash
sudo ./deploy/verify-install.sh
```

This runs comprehensive checks on:
- System requirements
- File structure and permissions
- Database connectivity
- Service status
- Network configuration
- Apache/web server
- SELinux and firewall

## 📋 Installation Methods

### Method 1: Interactive Wizard (Recommended)

```bash
sudo ./deploy/full-install.sh
```

**Best for:**
- First-time installations
- When you want guided prompts
- When you're not sure about settings

**Features:**
- Interactive prompts with defaults
- Input validation
- Clear summary before proceeding
- Detailed output and status

### Method 2: With Environment Variables

```bash
sudo \
  BASE_URL="https://edl.example.com/edl" \
  SERVER_NAME="edl.example.com" \
  AUTH_MODE="local" \
  PORT="3010" \
  ./deploy/full-install.sh
```

**Best for:**
- Automated deployments
- CI/CD pipelines
- When you know all settings

### Method 3: Direct Install Script

```bash
sudo DATABASE_URL='postgres://edl:pass@host:5432/edl' \
     BASE_URL='https://edl.example.com/edl' \
     ./deploy/install-rhel.sh
```

**Best for:**
- Updating existing installation
- Advanced users
- When project files are already in place

## 🔧 Configuration Variables

### Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `https://example.com/edl` | Public URL where app is served |
| `DATABASE_URL` | *(required)* | PostgreSQL connection string |
| `SERVER_NAME` | `example.com` | Server hostname |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3010` | Application port |
| `BIND_ADDR` | `127.0.0.1` | Network interface to bind to |
| `APP_DIR` | `/opt/EDLManager` | Application installation directory |
| `AUTH_MODE` | `local` | Authentication mode (`local` or `oidc`) |
| `ADMIN_USER` | `admin` | Admin username (local auth) |
| `NODE_MAJOR` | `20` | Node.js major version |
| `SSL_CERT` | *(auto-detect)* | SSL certificate path |
| `SSL_KEY` | *(auto-detect)* | SSL private key path |

### Database Variables (for --with-postgres)

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_NAME` | `edl` | Database name |
| `DB_USER` | `edl` | Database user |
| `DB_PASS` | *(auto-generated)* | Database password |
| `DB_HOST` | `127.0.0.1` | Database host |
| `DB_PORT` | `5432` | Database port |

### OIDC Variables (for AUTH_MODE=oidc)

| Variable | Description |
|----------|-------------|
| `OIDC_ISSUER` | OIDC issuer URL |
| `OIDC_CLIENT_ID` | OIDC client ID |
| `OIDC_CLIENT_SECRET` | OIDC client secret |
| `OIDC_REDIRECT_URI` | OAuth callback URL |
| `ADMIN_EMAILS` | Comma-separated admin emails |

## 📖 Documentation

### For Installation

1. **`FULL-INSTALL.md`** - Start here for complete installation guide
   - Prerequisites
   - Step-by-step instructions
   - Examples for different scenarios
   - Troubleshooting

2. **`CONFLICT-DETECTION.md`** - Handling existing services
   - What gets checked before installation
   - How to resolve conflicts
   - Apache config backup/restore
   - Port and path conflict resolution

3. **`DEPLOY-RHEL.md`** - Technical deployment details
   - How the subpath works
   - Apache configuration details
   - SELinux notes
   - Operating procedures

### For Operations

1. **`QUICK-REFERENCE.md`** - Daily operations cheat sheet
   - Service management commands
   - Log viewing
   - Configuration changes
   - Common tasks
   - Troubleshooting commands

## ⚠️ Conflict Detection & Resolution

The `full-install.sh` script automatically detects conflicts before installation:

### What It Checks

- **Existing edlmanager service** - Running instance that will be replaced
- **Apache configurations** - ProxyPass or Location blocks using the same path
- **Port conflicts** - Another service using the configured port
- **HTTP responses** - Services already responding at the target URL path

### How It Handles Conflicts

1. **Detection Phase**: Scans for conflicts and displays detailed information
2. **Confirmation**: Asks whether to proceed despite conflicts
3. **Automatic Cleanup**:
   - Stops and disables existing `edlmanager` service
   - Backs up Apache configs with timestamp (`.backup-YYYYMMDD-HHMMSS`)
   - Removes old installation directories

### If Conflicts Are Found

**Option 1: Let the installer handle it** (Recommended)
```bash
# When prompted "Do you want to continue despite these conflicts?"
# Type: yes
```
The script will automatically stop services and back up configs.

**Option 2: Resolve manually first**
```bash
# Stop conflicting services
sudo systemctl stop <service-name>

# Remove or rename conflicting Apache configs
sudo mv /etc/httpd/conf.d/conflicting.conf /etc/httpd/conf.d/conflicting.conf.disabled

# Re-run installation
sudo ./deploy/full-install.sh
```

**Option 3: Use different path/port**
```bash
# When prompted, use different values:
# Base URL: https://example.com/edl-manager (instead of /edl)
# Port: 3020 (instead of 3010)
```

**Backed-up configs** are saved and can be restored if needed:
```bash
ls -la /etc/httpd/conf.d/*.backup-*
```

## 🔍 Verification

After installation, run the verification script:

```bash
sudo ./deploy/verify-install.sh
```

This checks:
- ✅ System requirements (Node.js, PostgreSQL, etc.)
- ✅ Directory structure and file permissions
- ✅ Configuration files
- ✅ Database connectivity and schema
- ✅ Systemd service status
- ✅ Network connectivity
- ✅ Apache/web server configuration
- ✅ SELinux and firewall settings

**Output includes:**
- Pass/fail status for each check
- Warnings for non-critical issues
- Recommendations for improvements
- Exit code 0 for success, 1 for failures

## 🔄 Updates

To update an existing installation:

```bash
# 1. Update your source code
cd /tmp/EDLManager
git pull origin main  # or however you update

# 2. Re-run the installation
sudo ./deploy/full-install.sh
```

**What happens:**
- Old files are removed
- New files are synced
- Dependencies are updated
- Service is restarted
- **Database is preserved** (not dropped)

## 🗂️ Installation Directories

After installation, these directories are created:

```
/opt/EDLManager/                      # Application installation
├── src/                              # Source code
├── scripts/                          # Utility scripts
├── views/                            # Templates
├── schema.sql                        # Database schema
├── package.json                      # Dependencies
└── node_modules/                     # Installed packages

/opt/edl-manager-deploy/              # Deployment staging
└── (mirror of repository)

/etc/edlmanager/                      # Configuration
└── edlmanager.env                    # Environment variables (600 perms)

/etc/systemd/system/                  # Service
└── edlmanager.service                # Systemd unit file

/etc/httpd/conf.d/                    # Apache config
├── edlmanager-vhost.conf             # Virtual host (if created)
└── edlmanager.conf.example           # Proxy snippet (if vhost exists)
```

## 🛠️ Maintenance

### View Logs

```bash
# Follow live logs
sudo journalctl -u edlmanager -f

# Last 100 lines
sudo journalctl -u edlmanager -n 100
```

### Restart Service

```bash
sudo systemctl restart edlmanager
```

### Edit Configuration

```bash
# Edit environment variables
sudo nano /etc/edlmanager/edlmanager.env

# Restart to apply changes
sudo systemctl restart edlmanager
```

### Database Backup

```bash
# Quick backup
pg_dump "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)" > backup.sql
```

### Set Up Cron Job (Expiry Sweeper)

```bash
sudo tee /etc/cron.d/edlmanager << 'EOF'
# EDL Manager - Remove expired entries every 5 minutes
*/5 * * * * edlmgr cd /opt/EDLManager && /usr/bin/node scripts/expire-sweeper.js >/dev/null 2>&1
EOF
```

## 🔐 Security Notes

1. **Environment File**
   - Contains sensitive credentials
   - Permissions: `600` (owner read/write only)
   - Owner: `edlmgr` service account

2. **Auto-Generated Secrets**
   - Session secret: `openssl rand -hex 32`
   - Database password: `openssl rand -base64 18`
   - Admin password: `openssl rand -base64 15`

3. **SSL/TLS**
   - Required for production
   - Let's Encrypt auto-detected
   - Firewall lists MUST be fetched over HTTPS

4. **SELinux**
   - Remains enforcing
   - `httpd_can_network_connect=1` set for Apache→Node

## 🆘 Troubleshooting

### Service Won't Start

```bash
# Check what's wrong
sudo journalctl -u edlmanager -n 50

# Verify config
sudo cat /etc/edlmanager/edlmanager.env

# Test database
psql "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)" -c "SELECT 1"
```

### Can't Access via Browser

```bash
# Check if app is listening
sudo ss -tlnp | grep 3010

# Check Apache
sudo systemctl status httpd
sudo apachectl configtest

# Check firewall
sudo firewall-cmd --list-all
```

### Permission Errors

```bash
# Fix app directory
sudo chown -R edlmgr:edlmgr /opt/EDLManager

# Fix env file
sudo chmod 600 /etc/edlmanager/edlmanager.env
sudo chown edlmgr:edlmgr /etc/edlmanager/edlmanager.env
```

## 📞 Getting Help

1. Check the logs: `sudo journalctl -u edlmanager -f`
2. Run verification: `sudo ./deploy/verify-install.sh`
3. Review documentation in this directory
4. Check the main README: `../README.md`

## 📝 Script Usage Details

### full-install.sh

```bash
sudo ./deploy/full-install.sh
```

**What it does:**
1. Runs pre-flight checks
2. Prompts for configuration (or uses env vars)
3. Shows summary and asks for confirmation
4. Deletes `/opt/EDLManager`
5. Deletes `/opt/edl-manager-deploy`
6. Syncs project files to deployment directory
7. Runs `install-rhel.sh` with your settings

**Exit codes:**
- `0` - Success
- `1` - Failure (pre-checks, user abort, or install error)

### install-rhel.sh

```bash
sudo ./deploy/install-rhel.sh [--with-postgres]
```

**Options:**
- `--with-postgres` - Install and configure local PostgreSQL
- `--help` - Show usage information

**Environment variables:** All configuration (see table above)

### verify-install.sh

```bash
sudo ./deploy/verify-install.sh
```

**Checks performed:**
- System requirements (Node, PostgreSQL, etc.)
- Directory structure
- File permissions
- Configuration validity
- Database connectivity
- Service status
- Network ports
- Apache configuration
- SELinux booleans
- Firewall rules

**Exit codes:**
- `0` - All checks passed (warnings are OK)
- `1` - One or more critical checks failed

## 🎯 Quick Decision Tree

**Choose your installation method:**

```
Do you have the project on the RHEL server?
├─ No  → Transfer it first (scp or git clone)
└─ Yes → Continue

Do you know all configuration values?
├─ No  → Use full-install.sh (interactive wizard)
└─ Yes → Do you want to script it?
          ├─ Yes → Use full-install.sh with env vars
          └─ No  → Use full-install.sh (interactive wizard)

Is this your first installation?
├─ Yes → Use full-install.sh
└─ No  → Updating? Use full-install.sh
          Need fine control? Use install-rhel.sh directly
```

## 📦 What Gets Installed

**System packages (via dnf):**
- Node.js 20 (AppStream module)
- postgresql (client tools)
- postgresql-server (if `--with-postgres`)
- mod_ssl (Apache SSL module)
- policycoreutils (SELinux tools)

**NPM packages:**
- All dependencies from `package.json`
- Installed with `--omit=dev` (production only)

**System services:**
- `edlmanager.service` (systemd)
- `httpd.service` (if configuring Apache)
- `postgresql.service` (if `--with-postgres`)

**System configuration:**
- SELinux boolean: `httpd_can_network_connect=1`
- Systemd: `edlmanager.service` enabled
- Firewall: (manual - see docs)

---

**Last Updated:** June 2026  
**For:** EDL Manager on RHEL 9.7  
**Maintainer:** See main repository README
