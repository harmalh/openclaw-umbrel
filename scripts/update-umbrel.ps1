<#
.SYNOPSIS
    Local Clawdbot Umbrel App Update Script for Windows

.DESCRIPTION
    This script allows you to update the Umbrel app definition locally without
    waiting for the CI pipeline. It can:
    - Fetch the latest upstream Clawdbot version (or use a specified version)
    - Optionally build and push a new Docker image
    - Update the umbrel-apps fork with the new version
    - Run the Umbrel linter locally
    - Optionally create/update a PR via gh CLI

.PARAMETER Version
    Clawdbot version to use (e.g., v2026.1.24). Default: fetches latest from GitHub releases.

.PARAMETER Digest
    Use existing image digest (skip build). Required if -SkipBuild is specified.

.PARAMETER SkipBuild
    Skip Docker build (requires -Digest)

.PARAMETER SkipLint
    Skip umbrel-cli lint

.PARAMETER CreatePR
    Create/update PR to getumbrel/umbrel-apps

.PARAMETER DryRun
    Show what would be done without making changes

.EXAMPLE
    .\update-umbrel.ps1
    Fetches latest version, builds image, updates files, runs lint.

.EXAMPLE
    .\update-umbrel.ps1 -Version v2026.1.24 -CreatePR
    Updates to specific version and creates a PR.

.EXAMPLE
    .\update-umbrel.ps1 -SkipBuild -Digest "sha256:abc123..." -SkipLint
    Uses existing digest, skips build and lint.

.NOTES
    Requirements:
    - git, curl (or Invoke-WebRequest)
    - docker (unless -SkipBuild)
    - gh CLI (for -CreatePR)
    - npm/node (for lint, unless -SkipLint)

    Environment Variables:
    - UMBREL_APPS_PAT: Personal access token for GitHub (required for -CreatePR)
    - GITHUB_TOKEN: Token for GHCR access (defaults to UMBREL_APPS_PAT)
    - IMAGE_NAME: Docker image name (default: ghcr.io/harmalh/clawdbot-umbrel)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version,

    [Parameter()]
    [string]$Digest,

    [Parameter()]
    [switch]$SkipBuild,

    [Parameter()]
    [switch]$SkipLint,

    [Parameter()]
    [switch]$CreatePR,

    [Parameter()]
    [switch]$DryRun
)

# Configuration
$ErrorActionPreference = "Stop"
$ImageName = if ($env:IMAGE_NAME) { $env:IMAGE_NAME } else { "ghcr.io/harmalh/clawdbot-umbrel" }
$UmbrelAppsRepo = "getumbrel/umbrel-apps"
$AppId = "clawdbot"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Helper functions
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Test-Command {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-Requirements {
    $missing = @()
    
    foreach ($cmd in @("git", "curl")) {
        if (-not (Test-Command $cmd)) {
            $missing += $cmd
        }
    }
    
    if (-not $SkipBuild -and -not (Test-Command "docker")) {
        $missing += "docker"
    }
    
    if ($CreatePR -and -not (Test-Command "gh")) {
        $missing += "gh"
    }
    
    if (-not $SkipLint -and -not (Test-Command "npm")) {
        $missing += "npm"
    }
    
    if ($missing.Count -gt 0) {
        Write-Error "Missing required commands: $($missing -join ', ')"
        exit 1
    }
}

function Get-LatestVersion {
    Write-Info "Fetching latest Clawdbot release..."
    
    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/clawdbot/clawdbot/releases/latest" -ErrorAction Stop
        $version = $response.tag_name
        
        if ([string]::IsNullOrEmpty($version)) {
            throw "No tag_name in response"
        }
        
        return $version
    }
    catch {
        Write-Error "Could not fetch latest version from GitHub: $_"
        exit 1
    }
}

