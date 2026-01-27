# PR #4557 Update Guide

This document describes the exact changes needed to update [PR #4557](https://github.com/getumbrel/umbrel-apps/pull/4557) after building a new image with the Umbrel UI scroll/header fix.

## Overview

PR #4557 is the Clawdbot submission to the Umbrel App Store. After building an image that includes the UI fix, you need to update the PR with the new image digest.

## Required Changes

### 1. `clawdbot/docker-compose.yml`

Update the `image` line in the `gateway` service:

**Before:**
```yaml
gateway:
  image: ghcr.io/harmalh/clawdbot-umbrel:v2026.1.24@sha256:60c7f6e066702485acc9faa0abd0fc55ee5804fdd0f80015857136fa816fb9a1
```

**After (replace `NEW_DIGEST` with actual digest):**
```yaml
gateway:
  image: ghcr.io/harmalh/clawdbot-umbrel:v2026.1.24@sha256:NEW_DIGEST
```

### 2. `clawdbot/umbrel-app.yml` (Optional)

If this is an update to an existing PR (not a new submission), you may update the `releaseNotes` field:

**Before:**
```yaml
releaseNotes: ""
```

**After:**
```yaml
releaseNotes: "Fixed Config page scrolling and header visibility in Umbrel embedded context"
```

**Note:** For new submissions to the Umbrel App Store, `releaseNotes` should remain empty per Umbrel guidelines.

## How to Get the New Digest

### Option A: GitHub Actions (Automated)

1. Go to **Actions** > **Build and Push Image**
2. Click **Run workflow**
3. Set `clawdbot_version` to `v2026.1.24` (or your target version)
4. Check **Force build** (since the version tag may already exist)
5. Wait for the workflow to complete
6. The digest will be shown in the workflow summary

### Option B: Manual Build

```bash
# Build multi-arch image
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg CLAWDBOT_VERSION=v2026.1.24 \
  -t ghcr.io/harmalh/clawdbot-umbrel:v2026.1.24 \
  --push .

# Get the manifest digest
docker buildx imagetools inspect ghcr.io/harmalh/clawdbot-umbrel:v2026.1.24 \
  --format '{{json .Manifest.Digest}}'
```

## Suggested PR Comment

After pushing the update to the PR, add a comment explaining the change:

---

**Update: UI Fix for Embedded Context**

This update includes a CSS override that fixes UI issues when Clawdbot is displayed in Umbrel's `app_proxy` iframe:

**Issues Fixed:**
- Config page now scrolls properly (content was overflowing instead of scrolling)
- Page header text is no longer clipped

**Technical Details:**
- Added `patches/umbrel-control-ui.css` in the Docker build that overrides problematic CSS rules
- The fix mirrors changes already merged to upstream Clawdbot `main` branch
- Once upstream releases a version with these fixes, the override can be disabled

**Testing:**
- Verified on Umbrel (Raspberry Pi 4)
- Config page scroll works with mouse wheel and trackpad
- Header "Config" and subtitle are fully visible

**Changes in this update:**
- Updated Docker image digest (same version tag, includes CSS fix)

---

## Automated Updates

The `update-umbrel-app.yml` workflow will automatically:
1. Detect when a new image is built
2. Update the `docker-compose.yml` with the new digest
3. Update `umbrel-app.yml` version and releaseNotes
4. Create/update the PR
5. Wait for lint checks to pass

If you've manually built an image, trigger the update workflow manually:

1. Go to **Actions** > **Update Umbrel App**
2. Click **Run workflow**
3. Enter:
   - `version`: e.g., `v2026.1.24`
   - `digest`: e.g., `sha256:abc123...`
   - `image`: `ghcr.io/harmalh/clawdbot-umbrel`

## Verification After PR Update

After updating the PR, verify:

1. [ ] PR lint check passes
2. [ ] Image digest in `docker-compose.yml` matches the built image
3. [ ] Version in `umbrel-app.yml` is correct (no `v` prefix)
4. [ ] Test on local Umbrel to confirm the fix works
