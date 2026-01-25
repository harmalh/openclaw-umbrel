#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Clawdbot Umbrel Entrypoint
# =============================================================================
# This script:
# 1. Ensures data directories exist
# 2. Creates a minimal config if none exists (first-run)
# 3. Starts the Clawdbot Gateway
# =============================================================================

CONFIG_DIR="${CLAWDBOT_STATE_DIR:-/data/.clawdbot}"
WORKSPACE_DIR="${CLAWDBOT_WORKSPACE_DIR:-/data/clawd}"
LOG_DIR="${CLAWDBOT_LOG_DIR:-/data/logs}"
CONFIG_FILE="${CONFIG_DIR}/clawdbot.json"

echo "[entrypoint] Clawdbot Umbrel starting..."
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
  # Only include keys that Clawdbot's config validator accepts
  # Note: Clawdbot substitutes ${ENV_VAR} at config load time
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
echo "[entrypoint] Starting Clawdbot Gateway..."
echo "[entrypoint] Gateway will be available at http://0.0.0.0:18789"
echo "[entrypoint] Control UI: http://<umbrel-ip>:<app-port>/?token=<your-token>"

# -----------------------------------------------------------------------------
# Start Gateway
# -----------------------------------------------------------------------------
# The gateway reads config from CLAWDBOT_STATE_DIR (or ~/.clawdbot)
# We override HOME to ensure consistent paths
export HOME=/home/clawdbot

# Log to file and stdout for debugging
LOG_FILE="${LOG_DIR}/clawdbot.log"

exec node /app/dist/index.js gateway \
  --bind lan \
  --port 18789 \
  2>&1 | tee -a "${LOG_FILE}"
