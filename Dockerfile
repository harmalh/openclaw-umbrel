# Clawdbot Umbrel Image
# Multi-arch (linux/arm64, linux/amd64) Docker image for running Clawdbot on Umbrel
# Based on upstream Clawdbot Dockerfile with Umbrel-specific adaptations

# =============================================================================
# Stage 1: Build
# =============================================================================
FROM node:22-bookworm AS builder

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Enable corepack for pnpm
RUN corepack enable

WORKDIR /app

# Clone Clawdbot source (pinned to a specific version for reproducibility)
ARG CLAWDBOT_VERSION=main
RUN git clone --depth 1 --branch ${CLAWDBOT_VERSION} https://github.com/clawdbot/clawdbot.git .

# Copy Umbrel UI patches (applied after build if UMBREL_UI_OVERRIDE=1)
COPY patches/ /tmp/patches/

# Optional: Install additional apt packages for skills that need binaries
ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build the main application
RUN pnpm build

# Build the UI (force pnpm for ARM compatibility)
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

# Apply Umbrel UI overrides (fixes scroll and header issues in embedded context)
# Set UMBREL_UI_OVERRIDE=0 to skip applying the override (for testing or when
# upstream includes the fix)
ARG UMBREL_UI_OVERRIDE=1
RUN if [ "$UMBREL_UI_OVERRIDE" = "1" ] && [ -f /tmp/patches/umbrel-control-ui.css ]; then \
      echo "[Dockerfile] Applying Umbrel UI override..." && \
      cp /tmp/patches/umbrel-control-ui.css /app/dist/control-ui/umbrel-override.css && \
      # Inject stylesheet link into index.html (before </head>)
      sed -i 's|</head>|<link rel="stylesheet" href="./umbrel-override.css"></head>|' /app/dist/control-ui/index.html && \
      echo "[Dockerfile] Umbrel UI override applied successfully"; \
    else \
      echo "[Dockerfile] Skipping Umbrel UI override (UMBREL_UI_OVERRIDE=$UMBREL_UI_OVERRIDE)"; \
    fi

# =============================================================================
# Stage 2: Runtime
# =============================================================================
FROM node:22-bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Use the existing 'node' user (UID 1000) per Umbrel best practice
# The node image already has a 'node' user with UID 1000, so we reuse it

WORKDIR /app

# Copy built application from builder stage
COPY --from=builder --chown=node:node /app/dist ./dist
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/package.json ./package.json

# Copy bundled extensions (required for memory-core plugin validation)
COPY --from=builder --chown=node:node /app/extensions ./extensions

# Copy entrypoint script and convert line endings (in case of Windows CRLF)
COPY --chown=node:node entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Create data directories (will be overwritten by volume mounts)
RUN mkdir -p /data/.clawdbot /data/clawd /data/logs && \
    chown -R node:node /data

# Environment
ENV NODE_ENV=production
ENV HOME=/home/node
ENV CLAWDBOT_STATE_DIR=/data/.clawdbot
ENV CLAWDBOT_LOG_FILE=/data/logs/clawdbot.log

# Expose Gateway port
EXPOSE 18789

# Healthcheck removed for Umbrel deployment:
# - Umbrel's app_proxy handles health monitoring
# - Docker healthchecks can cause lock conflicts with gateway lock files
# - Manual setup uses --no-healthcheck to avoid these issues
# For standalone deployments, healthchecks can be added via docker-compose.yml

# Switch to non-root user
USER node

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
