# EDL Manager - Quick Reference Card

Quick commands for managing EDL Manager on RHEL 9.7 after installation.

## Service Management

```bash
# Check service status
sudo systemctl status edlmanager

# Start service
sudo systemctl start edlmanager

# Stop service
sudo systemctl stop edlmanager

# Restart service (after config changes)
sudo systemctl restart edlmanager

# Enable service (start on boot)
sudo systemctl enable edlmanager

# Disable service (don't start on boot)
sudo systemctl disable edlmanager
```

## Viewing Logs

```bash
# Follow live logs
sudo journalctl -u edlmanager -f

# View last 100 lines
sudo journalctl -u edlmanager -n 100

# View logs since today
sudo journalctl -u edlmanager --since today

# View logs from specific time
sudo journalctl -u edlmanager --since "2026-06-03 09:00:00"

# View logs with priority (errors only)
sudo journalctl -u edlmanager -p err
```

## Configuration

```bash
# View current configuration
sudo cat /etc/edlmanager/edlmanager.env

# Edit configuration
sudo nano /etc/edlmanager/edlmanager.env

# After editing, restart the service
sudo systemctl restart edlmanager

# Verify configuration syntax (check app starts)
sudo systemctl restart edlmanager && sudo systemctl status edlmanager
```

## Database Operations

```bash
# Connect to database (if local PostgreSQL)
sudo -u postgres psql edl

# Connect with app credentials
psql "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)"

# Backup database
pg_dump "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)" > backup.sql

# Restore database
psql "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)" < backup.sql

# Check database size
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('edl'));"
```

## Apache/Web Server

```bash
# Test Apache configuration
sudo apachectl configtest

# Reload Apache (after config changes)
sudo systemctl reload httpd

# Restart Apache
sudo systemctl restart httpd

# View Apache error logs
sudo tail -f /var/log/httpd/edlmanager_error.log

# View Apache access logs
sudo tail -f /var/log/httpd/edlmanager_access.log

# Check Apache status
sudo systemctl status httpd
```

## Application Files

| Path | Description |
|------|-------------|
| `/opt/EDLManager/` | Application code |
| `/opt/EDLManager/src/` | Source files |
| `/opt/EDLManager/scripts/` | Utility scripts |
| `/opt/EDLManager/schema.sql` | Database schema |
| `/etc/edlmanager/edlmanager.env` | Configuration file |
| `/etc/systemd/system/edlmanager.service` | Service definition |
| `/etc/httpd/conf.d/edlmanager*.conf` | Apache config |
| `/opt/edl-manager-deploy/` | Deployment staging |

## Common Tasks

### Change Admin Password (Local Auth)

```bash
# Edit the env file
sudo nano /etc/edlmanager/edlmanager.env

# Change this line:
# LOCAL_ADMIN_PASSWORD=your-new-password

# Restart service
sudo systemctl restart edlmanager
```

### Switch to OIDC Authentication

```bash
# Edit configuration
sudo nano /etc/edlmanager/edlmanager.env

# Change AUTH_MODE and uncomment OIDC settings:
# AUTH_MODE=oidc
# OIDC_ISSUER=https://login.microsoftonline.com/tenant-id/v2.0
# OIDC_CLIENT_ID=your-client-id
# OIDC_CLIENT_SECRET=your-client-secret
# OIDC_REDIRECT_URI=https://your-server.com/edl/callback
# OIDC_SCOPES=openid profile email
# ADMIN_EMAILS=admin@example.com

# Restart service
sudo systemctl restart edlmanager
```

### Change Port

```bash
# Edit configuration
sudo nano /etc/edlmanager/edlmanager.env
# Change: PORT=3020

# Edit Apache config
sudo nano /etc/httpd/conf.d/edlmanager-vhost.conf
# Update ProxyPass lines with new port

# Restart both services
sudo systemctl restart edlmanager
sudo apachectl configtest && sudo systemctl reload httpd
```

### Run Expiry Sweeper Manually

```bash
# As root
sudo -u edlmgr bash -c 'cd /opt/EDLManager && node scripts/expire-sweeper.js'

# View output
sudo -u edlmgr bash -c 'cd /opt/EDLManager && node scripts/expire-sweeper.js 2>&1'
```

### Import Existing List

```bash
# Import a text file as a new EDL
sudo -u edlmgr bash -c "cd /opt/EDLManager && \
  export \$(grep -v '^#' /etc/edlmanager/edlmanager.env | xargs) && \
  node scripts/import.js --slug my-list --file /path/to/list.txt"
```

### Check Application Health

```bash
# Check if app is listening on port
sudo ss -tlnp | grep 3010

# Test local endpoint
curl -I http://127.0.0.1:3010/edl/

# Test public endpoint
curl -I https://your-server.com/edl/

# Check database connection
sudo -u edlmgr bash -c 'cd /opt/EDLManager && \
  export $(grep -v "^#" /etc/edlmanager/edlmanager.env | xargs) && \
  node -e "const pg = require(\"pg\"); \
    new pg.Client().connect().then(() => console.log(\"DB OK\")).catch(console.error)"'
```

## Troubleshooting

### Service Won't Start

