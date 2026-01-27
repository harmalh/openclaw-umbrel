# GitHub Container Registry (GHCR) Token Setup Guide

This guide explains how to set up tokens for accessing GitHub Container Registry (GHCR) in different scenarios.

## Table of Contents

1. [GitHub Actions (Automatic Token)](#github-actions-automatic-token)
2. [Personal Access Token (PAT) for Local/External CI](#personal-access-token-pat-for-localexternal-ci)
3. [Repository Settings Configuration](#repository-settings-configuration)
4. [Troubleshooting](#troubleshooting)

---

## GitHub Actions (Automatic Token)

### How It Works

GitHub Actions automatically provides a `GITHUB_TOKEN` for each workflow run. This token:
- ✅ Is automatically available as `${{ secrets.GITHUB_TOKEN }}`
- ✅ Has permissions scoped to the repository
- ✅ Can push/pull packages if permissions are configured correctly

### Required Workflow Permissions

Your workflow **must** explicitly request `packages: write` permission:

```yaml
permissions:
  contents: write      # For repository_dispatch
  packages: write      # REQUIRED for GHCR push/pull
```

**Current Status**: ✅ Your `build-image.yml` already has this configured (line 45-47).

### Package Visibility Settings

1. Go to your repository: `https://github.com/<your-username>/<repo-name>`
2. Click **Settings** → **Actions** → **General**
3. Scroll to **Workflow permissions**
4. Ensure **"Read and write permissions"** is selected
5. Check **"Allow GitHub Actions to create and approve pull requests"** (if needed)

### Package Access Control

For the package to be accessible:

1. Go to **Packages** tab: `https://github.com/<your-username>?tab=packages`
2. Click on your package: `clawdbot-umbrel`
3. Click **Package settings** → **Manage access**
4. Ensure your repository has **Read** or **Write** access

**Note**: By default, packages inherit repository visibility. If your repo is private, the package is private.

---

## Personal Access Token (PAT) for Local/External CI

If you're building images locally or using external CI/CD (not GitHub Actions), you need a Personal Access Token (PAT).

### Step 1: Create a Personal Access Token

1. Go to GitHub Settings: `https://github.com/settings/tokens`
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Give it a descriptive name: `GHCR Access - Clawdbot Umbrel`
4. Set expiration (recommended: 90 days or custom)
5. Select scopes:
   - ✅ **`write:packages`** - Push packages to GHCR
   - ✅ **`read:packages`** - Pull packages from GHCR
   - ✅ **`delete:packages`** - (Optional) Delete packages
   - ✅ **`repo`** - (If repo is private) Access private repositories
6. Click **"Generate token"**
7. **⚠️ COPY THE TOKEN IMMEDIATELY** - You won't see it again!

### Step 2: Store the Token Securely

#### For GitHub Actions (as Repository Secret)

1. Go to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **"New repository secret"**
3. Name: `GHCR_PAT` (or `GITHUB_TOKEN` if you want to override the default)
4. Value: Paste your token
5. Click **"Add secret"**

#### For Local Docker Builds

**Linux/macOS:**
```bash
# Store in environment variable (current session only)
export GHCR_TOKEN="ghp_your_token_here"

# Or add to ~/.bashrc or ~/.zshrc for persistence
echo 'export GHCR_TOKEN="ghp_your_token_here"' >> ~/.bashrc
```

**Windows PowerShell:**
```powershell
# Current session
$env:GHCR_TOKEN = "ghp_your_token_here"

# Persistent (User-level)
[Environment]::SetEnvironmentVariable("GHCR_TOKEN", "ghp_your_token_here", "User")
```

**Windows CMD:**
```cmd
setx GHCR_TOKEN "ghp_your_token_here"
```

### Step 3: Use the Token

#### Docker Login

```bash
# Using PAT
echo $GHCR_TOKEN | docker login ghcr.io -u <your-username> --password-stdin

# Or directly
docker login ghcr.io -u <your-username> -p $GHCR_TOKEN
```

**PowerShell:**
```powershell
$GHCR_TOKEN | docker login ghcr.io -u <your-username> --password-stdin
```

#### In GitHub Actions (if using PAT instead of GITHUB_TOKEN)

```yaml
- name: Log in to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GHCR_PAT }}  # Use PAT instead of GITHUB_TOKEN
```

---

## Repository Settings Configuration

### Ensure Package Permissions

1. **Repository Settings** → **Actions** → **General**
   - Workflow permissions: **Read and write**
   - Allow GitHub Actions to create/approve PRs: ✅ (if needed)

2. **Repository Settings** → **Actions** → **General** → **Workflow permissions**
   - Check that **"Read and write permissions"** is enabled

### Package Visibility

1. Go to your package: `https://github.com/<your-username>?tab=packages`
2. Click on `clawdbot-umbrel`
3. **Package settings** → **Danger Zone** → **Change visibility**
   - **Public**: Anyone can pull (no auth needed)
   - **Private**: Only authorized users/orgs can pull

**Recommendation**: Keep it **private** for security, or **public** if you want others to use it without authentication.

---

## Troubleshooting

### Error: "unauthorized: authentication required"

**Cause**: Token doesn't have `read:packages` or `write:packages` scope.

**Solution**:
1. Regenerate PAT with correct scopes
2. Update the secret/environment variable
3. Re-run the workflow or rebuild

### Error: "denied: permission_denied: write_package"

**Cause**: Workflow doesn't have `packages: write` permission.

**Solution**: Add to workflow:
```yaml
permissions:
  packages: write
```

### Error: "unauthorized: HTTP Basic: Access denied"

**Cause**: Wrong username or token format.

**Solution**:
- Username should be your GitHub username (not email)
- Token should start with `ghp_` (classic) or `github_pat_` (fine-grained)
- For GHCR, use classic token (`ghp_...`)

### Error: "pull access denied, repository does not exist"

**Cause**: Package name mismatch or package doesn't exist.

**Solution**:
- Verify package name: `ghcr.io/<username>/clawdbot-umbrel`
- Check package exists: `https://github.com/<username>?tab=packages`
- Ensure package visibility allows access

### Workflow Token Not Working

**Checklist**:
1. ✅ Workflow has `permissions: packages: write`
2. ✅ Repository settings → Actions → Workflow permissions is "Read and write"
3. ✅ Package exists and is accessible
4. ✅ Package visibility matches your needs

### Local Build Token Not Working

**Checklist**:
1. ✅ Token has `write:packages` scope
2. ✅ Username is correct (GitHub username, not email)
3. ✅ Token is valid (not expired)
4. ✅ Docker login succeeded: `docker login ghcr.io -u <username> -p <token>`

---

## Best Practices

### 1. Use GITHUB_TOKEN for GitHub Actions

- ✅ Automatically scoped to repository
- ✅ Automatically rotated
- ✅ No manual token management
- ✅ Works with `packages: write` permission

**Only use PAT if**:
- You need cross-repository access
- You're using external CI/CD
- You're building locally

### 2. Token Security

- 🔒 Never commit tokens to git
- 🔒 Use repository secrets for GitHub Actions
- 🔒 Use environment variables for local builds
- 🔒 Rotate tokens regularly (90 days recommended)
- 🔒 Use fine-grained tokens when possible (GitHub feature)

### 3. Package Access

- 🔒 Keep packages private unless public distribution is needed
- 🔒 Use least-privilege access (only grant what's needed)
- 🔒 Review package access regularly

### 4. Token Scopes

**Minimum required scopes**:
- `read:packages` - Pull images
- `write:packages` - Push images
- `repo` - (If repository is private)

**Avoid**:
- ❌ `delete:packages` unless you need it
- ❌ `admin:packages` unless managing multiple packages

---

## Quick Reference

### GitHub Actions (Recommended)

```yaml
permissions:
  packages: write

- name: Log in to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

### Local Build

```bash
# Login
echo $GHCR_TOKEN | docker login ghcr.io -u <username> --password-stdin

# Build and push
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  -t ghcr.io/<username>/clawdbot-umbrel:v1.0.0 \
  --push .
```

### Verify Token Works

```bash
# Test authentication
curl -H "Authorization: Bearer $GHCR_TOKEN" \
  https://ghcr.io/v2/<username>/clawdbot-umbrel/tags/list

# Or with docker
docker pull ghcr.io/<username>/clawdbot-umbrel:latest
```

---

## Additional Resources

- [GitHub Container Registry Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub Actions Permissions](https://docs.github.com/en/actions/security-guides/automatic-token-authentication)
- [Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
