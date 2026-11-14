# pin: node:22-bookworm-slim@sha256:<fill at release>
FROM node:22-bookworm-slim AS build

WORKDIR /app

# Copy dependency manifests, configuration and sources
COPY package.json package-lock.json* ./
COPY apps/ apps/
COPY packages/ packages/
COPY tsconfig*.json ./

# Install dependencies and build backend and frontend SPA
RUN npm ci
RUN npx tsc -b
RUN npx --workspace @nakara-tickets/web vite build

# Prune development dependencies for production runtime
RUN npm prune --omit=dev

# pin: node:22-bookworm-slim@sha256:<fill at release>
FROM node:22-bookworm-slim AS runtime

WORKDIR /app

ENV NODE_ENV=production
ENV ROLE=all
ENV PORT=8080

# Package manifests needed for ESM module resolution
COPY package.json ./
COPY apps/server/package.json ./apps/server/
COPY apps/web/package.json ./apps/web/
COPY packages/core/package.json ./packages/core/
COPY packages/db/package.json ./packages/db/
COPY packages/discord/package.json ./packages/discord/

# Runtime stage copies only dist, production node_modules, packages/db/migrations, web dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/apps/server/dist ./apps/server/dist
COPY --from=build /app/packages/core/dist ./packages/core/dist
COPY --from=build /app/packages/db/dist ./packages/db/dist
COPY --from=build /app/packages/discord/dist ./packages/discord/dist
COPY --from=build /app/packages/db/migrations ./packages/db/migrations
COPY --from=build /app/apps/web/dist ./apps/web/dist

USER node

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://localhost:' + (process.env.PORT || 8080) + '/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node","apps/server/dist/main.js"]
