# Conflict Detection and Automatic Cleanup

The `full-install.sh` script includes comprehensive conflict detection to prevent issues when installing EDL Manager on servers that may already have services running at the `/edl` path or using the same port.

## What Gets Checked

Before installation begins, the script automatically scans for:

### 1. **Existing EDL Manager Service**
- Checks if `edlmanager.service` is running
- **Action**: Service is stopped and disabled before cleanup

### 2. **Apache Configuration Conflicts**
- Scans `/etc/httpd/conf.d/` for `ProxyPass` rules using your URL path
- Checks for `<Location>` blocks that might conflict
- Lists all files that reference the same path
- **Action**: Backs up old configs with timestamp before replacement

### 3. **Port Availability**
- Checks if the configured port (default: 3010) is already in use
- Shows which process is using the port
- **Action**: Warns you; manual resolution may be needed

### 4. **HTTP Endpoint Conflicts**
- Tests if a service is already responding at your target URL
- Tries both local (`http://localhost/edl`) and public URLs
- **Action**: Warns you before proceeding

### 5. **Running Web Services**
- Lists other Node.js, web, or app services currently running
- Helps identify potential conflicts
- **Action**: Informational only (doesn't stop these services)

## How Conflicts Are Displayed

When conflicts are detected, you'll see output like this:

```
═══════════════════════════════════════════════════════════════
                    ⚠  CONFLICTS DETECTED  ⚠
═══════════════════════════════════════════════════════════════
[WARN] Found 3 potential conflict(s) that need attention.

Actions that will be taken:
  - Existing edlmanager service will be stopped and replaced
  - Apache configs may need manual cleanup after installation
  - Port conflicts will need manual resolution

Do you want to continue despite these conflicts? (yes/no):
```

## Installation Behavior With Conflicts

### If You Type `yes` (Recommended)

The installation proceeds and automatically:

1. **Stops the edlmanager service**
   ```bash
   systemctl stop edlmanager
   systemctl disable edlmanager
   ```

2. **Backs up Apache configurations**
   ```
   /etc/httpd/conf.d/edlmanager-vhost.conf
     → /etc/httpd/conf.d/edlmanager-vhost.conf.backup-20260603-095800
   
   /etc/httpd/conf.d/edlmanager.conf.example
     → /etc/httpd/conf.d/edlmanager.conf.example.backup-20260603-095800
   ```

3. **Removes old installation directories**
   ```bash
   rm -rf /opt/EDLManager
   rm -rf /home/SNC/121135-adm/edl-manager
   ```

4. **Proceeds with fresh installation**

### If You Type `no`

The installation aborts with helpful guidance:

```
To resolve conflicts before installing:
  1. Stop conflicting services: systemctl stop <service-name>
  2. Remove conflicting Apache configs from /etc/httpd/conf.d/
  3. Free up port 3010 if it's in use
  4. Re-run this installation script
```

## Handling Specific Conflict Types

### Conflict: Port Already in Use

**Symptoms:**
```
[WARN] Port 3010 is already in use:
    LISTEN 0  128  127.0.0.1:3010  *:*  users:(("node",pid=1234,...))
```

**Solutions:**

**Option 1**: Use a different port
```bash
# When prompted, enter a different port
Application port [3010]: 3020
```

**Option 2**: Stop the conflicting process
```bash
# Identify the process
sudo ss -tlnp | grep :3010

# Stop it (if safe)
sudo kill <pid>

# Or stop the service
sudo systemctl stop <service-name>
```

### Conflict: Apache Config Using Same Path

**Symptoms:**
```
[WARN] Found Apache configurations already using /edl:
    - /etc/httpd/conf.d/old-edl-app.conf
```

**Solutions:**

**Option 1**: Let the installer back it up (Recommended)
- Type `yes` when prompted
- Old config is backed up with timestamp
- New config is installed

**Option 2**: Rename the conflicting config
```bash
sudo mv /etc/httpd/conf.d/old-edl-app.conf \
        /etc/httpd/conf.d/old-edl-app.conf.disabled

sudo systemctl reload httpd
```

**Option 3**: Use a different URL path
```bash
# When prompted, use a different path
Base URL [.../edl]: https://example.com/edl-manager
```

### Conflict: Service Already Responding at URL

**Symptoms:**
```
[WARN] Found existing service responding at /edl
```

**Solutions:**

**Option 1**: Stop the conflicting service
```bash
# Identify what's serving that path
curl -I https://your-server.com/edl

# Check Apache configs
grep -r "ProxyPass.*edl" /etc/httpd/conf.d/

# Stop the service or remove its config
```

**Option 2**: Use a different path
```bash
# When prompted
Base URL: https://example.com/edl-manager
```

## Restoring Backed-Up Configurations

If you need to rollback after installation:

### List All Backups
```bash
ls -lhtr /etc/httpd/conf.d/*.backup-*
```

### Restore a Specific Backup
```bash
# Copy backup back
sudo cp /etc/httpd/conf.d/edlmanager-vhost.conf.backup-20260603-095800 \
        /etc/httpd/conf.d/edlmanager-vhost.conf

# Test configuration
sudo apachectl configtest

# Reload Apache
sudo systemctl reload httpd
```

### Delete Old Backups
```bash
# Remove backups older than 30 days
sudo find /etc/httpd/conf.d/ -name "*.backup-*" -mtime +30 -delete

# Or remove all backups (careful!)
sudo rm /etc/httpd/conf.d/*.backup-*
```

## Advanced: Skipping Conflict Detection

If you're absolutely certain there are no conflicts and want to skip detection:

```bash
# Edit the script (not recommended)
# Comment out the "Conflict Detection" section (lines 196-296)
# Or set this before running:
export SKIP_CONFLICT_CHECK=1
```

**⚠️ Warning**: Skipping conflict detection can result in:
- Failed installation due to port conflicts
- Multiple services trying to serve the same path
- Apache configuration errors
- Data loss if old installations aren't properly cleaned up

## What Doesn't Get Checked

The script does **not** check for:
- Database conflicts (assumes you've provided correct credentials)
- Filesystem space (should be checked manually)
- SELinux policy conflicts (rare)
- Firewall rules (doesn't modify firewall)

Always ensure you have:
- At least 500 MB free space in `/opt`
- Correct database credentials
- Necessary firewall ports open (80/443 for Apache)

## Example: Clean Installation on Fresh Server

```bash
$ sudo ./deploy/full-install.sh

# No conflicts detected
[INFO] Will be serving at path: /edl
[INFO] Checking for conflicting systemd services...
[INFO] Checking Apache configurations for /edl...
[INFO] Checking if port 3010 is available...
✓ No conflicts detected. Safe to proceed.

═══════════════════════════════════════════════════════════════
Installation Summary
...
```

## Example: Installation With Conflicts

```bash
$ sudo ./deploy/full-install.sh

# Conflicts detected
[INFO] Will be serving at path: /edl
[WARN] edlmanager service is already running!
[INFO] This installation will stop and replace it.
[WARN] Found Apache configurations already using /edl:
    - /etc/httpd/conf.d/edlmanager-vhost.conf
[WARN] Port 3010 is already in use:
    LISTEN 0  128  127.0.0.1:3010  *:*  users:(("node",pid=12345,...))

╔═══════════════════════════════════════════════════════════════╗
║                    ⚠  CONFLICTS DETECTED  ⚠                  ║
╚═══════════════════════════════════════════════════════════════╝
[WARN] Found 3 potential conflict(s) that need attention.

Actions that will be taken:
  - Existing edlmanager service will be stopped and replaced
  - Apache configs may need manual cleanup after installation
  - Port conflicts will need manual resolution

[?] Do you want to continue despite these conflicts? (yes/no): yes

[INFO] Continuing installation - conflicts will be handled during cleanup...

# Cleanup phase
[INFO] Stopping existing edlmanager service...
✓ Stopped edlmanager service
[INFO] Disabling edlmanager service...
✓ Disabled edlmanager service
[INFO] Found old Apache configs, backing up...
  Backed up: /etc/httpd/conf.d/edlmanager-vhost.conf 
    → /etc/httpd/conf.d/edlmanager-vhost.conf.backup-20260603-095823
...
```

## Best Practices

1. **Review conflicts carefully** before proceeding
2. **Let the installer handle known conflicts** (it backs up configs safely)
3. **Resolve port conflicts manually** if possible before installation
4. **Keep backups** of backed-up Apache configs for at least 30 days
5. **Test after installation** using the verify-install.sh script
6. **Document custom changes** if you modify the default paths/ports

## Troubleshooting

### Script Says "No Conflicts" But Installation Fails

Check manually:
```bash
# Port in use?
sudo ss -tlnp | grep :3010

# Apache config valid?
sudo apachectl configtest

# Service already exists?
systemctl status edlmanager
```

### Old Service Still Running After Installation

```bash
# Force stop
sudo systemctl stop edlmanager
sudo systemctl disable edlmanager
sudo systemctl daemon-reload

# Verify
systemctl status edlmanager
```

### Apache Config Backup Filling Disk

```bash
# List backups by size
du -sh /etc/httpd/conf.d/*.backup-* | sort -h

# Remove old backups
sudo find /etc/httpd/conf.d/ -name "*.backup-*" -mtime +7 -delete
```

---

**For more information**, see:
- `FULL-INSTALL.md` - Complete installation guide
- `README.md` - Deployment scripts overview
- `QUICK-REFERENCE.md` - Post-installation operations
