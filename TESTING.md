# Testing Clawdbot on Umbrel

This guide covers how to test the Clawdbot Umbrel app locally.

## Prerequisites

- An Umbrel device (Raspberry Pi 4, x86 PC, or VM)
- SSH access to your Umbrel
- Docker installed on your development machine

## Quick Test

```bash
# Build
docker build -t clawdbot-umbrel:test .

# Run
docker run -d --name clawdbot-test \
  -p 18789:18789 \
  -e CLAWDBOT_GATEWAY_TOKEN=test-token \
  clawdbot-umbrel:test

# Check health
curl http://localhost:18789/health

# View logs
docker logs clawdbot-test

# Cleanup
docker rm -f clawdbot-test
```

## Verification Checklist

- [ ] Container starts without errors
- [ ] Health endpoint responds
- [ ] Control UI accessible at port 18789
- [ ] Token authentication works
- [ ] Config persists across restarts
