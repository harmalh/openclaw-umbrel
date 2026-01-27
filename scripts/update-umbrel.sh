#!/usr/bin/env bash
# ==============================================================================
# update-umbrel.sh - Local Clawdbot Umbrel App Update Script
# ==============================================================================
# This script allows you to update the Umbrel app definition locally without
# waiting for the CI pipeline. It can:
# - Fetch the latest upstream Clawdbot version (or use a specified version)
# - Optionally build and push a new Docker image
# - Update the umbrel-apps fork with the new version
# - Run the Umbrel linter locally
# - Optionally create/update a PR via gh CLI
#
# Usage:
#   ./scripts/update-umbrel.sh [OPTIONS]
#
# Options:
#   -v, --version VERSION    Clawdbot version to use (e.g., v2026.1.24)
#                            Default: fetches latest from GitHub releases
#   -d, --digest DIGEST      Use existing image digest (skip build)
#   -s, --skip-build         Skip Docker build (requires --digest)
#   -l, --skip-lint          Skip umbrel-cli lint
#   -p, --create-pr          Create/update PR to getumbrel/umbrel-apps
#   -n, --dry-run            Show what would be done without making changes
#   -h, --help               Show this help message
#
# Requirements:
#   - git, curl, jq
#   - docker (unless --skip-build)
#   - gh CLI (for --create-pr)
#   - npm/node (for lint, unless --skip-lint)
#
# Environment Variables:
#   UMBREL_APPS_PAT          Personal access token for GitHub (required for --create-pr)
#   GITHUB_TOKEN             Token for GHCR access (defaults to UMBREL_APPS_PAT)
#   IMAGE_NAME               Docker image name (default: ghcr.io/harmalh/clawdbot-umbrel)
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
VERSION=""
DIGEST=""
SKIP_BUILD=false
SKIP_LINT=false
CREATE_PR=false
DRY_RUN=false
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/harmalh/clawdbot-umbrel}"
UMBREL_APPS_REPO="getumbrel/umbrel-apps"
APP_ID="clawdbot"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_help() {
    head -50 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
}

check_requirements() {
    local missing=()
    
    for cmd in git curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ "$SKIP_BUILD" == "false" ]] && ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi
    
    if [[ "$CREATE_PR" == "true" ]] && ! command -v gh &> /dev/null; then
        missing+=("gh")
    fi
    
    if [[ "$SKIP_LINT" == "false" ]]; then
        if ! command -v npm &> /dev/null; then
            missing+=("npm")
        fi
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

get_latest_version() {
    log_info "Fetching latest Clawdbot release..."
    local response
    response=$(curl -s "https://api.github.com/repos/clawdbot/clawdbot/releases/latest")
    
    local version
    version=$(echo "$response" | jq -r '.tag_name // empty')
    
    if [[ -z "$version" ]]; then
        log_error "Could not fetch latest version from GitHub"
        exit 1
    fi
    
    echo "$version"
}

build_image() {
    local version="$1"
    
    log_info "Building multi-arch Docker image for $version..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would build: docker buildx build --platform linux/amd64,linux/arm64 --build-arg CLAWDBOT_VERSION=$version -t $IMAGE_NAME:$version --push ."
        echo "sha256:dryrun0000000000000000000000000000000000000000000000000000000000"
        return
    fi
    
    # Ensure buildx is available
    if ! docker buildx version &> /dev/null; then
        log_error "Docker buildx is required for multi-arch builds"
        log_info "Run: docker buildx create --name multiarch --use"
        exit 1
    fi
    
    cd "$REPO_ROOT"
    
    # Build and push
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg CLAWDBOT_VERSION="$version" \
        -t "$IMAGE_NAME:$version" \
        -t "$IMAGE_NAME:latest" \
        --push .
    
    # Get the manifest digest
    local digest
    digest=$(docker buildx imagetools inspect "$IMAGE_NAME:$version" --format '{{json .Manifest}}' | jq -r '.digest')
    
    if [[ -z "$digest" || ! "$digest" =~ ^sha256: ]]; then
        log_error "Failed to get valid digest from built image"
        exit 1
    fi
    
    echo "$digest"
}

setup_umbrel_apps() {
    local workdir="$1"
    
    log_info "Setting up umbrel-apps repository..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clone/update umbrel-apps in $workdir"
        return
    fi
    
    mkdir -p "$workdir"
    cd "$workdir"
    
    # Clone or update fork
    if [[ -d "umbrel-apps" ]]; then
        cd umbrel-apps
        git fetch origin
        git fetch upstream 2>/dev/null || git remote add upstream "https://github.com/$UMBREL_APPS_REPO.git"
        git fetch upstream
    else
        # Try to clone fork first
        local fork_owner
        fork_owner=$(gh api user --jq '.login' 2>/dev/null || echo "")
        
        if [[ -n "$fork_owner" ]]; then
            gh repo clone "$fork_owner/umbrel-apps" || {
                log_info "Fork not found, cloning upstream..."
                git clone "https://github.com/$UMBREL_APPS_REPO.git" umbrel-apps
            }
        else
            git clone "https://github.com/$UMBREL_APPS_REPO.git" umbrel-apps
        fi
        
        cd umbrel-apps
        git remote add upstream "https://github.com/$UMBREL_APPS_REPO.git" 2>/dev/null || true
        git fetch upstream
    fi
    
    # Sync with upstream
    git checkout master
    git reset --hard upstream/master
}

