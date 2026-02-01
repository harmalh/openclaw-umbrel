# Clawdbot for Umbrel

Run [Clawdbot](https://clawd.bot) - your personal AI assistant control plane - on your Umbrel home server.

## Overview

This repository contains everything needed to:

1. **Build** a multi-arch Docker image optimized for Umbrel (ARM64 + AMD64)
2. **Package** Clawdbot as an Umbrel app with proper persistence and authentication
3. **Submit** to the Umbrel App Store
4. **Automate** updates when new Clawdbot versions are released

---

## Automated Update Pipeline

This repository includes a fully automated pipeline that:

1. **Detects** new upstream Clawdbot releases (every 6 hours)
2. **Builds** multi-arch Docker images (amd64 + arm64)
3. **Updates** the Umbrel App Store PR with the new version
4. **Validates** changes with the Umbrel linter before submitting
5. **Waits** for the Umbrel App Store's lint checks to pass

### Pipeline Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  GitHub Release │────▶│   Build Image   │────▶│  Update Umbrel  │
│    Detection    │     │   (Multi-Arch)  │     │    App Store    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
   Every 6 hours          GHCR Push            PR to umbrel-apps
   or Manual             + Digest Pin          + Lint + Wait
```

### Running the Pipeline Manually

1. Go to **Actions** > **Build and Push Image**
2. Click **Run workflow**
3. Optionally specify a version (e.g., `v2026.1.24`) or leave blank for latest
4. Check "Force build" if the version already exists
5. The update workflow will trigger automatically after build

### Required Secrets

Configure these in your GitHub repository settings (**Settings > Secrets and variables > Actions**):

| Secret | Purpose | Required For |
|--------|---------|--------------|
| `GITHUB_TOKEN` | Auto-provided by GitHub. Used for GHCR push and repository_dispatch. | Build workflow |
| `UMBREL_APPS_PAT` | Personal Access Token with `repo` scope for your `umbrel-apps` fork. Used to push branches and create PRs. | Update workflow |

**Creating `UMBREL_APPS_PAT`:**
1. Go to GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
2. Generate new token with `repo` scope
3. Add as repository secret named `UMBREL_APPS_PAT`

### Maintenance Rules

#### Fields That Change on Updates (Safe to Automate)

| File | Field | Description |
|------|-------|-------------|
| `docker-compose.yml` | `services.gateway.image` | Updated to new version with digest pin |
| `umbrel-app.yml` | `version` | Semantic version without `v` prefix |
| `umbrel-app.yml` | `releaseNotes` | Auto-generated update note |

#### Fields That Should NEVER Be Overwritten (Protected)

These fields are set by the Umbrel team during initial PR review or contain app-specific configuration:

| File | Field | Reason |
|------|-------|--------|
| `umbrel-app.yml` | `id` | Unique app identifier |
| `umbrel-app.yml` | `name` | Display name |
| `umbrel-app.yml` | `tagline` | Short description |
| `umbrel-app.yml` | `category` | App Store category |
| `umbrel-app.yml` | `port` | Assigned port number |
| `umbrel-app.yml` | `description` | Full description |
| `umbrel-app.yml` | `developer` | Developer attribution |
| `umbrel-app.yml` | `website` | Official website |
| `umbrel-app.yml` | `gallery` | Screenshot images |
| `umbrel-app.yml` | `submission` | PR link |
| `docker-compose.yml` | Everything except `image` | Service configuration |

### Runbook: Verifying Local Umbrel vs App Store

If you suspect your local Umbrel is running a different version than the App Store PR:

**1. Check the running image on your Umbrel:**
```bash
# SSH into Umbrel
ssh umbrel@umbrel.local

# Get the image digest currently running
sudo docker inspect clawdbot_gateway_1 --format '{{.Image}}' | xargs sudo docker inspect --format '{{index .RepoDigests 0}}'
```

**2. Get the PR's expected digest:**
```bash
# From the PR's docker-compose.yml, look for the @sha256:... part
# Example: ghcr.io/harmalh/clawdbot-umbrel:v2026.1.24@sha256:abc123...
```

**3. Compare the digests:**
- If they match: Your local install matches the PR ✅
- If they differ: You're running a different version

**4. Common mismatch causes:**
- Running a different image entirely (e.g., `ghcr.io/zot24/clawdbot-docker`)
- Running `:latest` tag instead of pinned version
- Local manual installation with different image source

**5. To align with App Store version:**
```bash
# Update the docker-compose.yml in your local app-data
sudo nano ~/umbrel/app-data/clawdbot/docker-compose.yml
# Change the image line to match the PR's pinned image

# Restart the app
sudo ~/umbrel/scripts/app restart clawdbot
```

---

## Quick Start (Local Testing)

```bash
# 1. Build the image locally
docker build -t clawdbot-umbrel:local .

# 2. Copy the umbrel-app folder to your Umbrel
rsync -av umbrel-app/clawdbot/ umbrel@umbrel.local:/home/umbrel/umbrel/app-data/clawdbot/

# 3. Install via Umbrel CLI
ssh umbrel@umbrel.local "umbreld client apps.install.mutate --appId clawdbot"

# 4. Open from Umbrel Web UI (not direct URL!)
# Go to http://umbrel.local → click Clawdbot → enter your Umbrel app password as token
```

---

## Fresh Install Testing (Web UI)

To test like a real App Store user would experience (catches first-run bugs):

### 1. Backup Your Data (Optional but Recommended)

Before wiping, save your existing config, workspace, and sessions:

```bash
# SSH into Umbrel
ssh umbrel@umbrel.local

# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
tar -czvf ~/clawdbot-backup-${TIMESTAMP}.tar.gz -C ~/umbrel/app-data/clawdbot data/

# Download to your PC (run from your local machine)
scp umbrel@umbrel.local:~/clawdbot-backup-*.tar.gz ./
```

### 2. Uninstall and Wipe Data

```bash
# Uninstall the app
umbreld client apps.uninstall.mutate --appId clawdbot

# Wipe persistent data for a truly fresh start
sudo rm -rf ~/umbrel/app-data/clawdbot/data
```

### 3. Update Image and Reinstall

```bash
# Update the image reference (replace IMAGE_REF with the actual reference)
sed -i 's|image:.*|image: IMAGE_REF|' ~/umbrel/app-data/clawdbot/docker-compose.yml

# Reinstall (creates fresh data directory)
umbreld client apps.install.mutate --appId clawdbot
```

### 4. Verify from Umbrel Web UI

1. Open the **Umbrel Web UI** at http://umbrel.local
2. Navigate to the **Clawdbot** app and click to open
3. When prompted, enter your **Umbrel app password** as the token (see [Token Copy Flow](#10-token-copy-flow))
4. Configure an LLM backend (e.g., Anthropic, OpenAI, or local Ollama)
5. Send a test chat message
6. Confirm no "Missing workspace template" errors occur

### 5. Restore Backup (If Needed)

```bash
# Stop the app
umbreld client apps.stop.mutate --appId clawdbot

# Extract backup (replace TIMESTAMP with your backup filename)
tar -xzvf ~/clawdbot-backup-TIMESTAMP.tar.gz -C ~/umbrel/app-data/clawdbot/

# Restart the app
umbreld client apps.start.mutate --appId clawdbot
```

---

## Common Pitfalls and Issues

### 1. HTTP + WebCrypto Security Context (CRITICAL)

**Problem**: Umbrel serves apps over plain HTTP (`http://umbrel.local:<port>`). Browsers treat HTTP as a "non-secure context" and block certain WebCrypto APIs. Clawdbot's Control UI uses device identity for security and may refuse to load.

**Solution**: The entrypoint automatically sets `gateway.controlUi.allowInsecureAuth: true` in the config. This allows token-based authentication over HTTP.

**Security Note**: This weakens browser-side protections. Keep your Umbrel LAN-only and always use token auth.

### 2. Gateway Bind/Auth Guardrail

**Problem**: Clawdbot refuses to start if bound beyond loopback (`--bind lan`) without authentication configured.

**Symptoms**:
- Gateway fails to start with auth-related errors
- Control UI shows "unauthorized" or WebSocket error 1008

**Solution**: Always set `CLAWDBOT_GATEWAY_TOKEN`. On Umbrel, this is automatically set to `$APP_PASSWORD`. Copy the app password from Umbrel's UI and paste it into the Control UI's token field.

### 3. Interactive Onboarding Wizard

**Problem**: Clawdbot's normal installation uses an interactive CLI wizard (`clawdbot onboard`). This doesn't work in Umbrel's headless Docker environment.

**Solution**: The entrypoint script automatically creates a minimal config on first run, bypassing the wizard. Users configure everything through the Control UI instead.

### 4. Container Chrome/Browser Issues

**Problem**: Some Clawdbot skills use browser automation (Puppeteer). Container environments often lack proper Chrome binaries or display servers.

**Solution**: Browser automation is disabled by default (`browser.enabled: false`). Enable only if you add Chrome to the image.

### 5. Multi-Architecture Builds

**Problem**: Umbrel runs on Raspberry Pi (ARM64) and x86 PCs (AMD64). Single-arch images fail on mismatched hardware.

**Solution**: Always build multi-arch images:

```bash
docker buildx build --platform linux/arm64,linux/amd64 \
  -t ghcr.io/<owner>/clawdbot-umbrel:v1.0.0 \
  --push .
```

### 6. Image Digest Pinning

**Problem**: Umbrel requires images pinned by SHA256 digest for reproducibility. Using `:latest` or version tags alone may be rejected.

**Solution**: After pushing, get the manifest digest and update `docker-compose.yml`:

```yaml
image: ghcr.io/<owner>/clawdbot-umbrel:v1.0.0@sha256:abc123...
```

### 7. UID 1000 Permissions

**Problem**: Umbrel containers should run as UID 1000. Running as root causes permission issues with mounted volumes.

**Solution**: The Dockerfile creates a `clawdbot` user with UID 1000 and switches to it in the final stage.

### 8. Data Persistence

**Problem**: Umbrel destroys container data on uninstall. If you reinstall, all config and conversations are lost.

**Important**: All persistent data lives in `${APP_DATA_DIR}/data` which maps to:
- `/data/.clawdbot/` - Clawdbot config, sessions, agent state
- `/data/clawd/` - Agent workspace (memory, skills, files)
- `/data/logs/` - Persistent log files

**Backup**: Regularly backup `${APP_DATA_DIR}/data` if you have important conversations or configurations.

### 9. Port Conflicts

**Problem**: The default Clawdbot port (18789) might conflict with other services.

**Solution**: The internal port stays 18789, but Umbrel exposes it on 30189 (configurable in `umbrel-app.yml`). The `app_proxy` handles the translation.

### 10. Token Copy Flow

**Problem**: Users don't know how to authenticate with the Control UI on first run.

**Important**: On first run, when you open Clawdbot from the Umbrel Web UI, the Control UI will prompt for a token. This is a one-time setup step.

**Flow**:
1. Install Clawdbot from Umbrel App Store (or manually)
2. Open the app **from the Umbrel Web UI** (not via direct URL)
3. The Control UI will show a token prompt
4. Find the app password in Umbrel UI: click the Clawdbot app card, look for "Default Password" or credentials
5. Paste the password as the token in Control UI's login prompt
6. Control UI stores the token in browser localStorage for future visits

**Note**: The token is set to `${APP_PASSWORD}` (Umbrel's app password) via the `CLAWDBOT_GATEWAY_TOKEN` environment variable. You only need to enter it once per browser.

---

## Useful Information from Clawdbot Documentation

### Runtime Requirements

- **Node.js**: Version 22 or higher (included in image)
- **Memory**: 512MB minimum, 1GB recommended
- **CPU**: 1 core minimum
- **Disk**: 500MB for base, more for workspace/memory

### Data Locations

| Path | Purpose |
|------|---------|
| `/data/.clawdbot/clawdbot.json` | Main configuration (JSON5, hot-reloaded) |
| `/data/.clawdbot/sessions.json` | Session store (per-sender context) |
| `/data/.clawdbot/agents/<id>/` | Per-agent state and auth profiles |
| `/data/clawd/` | Agent workspace (memory markdown files, skills) |
| `/data/logs/clawdbot.log` | Persistent log file |

### Configuration Format

Clawdbot uses JSON5 (JSON with comments and trailing commas). Example:

```json5
{
  // Gateway settings
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "token": "${CLAWDBOT_GATEWAY_TOKEN}"  // Env var substitution
    },
    "controlUi": {
      "allowInsecureAuth": true  // Required for HTTP
    }
  },
  
  // Agent defaults
  "agents": {
    "defaults": {
      "workspace": "/data/clawd",
    }
  },
}
```

### Environment Variable Substitution

Config values can reference environment variables using `${VAR_NAME}` syntax. The Gateway resolves these at startup.

### Hot Reload

Config changes are hot-reloaded. Edit via Control UI (`config.set`, `config.apply`) or directly modify the JSON5 file.

### Supported Messaging Platforms

| Platform | Auth Method |
|----------|-------------|
| WhatsApp | QR code (via Control UI) |
| Telegram | Bot token |
| Discord | Bot token + application ID |
| Slack | OAuth app credentials |
| Signal | Linked device (QR) |
| iMessage | macOS only (not available in container) |
| Web Chat | Built into Control UI |

### Supported AI Providers

| Provider | Configuration |
|----------|---------------|
| Anthropic (Claude) | API key |
| OpenAI (GPT-4, etc.) | API key |
| Local LLMs (Ollama) | Base URL |

---

## Persistent Logging

### Log Location

All logs are written to `/data/logs/clawdbot.log` inside the container, which maps to `${APP_DATA_DIR}/data/logs/clawdbot.log` on the Umbrel host.

### Viewing Logs

**From Umbrel host**:
```bash
# Tail live logs
tail -f ~/umbrel/app-data/clawdbot/data/logs/clawdbot.log

# View last 100 lines
tail -100 ~/umbrel/app-data/clawdbot/data/logs/clawdbot.log
```

**Via Docker**:
```bash
# Container stdout (also logged to file)
docker logs -f clawdbot_gateway_1

# Or use Umbrel's app logs feature in the UI
```

### Log Rotation

The default setup uses `tee` to write to both stdout and the log file. For production use, consider adding logrotate:

```bash
# /etc/logrotate.d/clawdbot
/home/umbrel/umbrel/app-data/clawdbot/data/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
```

### Debug Logging

For troubleshooting, set `logging.level: "debug"` in the config:

```json5
{
  "logging": {
    "file": "/data/logs/clawdbot.log",
    "level": "debug"
  }
}
```

Or via environment variable:
```bash
CLAWDBOT_LOG_LEVEL=debug
```

---

## Health Check

### Built-in Health Endpoint

The Clawdbot Gateway exposes a health endpoint at `/health` that returns status information.

**Check from host**:
```bash
curl http://umbrel.local:30189/health
```

**Expected response**:
```json
{
  "ok": true,
  "ts": 1706123456789,
  "durationMs": 45,
  "channels": { ... },
  "heartbeatSeconds": 60,
  "defaultAgentId": "default",
  "agents": [ ... ],
  "sessions": { ... }
}
```

### Docker Healthcheck

**For Umbrel deployments**: Healthchecks are **disabled** in the docker-compose.yml because:
- Umbrel's `app_proxy` service handles health monitoring
- Docker healthchecks can cause lock conflicts with gateway lock files (`gateway.*.lock`)
- The manual setup guide uses `--no-healthcheck` to avoid these issues

**For standalone deployments**: You can add a healthcheck to docker-compose.yml if needed:

```yaml
healthcheck:
  test: ["CMD", "curl", "-sf", "http://127.0.0.1:18789/health"]
  interval: 60s  # Increased to reduce lock contention
  timeout: 10s
  start_period: 120s  # Increased to allow full initialization
  retries: 2
```

### Checking Container Health

**Via Umbrel**: Umbrel's app_proxy monitors the service automatically.

**Manual check**:
```bash
# Check if gateway is responding
curl http://umbrel.local:30189/health

# Check container status
docker ps | grep clawdbot

# View logs
docker logs clawdbot_gateway_1
```

### CLI Health Command

Inside the container (or with the CLI installed):

```bash
# Basic health check
node /app/dist/index.js health

# JSON output
node /app/dist/index.js health --json

# Verbose with probe timings
node /app/dist/index.js health --verbose
```

---

## Building Multi-Arch Images

### Prerequisites

```bash
# Create buildx builder
docker buildx create --name multiarch --use

# Bootstrap the builder
docker buildx inspect --bootstrap
```

### Build and Push

```bash
# Build for both architectures and push
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --build-arg CLAWDBOT_VERSION=v1.0.0 \
  -t ghcr.io/<owner>/clawdbot-umbrel:v1.0.0 \
  --push .

# Get the manifest digest
docker buildx imagetools inspect ghcr.io/<owner>/clawdbot-umbrel:v1.0.0
```

### Local Build (Single Arch)

```bash
# Build for current architecture only
docker build -t clawdbot-umbrel:local .

# Run locally for testing
docker run -it --rm \
  -p 18789:18789 \
  -v ./data:/data \
  -e CLAWDBOT_GATEWAY_TOKEN=test-token \
  clawdbot-umbrel:local
```

---

## GitHub Actions Automation

### Workflow A: Build on Upstream Release

See `.github/workflows/build-image.yml`:

- **Schedule**: Checks for new releases every 6 hours
- **Trigger**: Manual via `workflow_dispatch` with optional version override
- **Actions**:
  - Fetches latest upstream Clawdbot release (with validation)
  - Builds multi-arch image (amd64 + arm64) via buildx
  - Pushes to GHCR with version tag + `latest`
  - Validates manifest digest format
  - Triggers Update Umbrel App workflow via `repository_dispatch`

### Workflow B: Update Umbrel App

See `.github/workflows/update-umbrel-app.yml`:

- **Trigger**: `repository_dispatch` from build workflow, or manual `workflow_dispatch`
- **Actions**:
  - Syncs fork with `upstream/master` (preserves Umbrel team changes)
  - Updates ONLY safe fields (`image`, `version`, `releaseNotes`)
  - Verifies no unexpected files changed
  - Runs `umbrel-cli lint` before committing
  - Creates/updates PR to `getumbrel/umbrel-apps`
  - Waits for remote "Lint apps" check to pass
- **Safety Features**:
  - Uses `--force-with-lease` instead of `--force` for pushes
  - Validates digest format before updating files
  - Explicit verification of changed files

---

## Troubleshooting

### "Unauthorized" or WebSocket 1008

1. Ensure `CLAWDBOT_GATEWAY_TOKEN` is set
2. Copy the Umbrel app password and paste as token
3. Check config has `gateway.controlUi.allowInsecureAuth: true`

### Control UI Won't Load

1. Check container is healthy: `docker ps`
2. Check logs: `docker logs clawdbot_gateway_1`
3. Verify port mapping: `curl http://umbrel.local:30189/health`

### Gateway Won't Start

1. Check config syntax: JSON5 must be valid
2. Look for auth/bind errors in logs
3. Ensure `/data` is writable

### Lost Configuration After Update

1. Config lives in `/data/.clawdbot/clawdbot.json`
2. Ensure volume is correctly mounted
3. Check Umbrel didn't recreate the app data directory

### WhatsApp/Telegram Not Connecting

1. Open Control UI, go to Channels
2. Re-scan QR code or re-enter token
3. Check channel-specific logs in debug mode

---

## License

Clawdbot is MIT licensed. This Umbrel packaging is community-maintained.

## Links

- [Clawdbot Documentation](https://docs.clawd.bot)
- [Clawdbot GitHub](https://github.com/clawdbot/clawdbot)
- [Umbrel App Store Guide](https://github.com/getumbrel/umbrel-apps)