```bash
# Check what went wrong
sudo journalctl -u edlmanager -n 50 --no-pager

# Verify environment file exists and is readable
sudo ls -l /etc/edlmanager/edlmanager.env

# Check file permissions
sudo stat /opt/EDLManager/src/app.js

# Verify service account
id edlmgr
```

### Port Already in Use

```bash
# Find what's using the port
sudo ss -tlnp | grep :3010

# Kill the process (if safe)
sudo kill -9 <PID>

# Or change the port in config
sudo nano /etc/edlmanager/edlmanager.env
```

### Database Connection Fails

```bash
# Test connection
psql "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)" -c "SELECT 1"

# Check PostgreSQL is running
sudo systemctl status postgresql

# Check PostgreSQL logs
sudo journalctl -u postgresql -n 50
```

### Can't Access from Browser

```bash
# Check firewall rules
sudo firewall-cmd --list-all

# Open HTTPS port (if needed)
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Check SELinux (if blocking)
sudo ausearch -m avc -ts recent
sudo setsebool -P httpd_can_network_connect 1
```

## Monitoring

### Resource Usage

```bash
# Check memory usage
ps aux | grep "node.*edlmanager" | awk '{print $4"%\t"$11}'

# Check CPU usage
top -bn1 | grep "node"

# Check disk usage
df -h /opt/EDLManager
```

### List Statistics

Access the application's admin panel or query the database:

```bash
# Total number of EDLs
sudo -u postgres psql edl -c "SELECT COUNT(*) FROM edls;"

# Total entries across all lists
sudo -u postgres psql edl -c "SELECT COUNT(*) FROM edl_entries;"

# Entries by list type
sudo -u postgres psql edl -c "SELECT type, COUNT(*) FROM edls GROUP BY type;"

# Recent audit log entries
sudo -u postgres psql edl -c "SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 10;"
```

## Backup and Restore

### Quick Backup

```bash
# Backup database
BACKUP_FILE="edl-backup-$(date +%Y%m%d-%H%M%S).sql"
pg_dump "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)" > "$BACKUP_FILE"
echo "Backed up to: $BACKUP_FILE"

# Backup configuration
sudo cp /etc/edlmanager/edlmanager.env "/tmp/edlmanager.env.backup-$(date +%Y%m%d)"
```

### Quick Restore

```bash
# Restore database
psql "$(grep DATABASE_URL /etc/edlmanager/edlmanager.env | cut -d= -f2-)" < backup.sql

# Restart service
sudo systemctl restart edlmanager
```

## Performance Tuning

### Database Maintenance

```bash
# Analyze database for query optimization
sudo -u postgres psql edl -c "ANALYZE;"

# Vacuum database (reclaim space)
sudo -u postgres psql edl -c "VACUUM FULL;"

# Reindex database
sudo -u postgres psql edl -c "REINDEX DATABASE edl;"
```

### Log Rotation

```bash
# Configure journald log rotation
sudo nano /etc/systemd/journald.conf

# Set:
# SystemMaxUse=500M
# SystemMaxFileSize=100M

# Restart journald
sudo systemctl restart systemd-journald
```

## Security

### File Permissions

```bash
# Verify critical file permissions
ls -l /etc/edlmanager/edlmanager.env  # Should be 600, owned by edlmgr
ls -ld /opt/EDLManager                # Should be owned by edlmgr

# Fix if needed
sudo chown -R edlmgr:edlmgr /opt/EDLManager
sudo chmod 600 /etc/edlmanager/edlmanager.env
sudo chown edlmgr:edlmgr /etc/edlmanager/edlmanager.env
```

### Regenerate Session Secret

```bash
# Generate new secret
NEW_SECRET=$(openssl rand -hex 32)

# Update config
sudo sed -i "s/^SESSION_SECRET=.*/SESSION_SECRET=$NEW_SECRET/" /etc/edlmanager/edlmanager.env

# Restart (will log out all users)
sudo systemctl restart edlmanager
```

### View Active Sessions

```bash
# Check who's currently logged in (requires database access)
sudo -u postgres psql edl -c "SELECT * FROM sessions WHERE expire > NOW();"
```

## Getting Help

```bash
# View main install script help
sudo /opt/edl-manager-deploy/deploy/install-rhel.sh --help

# Check Node.js version
node --version

# Check PostgreSQL version
psql --version

# Check Apache version
httpd -v

# System information
cat /etc/redhat-release
uname -a
```

## Emergency Procedures

### Complete Service Reset

```bash
# Stop service
sudo systemctl stop edlmanager

# Clear logs
sudo journalctl --vacuum-time=1s

# Restart service
sudo systemctl start edlmanager
```

### Rollback Update

```bash
# If you have a backup of the old version
sudo systemctl stop edlmanager
sudo rm -rf /opt/EDLManager
sudo cp -r /path/to/backup/EDLManager /opt/EDLManager
sudo chown -R edlmgr:edlmgr /opt/EDLManager
sudo systemctl start edlmanager
```

## Quick Links

- Application: `https://your-server.com/edl/`
- Admin Panel: `https://your-server.com/edl/admin` (if implemented)
- Health Check: `http://127.0.0.1:3010/edl/`
- Firewall Lists: `https://your-server.com/edl/<slug>.txt`

---

**Last Updated**: June 2026  
**For**: EDL Manager on RHEL 9.7
