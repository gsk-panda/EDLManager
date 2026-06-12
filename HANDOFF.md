# EDL Manager - Project Handoff Documentation

## Table of Contents
1. [Project Overview](#project-overview)
2. [Current Deployment Status](#current-deployment-status)
3. [Architecture & Technology Stack](#architecture--technology-stack)
4. [Repository Structure](#repository-structure)
5. [Getting Started](#getting-started)
6. [Common Operations](#common-operations)
7. [Development Workflow](#development-workflow)
8. [Deployment Process](#deployment-process)
9. [Troubleshooting](#troubleshooting)
10. [Security & Access](#security--access)
11. [Key Contacts & Resources](#key-contacts--resources)

---

## Project Overview

### What is EDL Manager?

EDL Manager is a web application for managing **Palo Alto Networks External Dynamic Lists (EDLs)**. It provides a centralized interface for creating, managing, and serving threat intelligence lists that Palo Alto firewalls can consume.

### Why It Exists

Palo Alto firewalls can fetch dynamic block/allow lists from external URLs. Instead of managing static text files, this application provides:
- **Web UI** for managing IP addresses, domains, and URLs
- **Authentication** (local or SSO via OIDC)
- **Audit logging** of all changes
- **Entry expiration** (automatic removal after date)
- **Bulk import/export** capabilities
- **Global search** across all lists
- **Public .txt feeds** that firewalls fetch (unauthenticated)

### Key Features

- ✅ **Three list types**: IP addresses, domains, URLs
- ✅ **Entry management**: Add, edit, disable, delete with comments
- ✅ **Expiration dates**: Auto-removal of temporary blocks
- ✅ **Bulk import**: Upload many entries at once
- ✅ **Global search**: Find entries across all EDLs
- ✅ **Audit trail**: Complete history of all changes
- ✅ **ETag support**: Efficient firewall polling (304 Not Modified)
- ✅ **Multiple auth modes**: Local username/password or OIDC SSO
- ✅ **Subpath mounting**: Can run at `/edl` behind reverse proxy

---

## Current Deployment Status

### Production Environment

**Server Details:**
- Environment: RHEL 9.7
- Service name: `edlmanager`
- Application path: `/opt/EDLManager`
- Config path: `/etc/edlmanager/edlmanager.env`
- Running as user: `edlmgr`
- Listening on: `127.0.0.1:6032` (behind Apache reverse proxy)
- Public URL: Served via Apache at `/edl` subpath

**Current Features Deployed:**
- ✅ Full CRUD operations for EDLs and entries
- ✅ Global search functionality
- ✅ Conflict detection on installation
- ✅ Local authentication (username/password)
- ✅ PostgreSQL database backend
- ✅ Apache reverse proxy with HTTPS
- ✅ Systemd service management
- ✅ Audit logging

**Authentication:**
- Mode: `local` (username/password)
- Default credentials in `/etc/edlmanager/edlmanager.env`
- Can be switched to OIDC/SSO by updating config

**Database:**
- Type: PostgreSQL
- Name: `edl`
- Schema: See `schema.sql`
- Tables: `edls`, `edl_entries`, `edl_fetch_log`, `audit_log`, `users`, `session`

---

## Architecture & Technology Stack

### High-Level Architecture

```
Internet (Firewalls)
        ↓
   Apache (HTTPS)
        ↓
EDL Manager (Node.js)
        ↓
   PostgreSQL
```

### Technology Stack

**Backend:**
- **Node.js 20.x** - Runtime
- **Express.js** - Web framework
- **PostgreSQL 13+** - Database
- **connect-pg-simple** - Session storage

**Frontend:**
- **EJS templates** - Server-side rendering
- **Embedded CSS** - No build step required
- **Vanilla JavaScript** - Minimal client-side code

**Infrastructure:**
- **RHEL 9.7** - Operating system
- **Apache 2.4** - Reverse proxy (TLS termination)
- **systemd** - Service management
- **SELinux** - Enforcing mode

**Authentication:**
- **Passport.js** - Auth middleware
- **passport-openidconnect** - OIDC strategy (when enabled)
- **express-session** - Session management
- **csurf** - CSRF protection

### Application Flow

1. **User authentication**: Login via web UI (local or OIDC)
2. **Management operations**: CRUD operations on EDLs/entries via authenticated routes
3. **Audit logging**: All changes recorded with user, timestamp, and details
4. **Public feeds**: Unauthenticated `.txt` URLs for firewall consumption
5. **Fetch logging**: Each firewall fetch recorded with timestamp and ETag

---

## Repository Structure

```
EDLManager/
├── .env.example              # Environment template (copy to .env for local dev)
├── package.json              # Node.js dependencies
├── schema.sql                # Database schema (auto-applied during install)
├── docker-compose.yml        # Docker setup for local development
├── README.md                 # Main project documentation
├── SEARCH-FEATURE.md         # Global search feature docs
├── HANDOFF.md               # This file
│
├── src/                      # Application source code
│   ├── app.js               # Main Express app setup
│   ├── config.js            # Configuration loader (from env vars)
│   ├── db.js                # PostgreSQL connection pool
│   ├── auth.js              # Authentication logic (local + OIDC)
│   ├── validation.js        # IP/domain/URL validation
│   ├── audit.js             # Audit logging functions
│   └── routes/
│       ├── serve.js         # Public feed routes (unauthenticated)
│       └── edls.js          # Management routes (authenticated)
│
├── views/                    # EJS templates
│   ├── partials/
│   │   ├── header.ejs       # Common header (with search box)
│   │   └── footer.ejs       # Common footer
│   ├── login.ejs            # Login page
│   ├── edls.ejs             # Dashboard (list all EDLs)
│   ├── edl.ejs              # EDL detail page (entries)
│   ├── search.ejs           # Global search results
│   └── import-result.ejs    # Bulk import results
│
├── scripts/                  # Utility scripts
│   ├── sweep-expired.js     # Cleanup expired entries (run via cron)
│   └── create-user.js       # Add users (when using local auth)
│
└── deploy/                   # Deployment automation
    ├── README.md             # Deployment overview
    ├── FULL-INSTALL.md       # Complete installation guide
    ├── DEPLOY-RHEL.md        # RHEL-specific deployment details
    ├── CONFLICT-DETECTION.md # Conflict resolution guide
    ├── QUICK-REFERENCE.md    # Quick command reference
    ├── full-install.sh       # Automated full installation
    ├── install-rhel.sh       # Main installation script
    ├── verify-install.sh     # Post-install verification
    ├── edlmanager.service    # systemd unit file template
    ├── edlmanager-apache.conf   # Apache config snippet
    └── edlmanager-vhost.conf    # Dedicated vhost template
```

---

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/gsk-panda/EDLManager
cd EDLManager
```

### 2. Review Existing Documentation

**Start with these files (in order):**
1. `README.md` - Project overview and features
2. `deploy/README.md` - Deployment options and overview
3. `deploy/FULL-INSTALL.md` - Complete installation guide
4. `SEARCH-FEATURE.md` - Global search functionality
5. `deploy/QUICK-REFERENCE.md` - Common commands and tasks

### 3. Local Development Setup (Docker)

For local development, use Docker Compose:

```bash
# Copy example environment
cp .env.example .env

# Edit .env as needed (defaults work for Docker)
nano .env

# Start PostgreSQL and app
docker-compose up -d

# View logs
docker-compose logs -f app

# Access at http://localhost:3000
# Default login: admin / ChangeMe123!
```

### 4. Understanding the Codebase

**Key files to review:**

1. **`src/app.js`** - Main application setup
   - Session configuration
   - Route mounting
   - Trust proxy settings

2. **`src/auth.js`** - Authentication logic
   - Local and OIDC strategies
   - CSRF protection
   - User session management

3. **`src/routes/edls.js`** - Core business logic
   - EDL CRUD operations
   - Entry management
   - Bulk import
   - Global search (NEW)

4. **`src/routes/serve.js`** - Public feed serving
   - Unauthenticated routes
   - ETag support
   - Fetch logging

5. **`schema.sql`** - Database structure
   - All tables and indexes
   - Constraints and relationships

---

## Common Operations

### Access Production System

```bash
# SSH to server (adjust as needed)
ssh user@server

# Check service status
sudo systemctl status edlmanager

# View real-time logs
sudo journalctl -u edlmanager -f

# Restart service
sudo systemctl restart edlmanager

# View configuration
sudo cat /etc/edlmanager/edlmanager.env
```

### Database Access

```bash
# Connect to database
sudo -u postgres psql edl

# Common queries
SELECT * FROM edls;
SELECT * FROM edl_entries WHERE edl_id = 1;
SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 10;
SELECT * FROM edl_fetch_log ORDER BY fetched_at DESC LIMIT 10;
```

### View Audit Trail

```bash
# Recent changes
sudo -u postgres psql edl -c "
  SELECT created_at, username, action, entity_type, detail 
  FROM audit_log 
  ORDER BY created_at DESC 
  LIMIT 20;
"
```

### Add a User (Local Auth)

```bash
cd /opt/EDLManager
sudo -u edlmgr node scripts/create-user.js \
  --email user@example.com \
  --name "User Name" \
  --role editor
```

### Clean Up Expired Entries

```bash
# Manual run
cd /opt/EDLManager
sudo -u edlmgr node scripts/sweep-expired.js

# Or set up cron (recommended)
sudo crontab -e -u edlmgr
# Add: 0 2 * * * cd /opt/EDLManager && node scripts/sweep-expired.js
```

### Change Configuration

```bash
# Edit environment file
sudo nano /etc/edlmanager/edlmanager.env

# Common changes:
# - PORT: Change listening port
# - BASE_URL: Update public URL
# - AUTH_MODE: Switch between local/oidc
# - DATABASE_URL: Point to different database

# Restart to apply changes
sudo systemctl restart edlmanager
```

### Switch to OIDC/SSO

```bash
# Edit config
sudo nano /etc/edlmanager/edlmanager.env

# Set these values:
AUTH_MODE=oidc
OIDC_ISSUER=https://login.microsoftonline.com/tenant-id/v2.0
OIDC_CLIENT_ID=your-client-id
OIDC_CLIENT_SECRET=your-client-secret
OIDC_REDIRECT_URI=https://your-domain.com/edl/callback
OIDC_SCOPES=openid profile email
ADMIN_EMAILS=admin1@example.com,admin2@example.com

# Restart
sudo systemctl restart edlmanager
```

### Backup Database

```bash
# Backup
sudo -u postgres pg_dump edl > edl_backup_$(date +%Y%m%d).sql

# Restore
sudo -u postgres psql edl < edl_backup_20260612.sql
```

---

## Development Workflow

### Making Code Changes

1. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes locally**
   - Test with Docker Compose
   - Run the app locally: `npm install && npm start`

3. **Test thoroughly**
   - Login and authentication
   - EDL CRUD operations
   - Entry management
   - Search functionality
   - Public feed URLs

4. **Commit changes**
   ```bash
   git add .
   git commit -m "feat: Add your feature description"
   ```

5. **Push to GitHub**
   ```bash
   git push origin feature/your-feature-name
   ```

### Deploying to Production

**Option 1: Quick Update (no config changes)**
```bash
# On server
cd /tmp
rm -rf EDLManager
git clone https://github.com/gsk-panda/EDLManager
cd EDLManager
sudo cp -r src/* /opt/EDLManager/src/
sudo cp -r views/* /opt/EDLManager/views/
sudo chown -R edlmgr:edlmgr /opt/EDLManager
sudo systemctl restart edlmanager
```

**Option 2: Full Reinstall**
```bash
# On server
cd /tmp
rm -rf EDLManager
git clone https://github.com/gsk-panda/EDLManager
cd EDLManager
sudo ./deploy/full-install.sh
# Follow prompts (can accept defaults if config unchanged)
```

### Adding New Features

**Example: Adding a new route**

1. Add route to `src/routes/edls.js`:
   ```javascript
   router.get('/my-new-route', wrap(async (req, res) => {
     // Your logic here
     res.render('my-view', { data });
   }));
   ```

2. Create view at `views/my-view.ejs`:
   ```html
   <%- include('partials/header') %>
   <!-- Your HTML here -->
   <%- include('partials/footer') %>
   ```

3. Test locally, commit, deploy

**Example: Adding database column**

1. Add migration SQL:
   ```sql
   ALTER TABLE edl_entries ADD COLUMN my_field TEXT;
   ```

2. Run on production:
   ```bash
   sudo -u postgres psql edl -c "ALTER TABLE edl_entries ADD COLUMN my_field TEXT;"
   ```

3. Update code to use new column

---

## Deployment Process

### Prerequisites

- RHEL 9.7 server with root access
- PostgreSQL 13+ (can be installed by script)
- Apache 2.4 (usually pre-installed)
- Git installed
- Internet connectivity

### Full Installation Steps

See `deploy/FULL-INSTALL.md` for complete details. Quick summary:

1. **Clone repository to server**
   ```bash
   cd /tmp
   git clone https://github.com/gsk-panda/EDLManager
   cd EDLManager
   ```

2. **Run installation wizard**
   ```bash
   sudo ./deploy/full-install.sh
   ```

3. **Answer prompts**
   - Deployment directory
   - Application directory
   - Base URL and hostname
   - Port (default 3010, production uses 6032)
   - Database settings
   - Authentication mode
   - SSL certificates

4. **Review and confirm**
   - Script shows summary
   - Asks for confirmation
   - Detects and handles conflicts

5. **Installation proceeds automatically**
   - Installs Node.js 20
   - Installs PostgreSQL (if requested)
   - Creates service user
   - Deploys application
   - Configures systemd
   - Sets up Apache
   - Starts service

### Post-Installation

```bash
# Verify installation
sudo ./deploy/verify-install.sh

# Check service
sudo systemctl status edlmanager

# Test public feed
curl -I http://localhost:3010/edl/test.txt  # Adjust port as needed
```

---

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u edlmanager -n 50

# Common issues:
# 1. Port already in use
sudo ss -tlnp | grep :3010

# 2. Database connection failed
sudo -u postgres psql -c "\l" | grep edl

# 3. Wrong working directory
sudo cat /etc/systemd/system/edlmanager.service | grep WorkingDirectory

# 4. Permissions
ls -la /opt/EDLManager
ls -la /etc/edlmanager
```

### CSRF Token Errors

```bash
# Check trust proxy setting
sudo grep TRUST_PROXY /etc/edlmanager/edlmanager.env

# Should be TRUST_PROXY=1 when behind Apache
# Add if missing:
echo "TRUST_PROXY=1" | sudo tee -a /etc/edlmanager/edlmanager.env
sudo systemctl restart edlmanager
```

### Apache Not Proxying Correctly

```bash
# Check Apache config
sudo grep -r "ProxyPass.*edl" /etc/httpd/conf.d/

# Should see something like:
# ProxyPass /edl http://127.0.0.1:3010/edl retry=0

# Test Apache config
sudo apachectl configtest

# Check if modules loaded
sudo httpd -M | grep -E 'proxy|headers'

# Restart Apache
sudo systemctl restart httpd
```

### Database Issues

```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check if database exists
sudo -u postgres psql -c "\l" | grep edl

# Check if tables exist
sudo -u postgres psql edl -c "\dt"

# Re-apply schema if needed
sudo -u postgres psql edl < /opt/EDLManager/schema.sql
```

### Search Not Working

```bash
# Verify route exists
curl -I http://localhost:3010/edl/search?q=test

# Check if search.ejs exists
ls -la /opt/EDLManager/views/search.ejs

# Check logs for errors
sudo journalctl -u edlmanager -f
```

### Port Conflicts

```bash
# Find process using port
sudo lsof -i :3010
sudo ss -tlnp | grep :3010

# Kill conflicting process (if safe)
sudo kill <PID>

# Or change EDL Manager port
sudo nano /etc/edlmanager/edlmanager.env
# Change PORT=3010 to PORT=6032
sudo systemctl restart edlmanager
```

---

## Security & Access

### Authentication

**Current Mode**: Local (username/password)
- Credentials in: `/etc/edlmanager/edlmanager.env`
- Variables: `LOCAL_ADMIN_USER`, `LOCAL_ADMIN_PASSWORD`

**To Switch to SSO**: See "Switch to OIDC/SSO" in Common Operations section

### File Permissions

```bash
# Sensitive config (600 - root only)
/etc/edlmanager/edlmanager.env

# Application files (owned by edlmgr)
/opt/EDLManager/

# Service file (644 - readable by all)
/etc/systemd/system/edlmanager.service
```

### Firewall Rules

```bash
# Apache should be accessible
sudo firewall-cmd --list-services | grep http

# EDL Manager only on localhost (not exposed)
# Verify with:
sudo ss -tlnp | grep 3010
# Should show 127.0.0.1:3010, not 0.0.0.0:3010
```

### SELinux

```bash
# Check if enforcing
getenforce

# Required boolean for Apache → Node.js proxy
sudo getsebool httpd_can_network_connect
# Should be: on

# If off:
sudo setsebool -P httpd_can_network_connect 1
```

### SSL Certificates

- Apache handles TLS termination
- Let's Encrypt recommended
- Auto-detected by installer at: `/etc/letsencrypt/live/*/`

---

## Key Contacts & Resources

### Documentation

- **GitHub Repository**: https://github.com/gsk-panda/EDLManager
- **Main README**: `README.md`
- **Deployment Guide**: `deploy/FULL-INSTALL.md`
- **Search Feature**: `SEARCH-FEATURE.md`
- **Quick Reference**: `deploy/QUICK-REFERENCE.md`

### External Resources

- **Palo Alto EDL Documentation**: [Palo Alto Networks Docs](https://docs.paloaltonetworks.com/)
- **Node.js Documentation**: https://nodejs.org/docs/
- **Express.js Guide**: https://expressjs.com/
- **PostgreSQL Manual**: https://www.postgresql.org/docs/

### Development Tools

- **Node.js 20.x**: https://nodejs.org/
- **Docker Compose**: For local development
- **Git**: Version control
- **VS Code**: Recommended editor (or your preference)

### Support

- Review logs: `sudo journalctl -u edlmanager -f`
- Check GitHub Issues: (create if public repo)
- Refer to troubleshooting section above

---

## Quick Reference Card

### Service Management
```bash
sudo systemctl status edlmanager
sudo systemctl start edlmanager
sudo systemctl stop edlmanager
sudo systemctl restart edlmanager
sudo journalctl -u edlmanager -f
```

### Configuration
```bash
sudo nano /etc/edlmanager/edlmanager.env
sudo systemctl restart edlmanager
```

### Database
```bash
sudo -u postgres psql edl
# \dt - list tables
# \d edls - describe table
# \q - quit
```

### Apache
```bash
sudo apachectl configtest
sudo systemctl reload httpd
sudo systemctl status httpd
```

### Logs
```bash
# Application
sudo journalctl -u edlmanager -n 100
sudo journalctl -u edlmanager -f

# Apache
sudo tail -f /var/log/httpd/error_log
sudo tail -f /var/log/httpd/access_log
```

### Deployment
```bash
# Quick update
cd /tmp && rm -rf EDLManager
git clone https://github.com/gsk-panda/EDLManager
cd EDLManager
sudo cp -r src/* /opt/EDLManager/src/
sudo cp -r views/* /opt/EDLManager/views/
sudo systemctl restart edlmanager

# Full reinstall
cd /tmp/EDLManager
sudo ./deploy/full-install.sh
```

---

## Next Steps for New Engineer

### Week 1: Orientation
- [ ] Clone repository and review all documentation
- [ ] Set up local development environment with Docker
- [ ] Review codebase structure and key files
- [ ] Access production system (read-only initially)
- [ ] Observe logs and understand traffic patterns

### Week 2: Hands-On Learning
- [ ] Make a small UI change locally and test
- [ ] Review recent audit logs on production
- [ ] Practice database queries
- [ ] Run verification scripts
- [ ] Shadow any configuration changes

### Week 3: Independent Work
- [ ] Deploy a small update to production (with supervision)
- [ ] Handle a support request or bug fix
- [ ] Review and understand the search feature implementation
- [ ] Document any questions or unclear areas

### Ongoing
- [ ] Monitor service health and logs
- [ ] Respond to firewall team requests (new EDLs, entries)
- [ ] Keep dependencies updated (npm audit)
- [ ] Plan and implement enhancements
- [ ] Maintain documentation

---

## Important Notes

### Things to Remember

1. **Public feeds are unauthenticated** - Anyone with the URL can fetch lists
2. **Session secrets** - Never commit `.env` files with real secrets
3. **Database backups** - Set up automated backups (not included in install)
4. **Expired entries** - Set up cron job for cleanup (see Common Operations)
5. **TRUST_PROXY** - Required when behind Apache (already configured)
6. **Port conflicts** - Production uses 6032, not default 3010
7. **Audit everything** - All changes are logged automatically
8. **ETags matter** - Efficient firewall polling, don't break this

### Common Gotchas

- Forgetting to restart service after config changes
- Wrong WorkingDirectory in systemd service file
- CSRF errors if TRUST_PROXY not set
- Apache serving old static files instead of proxying
- Case sensitivity in EDL slugs and search

### Best Practices

- Test all changes locally before deploying
- Always check logs after deployment
- Keep documentation updated
- Use version control for all changes
- Back up database before schema changes
- Communicate with firewall team before major changes

---

**Good luck! This is a solid, production-ready application. Take your time to understand it, and don't hesitate to refer back to the documentation.**

**Questions or issues? Review the troubleshooting section first, then check logs, then reach out for help.**
