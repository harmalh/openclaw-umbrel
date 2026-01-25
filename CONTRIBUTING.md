# Contributing to Clawdbot for Umbrel

This project packages [Clawdbot](https://github.com/clawdbot/clawdbot) for the Umbrel App Store.

## Development

### Local Development

```bash
# Build image
docker build -t clawdbot-umbrel:dev .

# Run locally
docker run -it --rm \
  -p 18789:18789 \
  -v $(pwd)/test-data:/data \
  -e CLAWDBOT_GATEWAY_TOKEN=dev-token \
  clawdbot-umbrel:dev
```

### Testing Changes

1. Modify Dockerfile or entrypoint.sh
2. Rebuild image
3. Test locally with docker run
4. Test on actual Umbrel hardware

## License

MIT License - see LICENSE file.
