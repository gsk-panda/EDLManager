# EDL Manager - Quick Start Guide

## 🚀 New Engineer Onboarding

Welcome! This guide gets you up and running in 30 minutes.

---

## What This Application Does

**EDL Manager** serves threat intelligence lists to Palo Alto firewalls. Think of it as a centralized database of IPs/domains/URLs to block or allow, with a web interface for management.

```
Firewalls → Fetch lists → From public .txt URLs → Served by EDL Manager
Security Team → Manages entries → Via web UI → Updates live lists
```

---

## 🎯 Day 1 Checklist

### 1. Read the Documentation (30 minutes)
- [ ] `README.md` - Project overview
- [ ] `HANDOFF.md` - Complete handoff documentation (this is your bible)
- [ ] `deploy/QUICK-REFERENCE.md` - Common commands

### 2. Get Local Development Running (15 minutes)

```bash
# Clone repo
git clone https://github.com/gsk-panda/EDLManager
cd EDLManager

# Copy environment template
cp .env.example .env

# Start with Docker
docker-compose up -d

# View logs
docker-compose logs -f app

# Open browser
# URL: http://localhost:3000
# Login: admin / ChangeMe123!
```

### 3. Explore the Application (15 minutes)
- [ ] Log in with default credentials
- [ ] Create a test EDL (try "test-ips" as name, type "IP")
- [ ] Add some IP addresses (e.g., `10.0.0.1`, `192.168.1.0/24`)
- [ ] Try the search box in the header
- [ ] View the public feed URL (click "view raw")
- [ ] Check the audit log (scroll down on EDL detail page)

### 4. Access Production (Read-Only) (10 minutes)

```bash
# SSH to production server
ssh user@production-server

# Check service status
sudo systemctl status edlmanager

# Watch logs (Ctrl+C to exit)
sudo journalctl -u edlmanager -f

# View configuration (note the paths and ports)
sudo cat /etc/edlmanager/edlmanager.env
```

---

## 📁 Key Files You'll Work With

### Application Code
```
src/routes/edls.js     ← Main business logic (EDL CRUD, search)
src/routes/serve.js    ← Public feed serving (what firewalls fetch)
src/auth.js            ← Login and authentication
views/edls.ejs         ← Dashboard page
views/edl.ejs          ← EDL detail page with entries
```

### Configuration
```
/etc/edlmanager/edlmanager.env           ← Production config (passwords here!)
/etc/systemd/system/edlmanager.service   ← Service definition
/opt/EDLManager/                         ← Application files
```

### Documentation
```
README.md              ← Project overview
HANDOFF.md             ← Complete handoff guide (read this fully!)
deploy/FULL-INSTALL.md ← Installation procedures
SEARCH-FEATURE.md      ← Search functionality
```

---

## 🔧 Common Tasks

### View Production Logs
```bash
sudo journalctl -u edlmanager -f
```

### Restart Service
```bash
sudo systemctl restart edlmanager
sudo systemctl status edlmanager
```

### Query Database
```bash
sudo -u postgres psql edl

# Useful queries:
SELECT * FROM edls;
SELECT * FROM edl_entries WHERE edl_id = 1;
SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 10;
```

### Deploy Code Update
```bash
# On server
cd /tmp
rm -rf EDLManager
git clone https://github.com/gsk-panda/EDLManager
cd EDLManager
sudo cp -r src/* /opt/EDLManager/src/
sudo cp -r views/* /opt/EDLManager/views/
sudo systemctl restart edlmanager
```

### Add a User (Local Auth Mode)
```bash
cd /opt/EDLManager
sudo -u edlmgr node scripts/create-user.js \
  --email user@example.com \
  --name "User Name" \
  --role editor
```

---

## 🏗️ Architecture (Simplified)

```
┌─────────────────────────────────────────────┐
│  Internet (Palo Alto Firewalls)             │
└──────────────────┬──────────────────────────┘
                   │ HTTPS
                   ↓
┌─────────────────────────────────────────────┐
│  Apache (Reverse Proxy, TLS Termination)    │
│  - Serves https://domain.com/edl/*          │
│  - Proxies to Node.js on 127.0.0.1:6032     │
└──────────────────┬──────────────────────────┘
                   │ HTTP (localhost only)
                   ↓
┌─────────────────────────────────────────────┐
│  EDL Manager (Node.js/Express)              │
│  - Web UI for management (authenticated)    │
│  - Public .txt feeds (unauthenticated)      │
│  - Systemd service as "edlmgr" user         │
└──────────────────┬──────────────────────────┘
                   │ PostgreSQL protocol
                   ↓
┌─────────────────────────────────────────────┐
│  PostgreSQL Database                         │
│  - Tables: edls, edl_entries, users, etc.   │
│  - Stores all data and audit logs           │
└─────────────────────────────────────────────┘
```

---

## 🐛 Quick Troubleshooting

### Service won't start?
```bash
sudo journalctl -u edlmanager -n 50
# Look for error messages (database connection, port in use, etc.)
```

### Can't log in (CSRF error)?
```bash
# Check trust proxy setting (must be "1" behind Apache)
sudo grep TRUST_PROXY /etc/edlmanager/edlmanager.env
```

### Changes not showing up?
```bash
# Did you restart the service?
sudo systemctl restart edlmanager
```

### Database issues?
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check if database exists
sudo -u postgres psql -c "\l" | grep edl
```

---

## 📞 Getting Help

1. **Check logs first**: `sudo journalctl -u edlmanager -f`
2. **Review HANDOFF.md**: Comprehensive troubleshooting section
3. **Search GitHub Issues**: (if public repo)
4. **Ask previous engineer**: (transition period)

---

## 🎓 Learning Path

### Week 1: Understanding
- Set up local dev environment
- Read all documentation
- Explore codebase structure
- Shadow production operations

### Week 2: Hands-On
- Make small UI changes locally
- Review audit logs and database
- Practice common operations
- Deploy a test update

### Week 3: Independence
- Handle a real support request
- Deploy a production update
- Troubleshoot an issue
- Plan an enhancement

---

## ⚠️ Important Things to Remember

| What | Why |
|------|-----|
| **Never commit `.env` files** | Contains secrets (passwords, session keys) |
| **Always test locally first** | Docker Compose environment available |
| **TRUST_PROXY=1 is required** | Running behind Apache reverse proxy |
| **Public feeds are unauthenticated** | By design - firewalls fetch without auth |
| **All changes are audited** | Don't worry, everything is logged |
| **Port 6032 in production** | Not the default 3010 |
| **Restart after config changes** | Service doesn't auto-reload |

---

## 🔗 Quick Links

- **Repository**: https://github.com/gsk-panda/EDLManager
- **Full Handoff**: See `HANDOFF.md`
- **Deployment Guide**: See `deploy/FULL-INSTALL.md`
- **Search Feature**: See `SEARCH-FEATURE.md`

---

## Next Steps

1. ✅ Read this guide
2. ✅ Set up local development
3. ✅ Access production (read-only)
4. ✅ Read `HANDOFF.md` thoroughly
5. ✅ Shadow operations for first week
6. ✅ Start making changes in week 2

**You've got this! The application is solid and well-documented. Take it one step at a time.**

---

**Questions? Start with the logs, then check HANDOFF.md, then ask for help.**
