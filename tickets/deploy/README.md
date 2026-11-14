# Nakara Tickets Deployment Guide

Nakara Tickets runs from a single unified container image (`ghcr.io/aeterna/nakara-tickets`). The application supports two deployment modes:
- **Run Mode A (VM + Docker Compose):** Recommended for self-hosted virtual machines or dedicated servers.
- **Run Mode B (Serverless Container):** For platforms like Google Cloud Run, AWS ECS/Fargate, or Fly.io with external managed Postgres.

---

## Discord Application Setup

Before deploying the container, you must configure a Discord Application in the [Discord Developer Portal](https://discord.com/developers/applications):

1. **Create an Application:**
   - Click **New Application**, give it a name (e.g. `Nakara Tickets`), and save.
   - Note the **Application ID** (`DISCORD_APP_ID`).
2. **Configure OAuth2:**
   - Go to **OAuth2** -> **General**.
   - Note the **Client Secret** (`DISCORD_CLIENT_SECRET`).
   - Add Redirect URL: `<PUBLIC_ORIGIN>/auth/callback` (e.g. `https://tickets.example.com/auth/callback`).
3. **Configure Bot Settings:**
   - Go to **Bot**.
   - Reset/Copy Token (`DISCORD_TOKEN`).
   - **Turn OFF "Public Bot"**: Ensure this toggle is disabled. Only the application owner should invite the bot.
   - **Privileged Gateway Intents**: Enable the following intents:
     - `Guilds`
     - `GuildMembers`
     - `GuildMessages`
     - `MessageContent` (Required to capture ticket conversations and generate transcripts)
4. **Bot Permissions (ADR 0003 Decision 5):**
   When generating the bot invite URL under **OAuth2 -> URL Generator** (scopes: `bot`, `applications.commands`), grant **only** the following permissions:
   - View Channels
   - Send Messages
   - Send Messages in Threads
   - Create Private Threads
   - Manage Threads
   - Manage Channels (required only if you configure channel-based categories instead of thread categories)
   - Embed Links
   - Attach Files
   - Read Message History
   - *Security Rule:* **NEVER grant Administrator permission.**
5. **Guild Restriction (`ALLOWED_GUILD_IDS`):**
   - Provide a comma-separated list of your Discord server ID(s).
   - If invited to an unauthorized server, the bot immediately leaves.

---

## Run Mode A: VM + Docker Compose (Step by Step)

### Step 1: Prepare Directory Structure

Place `compose.yaml` and the `deploy/` folder onto your server:

```bash
mkdir -p nakara-tickets/secrets nakara-tickets/deploy
cd nakara-tickets
```

### Step 2: Create Secrets Files

Create secret files inside `./secrets/`. Never commit or paste raw passwords into configuration files:

```bash
# 1. Postgres superuser password
openssl rand -hex 24 > secrets/postgres_password.txt

# 2. Database connection string
# Must match postgres container user, password from above, and db name 'tickets'
echo "postgresql://postgres:$(cat secrets/postgres_password.txt)@postgres:5432/tickets" > secrets/database_url.txt

# 3. Encryption key for transcripts and bridge secrets (32 bytes base64)
openssl rand -base64 32 > secrets/tickets_data_key.txt

# 4. Discord bot token
echo "your_bot_token_here" > secrets/discord_token.txt

# 5. Discord client secret
echo "your_oauth2_client_secret_here" > secrets/discord_client_secret.txt

# Secure secrets directory permissions
chmod 600 secrets/*
chmod 700 secrets
```

### Step 3: Configure Environment Variables

Copy `deploy/env.example` to `.env` and fill in the non-sensitive parameters:

```bash
cp deploy/env.example .env
```

Configure the following fields in `.env`:
- `PUBLIC_ORIGIN`: Your public dashboard URL (e.g. `https://tickets.example.com` or `http://localhost:8080`).
- `DISCORD_APP_ID`: Your Discord Application ID.
- `ALLOWED_GUILD_IDS`: Comma-separated list of authorized guild IDs (e.g. `123456789012345678`).
- `PUBLIC_DOMAIN`: Your public domain if using the Caddy profile (e.g. `tickets.example.com`).

### Step 4: Run Database Migrations and Start the Stack

The `compose.yaml` runs database migrations automatically before starting the web and bot application:

```bash
# Standard start (with internal port 8080 or custom reverse proxy)
docker compose up -d

# OR with automated TLS via Caddy (ports 80 and 443)
docker compose --profile caddy up -d

# OR with Cloudflare Tunnel (zero open inbound ports)
# Put your Cloudflare tunnel token in secrets/cloudflared_token.txt first
docker compose --profile cloudflared up -d
```

### Step 5: Service Breakdown

- `postgres`: PostgreSQL 17 database storing all system records.
- `migrate`: Runs Drizzle migrations once (`ROLE=migrate`) and exits with code 0 (`restart: "no"`).
- `app`: Unified process (`ROLE=all`) running Fastify REST API, web dashboard SPA, Discord gateway bot, and background workers.
- `backup`: Daily automated `pg_dump` service saving gzip archives to a volume and retaining the newest 7 backups.
- `caddy` (optional profile): Automatic HTTPS reverse proxy.
- `cloudflared` (optional profile): Outbound tunnel to Cloudflare Edge.

---

## Run Mode B: Serverless Container

Nakara Tickets can run on serverless container platforms (e.g. Google Cloud Run, AWS ECS/Fargate) under specific constraints:

1. **Always-On Instance (min_instances=1, max_instances=1):**
   - The container **must not scale to zero**. Discord gateway connections and WebSocket heartbeats require a persistent process.
   - The container **must not scale beyond 1 instance**. A single Discord bot token connects to the gateway once per application; multiple instances will receive duplicate gateway events.
   - **Cost Notice:** Serverless deployment is **billed as always-on**. It trades OS maintenance overhead for convenience, but is not cheaper than a small VM.
2. **Session-Mode Postgres:**
   - Nakara Tickets acquires a PostgreSQL advisory lock (`pg_try_advisory_lock`) keyed by the Discord Application ID to ensure single-gateway leadership.
   - You **must connect in session mode** (direct connection to Postgres or session-mode pooler). Transaction-level poolers (like Supabase Transaction Pooler or PgBouncer in transaction mode) drop advisory locks between queries and are not supported.
3. **Storage for Attachments:**
   - When running without local persistent disk, configure S3-compatible object storage for ticket attachment retention and transcripts.
4. **Migration Execution:**
   - Run migrations as a one-shot container execution prior to traffic rollout:
     ```bash
     docker run --rm \
       -e ROLE=migrate \
       -e DATABASE_URL="$DATABASE_URL" \
       -e TICKETS_DATA_KEY="$TICKETS_DATA_KEY" \
       ghcr.io/aeterna/nakara-tickets:latest
     ```

---

## Privacy Policy and GDPR

Discord Developer Terms §5 require all bot operators to provide a publicly accessible privacy policy and data deletion mechanism:
- Customize `deploy/PRIVACY-TEMPLATE.md` with your community's contact information.
- Host the resulting privacy policy publicly and paste its URL into the Discord Developer Portal under **Application -> General Information -> Privacy Policy URL**.
- Users can request deletion of their tickets, messages, and ratings at any time using `/tickets delete-my-data` or via the web dashboard data deletion route.
