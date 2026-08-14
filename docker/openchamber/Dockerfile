# OpenChamber web UI for OpenCode agents (self-built; no official image).
# Installs the published npm packages so versions match the host db (opencode 1.18.18).
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  git openssh-client ca-certificates python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

# Match the local instance db schema exactly (see ~/.local/share/opencode/opencode.db).
RUN npm install -g opencode-ai@1.18.18 @openchamber/web@1.18.4

COPY entrypoint.sh /home/openchamber/entrypoint.sh
RUN chmod +x /home/openchamber/entrypoint.sh

# Replace the base image user (UID 1000) with "openchamber" so mounted volumes
# with 1000:1000 ownership work correctly (same as upstream Dockerfile).
RUN userdel node 2>/dev/null || true \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && chown -R openchamber:openchamber /home/openchamber

USER openchamber
ENV HOME=/home/openchamber
ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=/home/openchamber/.npm-global/bin:${PATH}

EXPOSE 3000
ENTRYPOINT ["/home/openchamber/entrypoint.sh"]
