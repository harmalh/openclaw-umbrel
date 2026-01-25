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

# Create non-root user (UID 1000 per Umbrel best practice)
RUN groupadd -g 1000 clawdbot && \
    useradd -u 1000 -g clawdbot -m -s /bin/bash clawdbot

WORKDIR /app

# Copy built application from builder stage
COPY --from=builder --chown=clawdbot:clawdbot /app/dist ./dist
COPY --from=builder --chown=clawdbot:clawdbot /app/node_modules ./node_modules
COPY --from=builder --chown=clawdbot:clawdbot /app/package.json ./package.json

# Copy entrypoint script
COPY --chown=clawdbot:clawdbot entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create data directories (will be overwritten by volume mounts)
RUN mkdir -p /data/.clawdbot /data/clawd /data/logs && \
    chown -R clawdbot:clawdbot /data

# Environment
ENV NODE_ENV=production
ENV HOME=/home/clawdbot
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
USER clawdbot

# Use tini as init system for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
