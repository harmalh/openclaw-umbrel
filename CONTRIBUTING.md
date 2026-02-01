# Contributing to OpenClaw for Umbrel

## Submitting to Umbrel App Store

Follow these steps to submit OpenClaw to the official Umbrel App Store.

### Prerequisites

1. A working OpenClaw Umbrel image published to GHCR
2. The app tested on both ARM64 and AMD64
3. A GitHub account

### Step 1: Prepare Assets

The Umbrel App Store requires certain assets:

#### App Icon

- Format: PNG or SVG
- Size: 256x256 pixels minimum
- Location: Host publicly (GitHub raw, CDN, etc.)
- Current: Using OpenClaw's official logo

#### Gallery Images (Recommended)

- Format: PNG or JPEG
- Size: 1280x800 pixels
- Show the Control UI and key features
- Add to `umbrel-app.yml` gallery array

### Step 2: Get Image Digest

After building and pushing your image:

```bash
# Get the manifest digest
docker buildx imagetools inspect ghcr.io/<owner>/openclaw-umbrel:v1.0.0

# Output includes:
# Digest: sha256:abc123...
```

### Step 3: Update docker-compose.yml

Replace the image line with the digest-pinned version:

```yaml
gateway:
  image: ghcr.io/<owner>/openclaw-umbrel:v1.0.0@sha256:abc123...
```

### Step 4: Fork umbrel-apps

1. Go to https://github.com/getumbrel/umbrel-apps
2. Click "Fork"
3. Clone your fork locally

### Step 5: Add the App

```bash
cd umbrel-apps

# Copy the app definition
cp -r /path/to/openclaw-umbrel/umbrel-app/openclaw .

# Verify structure
ls openclaw/
# Should show: docker-compose.yml  exports.sh  umbrel-app.yml
```

### Step 6: Create Pull Request

1. Create a branch: `git checkout -b add-openclaw`
2. Commit: `git add openclaw && git commit -m "Add OpenClaw app"`
3. Push: `git push origin add-openclaw`
4. Open PR on GitHub

### PR Template

```markdown
## App Submission: OpenClaw

### Description

OpenClaw is a self-hosted AI assistant control plane that connects to
multiple messaging platforms and AI providers.

### Checklist

- [x] App is open source and MIT licensed
- [x] Multi-arch image (arm64 + amd64)
- [x] Image pinned by digest
- [x] Tested on Raspberry Pi 4
- [x] Tested on x86
- [x] Port doesn't conflict with existing apps
- [x] App uses app_proxy for routing
- [x] Data persists in APP_DATA_DIR

### Testing

Tested on:
- umbrelOS 1.x on Raspberry Pi 4 (8GB)
- umbrelOS 1.x on Intel NUC

### Screenshots

[Add Control UI screenshots here]
```

### Step 7: Address Review Feedback

Umbrel maintainers may request:

1. **Smaller image size**: Use multi-stage builds, slim base images
2. **Different port**: If conflicts exist
3. **Security improvements**: Non-root user, proper permissions
4. **Documentation**: Better description, gallery images

### Maintenance

After acceptance:

1. Monitor upstream OpenClaw releases
2. Build and push new images
3. Update digest in docker-compose.yml
4. Open update PR

The GitHub Actions workflows automate most of this process.

## Development

### Local Development

```bash
# Build image
docker build -t openclaw-umbrel:dev .

# Run locally
docker run -it --rm \
  -p 18789:18789 \
  -v $(pwd)/test-data:/data \
  -e CLAWDBOT_GATEWAY_TOKEN=dev-token \
  openclaw-umbrel:dev
```

### Testing Changes

1. Modify Dockerfile or entrypoint.sh
2. Rebuild image
3. Test locally with docker run
4. Test on actual Umbrel hardware

### Updating OpenClaw Version

1. Update `OPENCLAW_VERSION` build arg
2. Test thoroughly
3. Push new image
4. Update Umbrel app definition

## Code of Conduct

Be respectful and constructive. This is a community project.

## License

MIT License - see LICENSE file.
