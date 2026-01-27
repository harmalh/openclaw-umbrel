# Testing Clawdbot on Umbrel

This guide covers how to test the Clawdbot Umbrel app locally before submitting to the App Store.

## Prerequisites

- An Umbrel device (Raspberry Pi 4, x86 PC, or VM)
- SSH access to your Umbrel
- Docker installed on your development machine (for building)

## Option 1: Test with Local Image Build

### 1. Build the Image Locally

On your development machine:

```bash
cd /path/to/clawdbot-umbrel

# Build for your architecture
docker build -t clawdbot-umbrel:local .

# Or build multi-arch (requires buildx)
docker buildx build --platform linux/arm64,linux/amd64 \
  -t clawdbot-umbrel:local \
  --load .
```

### 2. Export and Transfer the Image

```bash
# Save the image to a tar file
docker save clawdbot-umbrel:local | gzip > clawdbot-umbrel.tar.gz

# Copy to Umbrel
scp clawdbot-umbrel.tar.gz umbrel@umbrel.local:~/
```

### 3. Load Image on Umbrel

```bash
ssh umbrel@umbrel.local

# Load the image
docker load < clawdbot-umbrel.tar.gz
```

### 4. Update docker-compose.yml for Local Testing

Edit `umbrel-app/clawdbot/docker-compose.yml`:

```yaml
gateway:
  # Use local image instead of GHCR
  image: clawdbot-umbrel:local
```

### 5. Copy App Definition to Umbrel

```bash
# From your development machine
rsync -av umbrel-app/clawdbot/ umbrel@umbrel.local:/home/umbrel/umbrel/app-data/clawdbot/
```

### 6. Install the App

```bash
ssh umbrel@umbrel.local

# Install via CLI
umbreld client apps.install.mutate --appId clawdbot
```

Or use the Umbrel web UI to install from "Available Apps".

## Option 2: Test with Published Image

If you've already pushed an image to GHCR:

### 1. Copy App Definition

```bash
rsync -av umbrel-app/clawdbot/ umbrel@umbrel.local:/home/umbrel/umbrel/app-data/clawdbot/
```

### 2. Install

```bash
ssh umbrel@umbrel.local
umbreld client apps.install.mutate --appId clawdbot
```

## Testing UI Override (Scroll/Header Fix)

The Docker image includes a CSS override that fixes UI issues when Clawdbot is embedded in Umbrel:
- Config page not scrolling
- Header text being clipped

### Build with Override (default)

```bash
# Build with UI override enabled (default)
docker build -t clawdbot-umbrel:local .

# Or explicitly enable
docker build --build-arg UMBREL_UI_OVERRIDE=1 -t clawdbot-umbrel:local .
```

### Build without Override (for testing)

```bash
# Build WITHOUT UI override (to reproduce the bug)
docker build --build-arg UMBREL_UI_OVERRIDE=0 -t clawdbot-umbrel:no-override .
```

### Verify UI Fix

After installing the patched image:

1. Open Clawdbot in Umbrel UI
2. Navigate to **Config** tab
3. Verify these behaviors:

**Config Page Scrolling:**
- [ ] The Config content area scrolls when content exceeds viewport
- [ ] Scroll with mouse wheel works
- [ ] Scrollbar appears on the right side of the config content
- [ ] Browser DevTools shows `.config-content` has `scrollTop` changing on scroll

**Header Visibility:**
- [ ] Page title "Config" is fully visible
- [ ] Page subtitle "Edit ~/.clawdbot/clawdbot.json safely." is fully visible
- [ ] No text is clipped or cut off

**Quick DevTools Check:**
```javascript
// Run in browser console on Config page
const content = document.querySelector('.config-content');
console.log('scrollHeight:', content.scrollHeight);
console.log('clientHeight:', content.clientHeight);
console.log('Can scroll:', content.scrollHeight > content.clientHeight);

// Test scroll programmatically
content.scrollTop = 200;
console.log('scrollTop after set:', content.scrollTop);
// Should be 200 (or close) if scrolling works
```

## Verification Checklist

After installation, verify these items:

### Basic Functionality

- [ ] App appears in Umbrel UI
- [ ] App starts without errors (`docker logs clawdbot_gateway_1`)
- [ ] Health check passes (`docker inspect clawdbot_gateway_1 --format='{{.State.Health.Status}}'`)
- [ ] Control UI is accessible at `http://umbrel.local:30189`

### Authentication

- [ ] Control UI prompts for token
- [ ] App password from Umbrel works as token
- [ ] Token is stored in browser (no re-prompt on refresh)

### Configuration

- [ ] Config file created at `/data/.clawdbot/clawdbot.json`
- [ ] Config is valid JSON5
- [ ] `allowInsecureAuth: true` is set
- [ ] Gateway binds to LAN

### UI (Config Page)

- [ ] Config page scrolls properly (see "Testing UI Override" section above)
- [ ] Header text is fully visible (not clipped)
- [ ] All config sections are accessible via sidebar navigation
- [ ] Config changes can be saved

### Persistence

- [ ] Restart app - config persists
- [ ] Update app - config persists
- [ ] Session data survives restart

### Logging

- [ ] Logs written to `/data/logs/clawdbot.log`
- [ ] Logs viewable via `docker logs`
- [ ] Log level configurable

### Platform Integration (Optional)

- [ ] Anthropic API key can be added
- [ ] Web chat works in Control UI
- [ ] WhatsApp QR scan works (if testing)

## Common Issues

### "Cannot connect to gateway"

1. Check container is running: `docker ps | grep clawdbot`
2. Check logs: `docker logs clawdbot_gateway_1`
3. Verify port: `curl http://127.0.0.1:18789/health`

### "Unauthorized" in Control UI

1. Check `CLAWDBOT_GATEWAY_TOKEN` is set
2. Use the Umbrel app password as token
3. Clear browser localStorage and retry

### Container Won't Start

1. Check config syntax: `cat /home/umbrel/umbrel/app-data/clawdbot/data/.clawdbot/clawdbot.json | jq .`
2. Check permissions: `ls -la /home/umbrel/umbrel/app-data/clawdbot/data/`
3. Check image exists: `docker images | grep clawdbot`

### Health Check Failing

1. Wait 60 seconds (start period)
2. Check curl is available in container
3. Verify gateway is binding correctly

## Uninstalling

```bash
# Via CLI
umbreld client apps.uninstall.mutate --appId clawdbot

# Or via Umbrel UI
```

**Warning**: Uninstalling removes all data including config and conversations!

## Debugging

### Enable Debug Logging

Edit config or set environment variable:

```json5
{
  "logging": {
    "level": "debug"
  }
}
```

### Attach to Container

```bash
docker exec -it clawdbot_gateway_1 /bin/bash
```

### View Real-time Logs

```bash
docker logs -f clawdbot_gateway_1
```

### Check Resource Usage

```bash
docker stats clawdbot_gateway_1
```