function Build-Image {
    param([string]$Version)
    
    Write-Info "Building multi-arch Docker image for $Version..."
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would build: docker buildx build --platform linux/amd64,linux/arm64 --build-arg CLAWDBOT_VERSION=$Version -t ${ImageName}:$Version --push ."
        return "sha256:dryrun0000000000000000000000000000000000000000000000000000000000"
    }
    
    # Check buildx
    $buildxVersion = docker buildx version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker buildx is required for multi-arch builds"
        Write-Info "Run: docker buildx create --name multiarch --use"
        exit 1
    }
    
    Push-Location $RepoRoot
    try {
        # Build and push
        docker buildx build `
            --platform linux/amd64,linux/arm64 `
            --build-arg CLAWDBOT_VERSION=$Version `
            -t "${ImageName}:$Version" `
            -t "${ImageName}:latest" `
            --push .
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Docker build failed"
            exit 1
        }
        
        # Get the manifest digest
        $inspectOutput = docker buildx imagetools inspect "${ImageName}:$Version" --format '{{json .Manifest}}' | ConvertFrom-Json
        $digest = $inspectOutput.digest
        
        if ([string]::IsNullOrEmpty($digest) -or $digest -notmatch "^sha256:") {
            Write-Error "Failed to get valid digest from built image"
            exit 1
        }
        
        return $digest
    }
    finally {
        Pop-Location
    }
}

function Initialize-UmbrelApps {
    param([string]$WorkDir)
    
    Write-Info "Setting up umbrel-apps repository..."
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would clone/update umbrel-apps in $WorkDir"
        return
    }
    
    if (-not (Test-Path $WorkDir)) {
        New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    }
    
    Push-Location $WorkDir
    try {
        if (Test-Path "umbrel-apps") {
            Set-Location "umbrel-apps"
            git fetch origin
            $remotes = git remote
            if ($remotes -notcontains "upstream") {
                git remote add upstream "https://github.com/$UmbrelAppsRepo.git"
            }
            git fetch upstream
        }
        else {
            # Try to get current user's fork
            $forkOwner = ""
            try {
                $forkOwner = gh api user --jq '.login' 2>$null
            }
            catch { }
            
            if ($forkOwner) {
                $cloneResult = gh repo clone "$forkOwner/umbrel-apps" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Info "Fork not found, cloning upstream..."
                    git clone "https://github.com/$UmbrelAppsRepo.git" umbrel-apps
                }
            }
            else {
                git clone "https://github.com/$UmbrelAppsRepo.git" umbrel-apps
            }
            
            Set-Location "umbrel-apps"
            git remote add upstream "https://github.com/$UmbrelAppsRepo.git" 2>$null
            git fetch upstream
        }
        
        # Sync with upstream
        git checkout master
        git reset --hard upstream/master
    }
    finally {
        Pop-Location
    }
}

function Update-AppFiles {
    param(
        [string]$UmbrelAppsDir,
        [string]$Version,
        [string]$Digest
    )
    
    Write-Info "Updating app files for version $Version..."
    
    $appDir = Join-Path $UmbrelAppsDir $AppId
    $composeFile = Join-Path $appDir "docker-compose.yml"
    $appFile = Join-Path $appDir "umbrel-app.yml"
    
    # Ensure app directory exists
    if (-not (Test-Path $appDir)) {
        Write-Info "Copying app template from repository..."
        $sourceAppDir = Join-Path (Join-Path $RepoRoot "umbrel-app") $AppId
        Copy-Item -Path $sourceAppDir -Destination $UmbrelAppsDir -Recurse
    }
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would update:"
        Write-Info "  - ${composeFile}: image: ${ImageName}:${Version}@${Digest}"
        Write-Info "  - ${appFile}: version: $($Version -replace '^v', '')"
        return
    }
    
    # Update docker-compose.yml (image only)
    $composeContent = Get-Content $composeFile -Raw
    $composeContent = $composeContent -replace "(?m)^(\s*image:\s*).*$", "`${1}${ImageName}:${Version}@${Digest}"
    Set-Content -Path $composeFile -Value $composeContent -NoNewline
    
    # Update umbrel-app.yml (version and releaseNotes only)
    $cleanVersion = $Version -replace "^v", ""
    $date = Get-Date -Format "yyyy-MM-dd"
    
    $appContent = Get-Content $appFile -Raw
    $appContent = $appContent -replace "(?m)^version:.*$", "version: `"$cleanVersion`""
    $appContent = $appContent -replace "(?m)^releaseNotes:.*$", "releaseNotes: `"Updated to Clawdbot $Version ($date)`""
    Set-Content -Path $appFile -Value $appContent -NoNewline
    
    Write-Success "Updated app files"
}