update_app_files() {
    local umbrel_apps_dir="$1"
    local version="$2"
    local digest="$3"
    
    log_info "Updating app files for version $version..."
    
    local compose_file="$umbrel_apps_dir/$APP_ID/docker-compose.yml"
    local app_file="$umbrel_apps_dir/$APP_ID/umbrel-app.yml"
    
    # Ensure app directory exists
    if [[ ! -d "$umbrel_apps_dir/$APP_ID" ]]; then
        log_info "Copying app template from repository..."
        cp -r "$REPO_ROOT/umbrel-app/$APP_ID" "$umbrel_apps_dir/"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update:"
        log_info "  - $compose_file: image: $IMAGE_NAME:$version@$digest"
        log_info "  - $app_file: version: ${version#v}"
        return
    fi
    
    # Update docker-compose.yml (image only)
    sed -i "s|^\([[:space:]]*image:[[:space:]]*\).*|\1$IMAGE_NAME:$version@$digest|" "$compose_file"
    
    # Update umbrel-app.yml (version and releaseNotes only)
    local clean_version="${version#v}"
    local date
    date=$(date +%Y-%m-%d)
    
    sed -i "s|^version:.*|version: \"$clean_version\"|" "$app_file"
    sed -i "s|^releaseNotes:.*|releaseNotes: \"Updated to Clawdbot $version ($date)\"|" "$app_file"
    
    log_success "Updated app files"
}

run_lint() {
    local umbrel_apps_dir="$1"
    
    log_info "Running umbrel-cli lint..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run: umbrel lint $APP_ID"
        return
    fi
    
    cd "$umbrel_apps_dir"
    
    # Install umbrel-cli if not present
    if ! command -v umbrel &> /dev/null; then
        log_info "Installing umbrel-cli..."
        npm install -g umbrel-cli@^0.6.4
    fi
    
    umbrel lint "$APP_ID"
    log_success "Lint passed"
}

create_pr() {
    local umbrel_apps_dir="$1"
    local version="$2"
    local digest="$3"
    
    log_info "Creating/updating PR..."
    
    local branch="update-clawdbot-$version"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create PR for branch: $branch"
        return
    fi
    
    cd "$umbrel_apps_dir"
    
    # Configure git
    git config user.name "$(git config user.name || echo 'Local User')"
    git config user.email "$(git config user.email || echo 'local@user.com')"
    
    # Create branch
    git checkout -b "$branch" upstream/master 2>/dev/null || git checkout "$branch"
    
    # Add and commit
    git add "$APP_ID/"
    git commit -m "Update Clawdbot to $version" -m "Updated Docker image to $version with digest pinning" || {
        log_warn "No changes to commit"
        return
    }
    
    # Push
    git push origin "$branch" --force-with-lease || git push origin "$branch" -u
    
    # Create PR
    local existing_pr
    existing_pr=$(gh pr list --repo "$UMBREL_APPS_REPO" --head "$(gh api user --jq '.login'):$branch" --json number --jq '.[0].number' 2>/dev/null || echo "")
    
    if [[ -n "$existing_pr" ]]; then
        log_success "PR #$existing_pr already exists"
        gh pr view --repo "$UMBREL_APPS_REPO" "$existing_pr" --web || true
    else
        gh pr create \
            --repo "$UMBREL_APPS_REPO" \
            --base master \
            --title "Update Clawdbot to $version" \
            --body "## Summary

This PR updates the Clawdbot app to version $version.

## Changes

- Updated Docker image to \`$version\` with digest pinning
- Updated app version in umbrel-app.yml
- Image digest: \`$digest\`

---

*Created via local update script*"
        
        log_success "PR created"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -d|--digest)
            DIGEST="$2"
            shift 2
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift
            ;;
        -l|--skip-lint)
            SKIP_LINT=true
            shift
            ;;
        -p|--create-pr)
            CREATE_PR=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "=== Clawdbot Umbrel Update Script ==="
    
    check_requirements
    
    # Get version
    if [[ -z "$VERSION" ]]; then
        VERSION=$(get_latest_version)
    fi
    log_info "Target version: $VERSION"
    
    # Build or use existing digest
    if [[ "$SKIP_BUILD" == "true" ]]; then
        if [[ -z "$DIGEST" ]]; then
            log_error "--skip-build requires --digest"
            exit 1
        fi
        log_info "Using existing digest: $DIGEST"
    else
        DIGEST=$(build_image "$VERSION")
    fi
    log_info "Image digest: $DIGEST"
    
    # Setup umbrel-apps
    local workdir="${TMPDIR:-/tmp}/umbrel-update-$$"
    setup_umbrel_apps "$workdir"
    
    # Update app files
    update_app_files "$workdir/umbrel-apps" "$VERSION" "$DIGEST"
    
    # Run lint
    if [[ "$SKIP_LINT" == "false" ]]; then
        run_lint "$workdir/umbrel-apps"
    fi
    
    # Create PR
    if [[ "$CREATE_PR" == "true" ]]; then
        create_pr "$workdir/umbrel-apps" "$VERSION" "$DIGEST"
    fi
    
    log_success "=== Update complete ==="
    echo ""
    echo "Next steps:"
    if [[ "$CREATE_PR" == "false" ]]; then
        echo "  - Review changes in: $workdir/umbrel-apps/$APP_ID/"
        echo "  - Run with --create-pr to open a PR"
    fi
    echo "  - Test locally by installing on your Umbrel"
}

main
