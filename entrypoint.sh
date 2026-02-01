#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OpenClaw Umbrel Entrypoint
# =============================================================================
# This script:
# 1. Ensures data directories exist
# 2. Creates a minimal config if none exists (first-run)
# 3. Starts the OpenClaw Gateway
#
# Note: Environment variables still use CLAWDBOT_* prefix for backward
# compatibility with existing configs and upstream OpenClaw defaults.
# =============================================================================

CONFIG_DIR="${CLAWDBOT_STATE_DIR:-/data/.clawdbot}"
WORKSPACE_DIR="${CLAWDBOT_WORKSPACE_DIR:-/data/clawd}"
LOG_DIR="${CLAWDBOT_LOG_DIR:-/data/logs}"
CONFIG_FILE="${CONFIG_DIR}/clawdbot.json"

echo "[entrypoint] OpenClaw Umbrel starting..."
echo "[entrypoint] Config dir: ${CONFIG_DIR}"
echo "[entrypoint] Workspace dir: ${WORKSPACE_DIR}"
echo "[entrypoint] Log dir: ${LOG_DIR}"

# -----------------------------------------------------------------------------
# Ensure directories exist
# -----------------------------------------------------------------------------
mkdir -p "${CONFIG_DIR}" "${WORKSPACE_DIR}" "${LOG_DIR}"

# -----------------------------------------------------------------------------
# Seed minimal config on first run
# -----------------------------------------------------------------------------
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "[entrypoint] No config found, creating minimal Umbrel-ready config..."
  
  # Get the token from environment (Umbrel passes APP_PASSWORD)
  TOKEN="${CLAWDBOT_GATEWAY_TOKEN:-}"
  
  if [[ -z "${TOKEN}" ]]; then
    echo "[entrypoint] WARNING: CLAWDBOT_GATEWAY_TOKEN not set!"
    echo "[entrypoint] The Control UI will require a token for access."
    echo "[entrypoint] Set this to your Umbrel app password for easy access."
  fi
  
  # Create minimal valid JSON config for Umbrel
  # Only include keys that OpenClaw's config validator accepts
  # Note: OpenClaw substitutes ${ENV_VAR} at config load time
  # Bundled extensions (memory-core) are now included in the image,
  # so we let OpenClaw use its default plugin configuration
  cat > "${CONFIG_FILE}" << 'CONFIGEOF'
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "token": "${CLAWDBOT_GATEWAY_TOKEN}"
    },
    "controlUi": {
      "allowInsecureAuth": true
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/data/clawd"
    }
  }
}
CONFIGEOF

  echo "[entrypoint] Config created at ${CONFIG_FILE}"
else
  echo "[entrypoint] Existing config found at ${CONFIG_FILE}"
fi

# -----------------------------------------------------------------------------
# Log startup info
# -----------------------------------------------------------------------------
echo "[entrypoint] Starting OpenClaw Gateway..."
echo "[entrypoint] Gateway will be available at http://0.0.0.0:18789"
echo "[entrypoint] Control UI: http://<umbrel-ip>:<app-port>/?token=<your-token>"

# -----------------------------------------------------------------------------
# Start Gateway
# -----------------------------------------------------------------------------
# The gateway reads config from CLAWDBOT_STATE_DIR (or ~/.clawdbot)
# We override HOME to ensure consistent paths
export HOME=/home/node

# Log to file and stdout for debugging
LOG_FILE="${LOG_DIR}/clawdbot.log"

# Run doctor to fix any config issues before starting
echo "[entrypoint] Running doctor to fix config..."
node /app/dist/index.js doctor --fix 2>&1 || true

echo "[entrypoint] Starting gateway..."
exec node /app/dist/index.js gateway \
  --bind lan \
  --port 18789 \
  2>&1 | tee -a "${LOG_FILE}"
