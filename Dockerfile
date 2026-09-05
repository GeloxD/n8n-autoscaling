# Pin the n8n version explicitly - this is the #1 fix for "my setup silently
# broke": the old Dockerfile did `npm install -g n8n` with no version pin, so
# every rebuild grabbed whatever n8n happened to be "latest" that day.
#
# Check https://github.com/n8n-io/n8n/releases for the newest stable tag
# before you deploy, then bump N8N_VERSION here (or via --build-arg) when
# you're ready to upgrade - never let it float on its own again.
ARG N8N_VERSION=2.32.6
FROM docker.n8n.io/n8nio/n8n:${N8N_VERSION}

# The official image is Alpine-based (not Debian like the old node:20 image),
# so package names/paths differ from your previous Dockerfile.
USER root

# System utilities your old image had (ffmpeg, git, graphicsmagick,
# openssh-client) via apk instead of apt. No Chromium/Puppeteer - not used.
RUN apk add --no-cache \
    ffmpeg \
    git \
    graphicsmagick \
    openssh-client

ENV NODE_FUNCTION_ALLOW_EXTERNAL=ajv,ajv-formats,ffmpeg,git,graphicsmagick,openssh-client

# docker-compose.yml explicitly runs these containers as root (user: root:root)
# to match your existing setup and avoid a volume-permission migration on
# your existing n8n_main/n8n_webhook volumes. You can migrate to the
# image's default non-root `node` user later for better isolation - see
# the migration notes in README.md.
USER root
