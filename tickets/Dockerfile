# node:22-bookworm-slim, digest pinned 2026-11-20 (multi-arch index)
FROM node:22-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee AS build

WORKDIR /app

# Copy dependency manifests, configuration and sources
COPY package.json package-lock.json* ./
COPY apps/ apps/
COPY packages/ packages/
COPY tsconfig*.json ./

# Install dependencies and build backend and frontend SPA
RUN npm ci
RUN npm run build

# Prune development dependencies for production runtime
RUN npm prune --omit=dev

# node:22-bookworm-slim, digest pinned 2026-11-20 (multi-arch index)
FROM node:22-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee AS runtime

WORKDIR /app

ENV NODE_ENV=production
ENV ROLE=all
ENV PORT=8080
ENV MIGRATIONS_DIR=/app/migrations WEB_DIR=/app/web

# Runtime stage copies only server.mjs, production node_modules, migrations, web dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/apps/server/dist/server.mjs ./server.mjs
COPY --from=build /app/packages/db/migrations ./migrations
COPY --from=build /app/apps/web/dist ./web

RUN mkdir -p /data/files && chown node:node /data/files

USER node

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 8080) + '/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node","server.mjs"]