function Invoke-Lint {
    param([string]$UmbrelAppsDir)
    
    Write-Info "Running umbrel-cli lint..."
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would run: umbrel lint $AppId"
        return
    }
    
    Push-Location $UmbrelAppsDir
    try {
        # Install umbrel-cli if not present
        $umbrelCmd = Get-Command umbrel -ErrorAction SilentlyContinue
        if (-not $umbrelCmd) {
            Write-Info "Installing umbrel-cli..."
            npm install -g umbrel-cli@^0.6.4
        }
        
        umbrel lint $AppId
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Lint failed"
            exit 1
        }
        
        Write-Success "Lint passed"
    }
    finally {
        Pop-Location
    }
}

function New-PullRequest {
    param(
        [string]$UmbrelAppsDir,
        [string]$Version,
        [string]$Digest
    )
    
    Write-Info "Creating/updating PR..."
    
    $branch = "update-clawdbot-$Version"
    
    if ($DryRun) {
        Write-Info "[DRY RUN] Would create PR for branch: $branch"
        return
    }
    
    Push-Location $UmbrelAppsDir
    try {
        # Configure git
        $userName = git config user.name
        if ([string]::IsNullOrEmpty($userName)) {
            git config user.name "Local User"
        }
        $userEmail = git config user.email
        if ([string]::IsNullOrEmpty($userEmail)) {
            git config user.email "local@user.com"
        }
        
        # Create branch
        git checkout -b $branch upstream/master 2>$null
        if ($LASTEXITCODE -ne 0) {
            git checkout $branch
        }
        
        # Add and commit
        git add "$AppId/"
        $commitResult = git commit -m "Update Clawdbot to $Version" -m "Updated Docker image to $Version with digest pinning" 2>&1
        if ($LASTEXITCODE -ne 0 -and $commitResult -match "nothing to commit") {
            Write-Warn "No changes to commit"
            return
        }
        
        # Push
        git push origin $branch --force-with-lease 2>$null
        if ($LASTEXITCODE -ne 0) {
            git push origin $branch -u
        }
        
        # Create PR
        $ghUser = gh api user --jq '.login' 2>$null
        $existingPr = gh pr list --repo $UmbrelAppsRepo --head "${ghUser}:$branch" --json number --jq '.[0].number' 2>$null
        
        if ($existingPr) {
            Write-Success "PR #$existingPr already exists"
            gh pr view --repo $UmbrelAppsRepo $existingPr --web 2>$null
        }
        else {
            $prBody = @"
## Summary

This PR updates the Clawdbot app to version $Version.

## Changes

- Updated Docker image to ``$Version`` with digest pinning
- Updated app version in umbrel-app.yml
- Image digest: ``$Digest``

---

*Created via local update script*
"@
            
            gh pr create `
                --repo $UmbrelAppsRepo `
                --base master `
                --title "Update Clawdbot to $Version" `
                --body $prBody
            
            Write-Success "PR created"
        }
    }
    finally {
        Pop-Location
    }
}

# Main execution
function Main {
    Write-Info "=== Clawdbot Umbrel Update Script ==="
    
    Test-Requirements
    
    # Get version
    if ([string]::IsNullOrEmpty($Version)) {
        $Version = Get-LatestVersion
    }
    Write-Info "Target version: $Version"
    
    # Build or use existing digest
    if ($SkipBuild) {
        if ([string]::IsNullOrEmpty($Digest)) {
            Write-Error "-SkipBuild requires -Digest"
            exit 1
        }
        Write-Info "Using existing digest: $Digest"
    }
    else {
        $Digest = Build-Image -Version $Version
    }
    Write-Info "Image digest: $Digest"
    
    # Setup umbrel-apps
    $workDir = Join-Path $env:TEMP "umbrel-update-$PID"
    Initialize-UmbrelApps -WorkDir $workDir
    
    # Update app files
    $umbrelAppsPath = Join-Path $workDir "umbrel-apps"
    Update-AppFiles -UmbrelAppsDir $umbrelAppsPath -Version $Version -Digest $Digest
    
    # Run lint
    if (-not $SkipLint) {
        Invoke-Lint -UmbrelAppsDir $umbrelAppsPath
    }
    
    # Create PR
    if ($CreatePR) {
        New-PullRequest -UmbrelAppsDir $umbrelAppsPath -Version $Version -Digest $Digest
    }
    
    Write-Success "=== Update complete ==="
    Write-Host ""
    Write-Host "Next steps:"
    if (-not $CreatePR) {
        Write-Host "  - Review changes in: $umbrelAppsPath\$AppId\"
        Write-Host "  - Run with -CreatePR to open a PR"
    }
    Write-Host "  - Test locally by installing on your Umbrel"
}

Main
