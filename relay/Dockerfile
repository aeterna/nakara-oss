# Rongroi Relay — SPDX-License-Identifier: MIT
# No dependencies: only Node's standard library. Runs as the non-root `node` user and keeps no files.
# node:22-bookworm-slim, the digest tickets/Dockerfile pins (2026-11-20)
FROM node:22-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee
WORKDIR /app
COPY package.json relay.js main.js ./
USER node
ENV PORT=8080
EXPOSE 8080
CMD ["node", "main.js"]
