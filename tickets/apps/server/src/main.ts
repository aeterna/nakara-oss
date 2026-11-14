import { fileURLToPath } from 'node:url';
import { startGateway } from '@nakara-tickets/discord';
import { buildApp, installAll } from './app.js';
import { loadConfig } from './config.js';
import { createDb } from './db.js';
import { createDiscordRest } from './discord-rest.js';
import { createStorage } from './storage.js';
import { startWorker } from './worker.js';
import { jobs } from './jobs/index.js';
import { runMigrations } from './migrate.js';

export { runMigrations } from './migrate.js';

const config = loadConfig();

if (config.ROLE === 'migrate') {
  const migrationsFolder =
    process.env.MIGRATIONS_DIR ?? fileURLToPath(new URL('../../../packages/db/migrations', import.meta.url));
  try {
    await runMigrations(config.DATABASE_URL, migrationsFolder);
    process.exit(0);
  } catch (err: any) {
    const rawMsg = err?.message ? String(err.message) : 'Migration error';
    const safeMsg = rawMsg.replaceAll(config.DATABASE_URL, '[REDACTED]');
    console.error(`Migration error: ${safeMsg}`);
    process.exit(1);
  }
}

const { db, pool, close: closeDb } = createDb(config.DATABASE_URL);

const storage = createStorage(config);

const discord = config.DISCORD_TOKEN ? createDiscordRest({ token: config.DISCORD_TOKEN }) : null;

const gateway = await startGateway({
  token: config.DISCORD_TOKEN!,
  appId: config.DISCORD_APP_ID!,
  allowedGuildIds: Array.from(config.ALLOWED_GUILD_IDS),
  db,
  pool,
  dataKey: config.TICKETS_DATA_KEY,
  log: console,
  storage,
} as any);

const app = buildApp({ config, db, gateway, discord, storage, logger: true });

const webDir = process.env.WEB_DIR ?? '/app/web';
await installAll(app, { config, db, webDir });

const worker = startWorker(
  jobs,
  {
    db,
    config,
    discord,
    storage,
    gateway: gateway
      ? {
          closeHooks: (guildId: string, ticketId: string, actorId: string) =>
            (gateway as any).closeHooks?.(guildId, ticketId, actorId),
        }
      : undefined,
    log: console,
  },
  console
);

let stopping = false;
const shutdown = async () => {
  if (stopping) return;
  stopping = true;
  try {
    await worker.stop();
  } catch (err) {
    console.error('Error stopping worker', err);
  }
  try {
    await gateway.stop();
  } catch (err) {
    console.error('Error stopping gateway', err);
  }
  try {
    await app.close();
  } catch (err) {
    console.error('Error closing app', err);
  }
  try {
    await closeDb();
  } catch (err) {
    console.error('Error closing db', err);
  }
  process.exit(0);
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await app.listen({ port: config.PORT, host: '0.0.0.0' });
