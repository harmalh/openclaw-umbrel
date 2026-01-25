# Clawdbot for Umbrel

Run [Clawdbot](https://clawd.bot) - your personal AI assistant control plane - on your Umbrel home server.

## Overview

This repository contains everything needed to:

1. **Build** a multi-arch Docker image optimized for Umbrel (ARM64 + AMD64)
2. **Package** Clawdbot as an Umbrel app with proper persistence and authentication
3. **Submit** to the Umbrel App Store
4. **Automate** updates when new Clawdbot versions are released

## Credits

This project is based on [Clawdbot](https://github.com/clawdbot/clawdbot) - a self-hosted AI assistant control plane.
Donate to the creator of Clawdbot if you like his work: https://github.com/sponsors/steipete. 

## Quick Start (Local Testing)

```bash
# 1. Build the image locally
docker build -t clawdbot-umbrel:local .

# 2. Copy the umbrel-app folder to your Umbrel
rsync -av umbrel-app/clawdbot/ umbrel@umbrel.local:/home/umbrel/umbrel/app-data/clawdbot/

# 3. Install via Umbrel CLI
ssh umbrel@umbrel.local "umbreld client apps.install.mutate --appId clawdbot"
```

## License

MIT License - see LICENSE file.

## Links

- [Clawdbot Documentation](https://docs.clawd.bot)
- [Clawdbot GitHub](https://github.com/clawdbot/clawdbot)
- [Umbrel App Store Guide](https://github.com/getumbrel/umbrel-apps)
