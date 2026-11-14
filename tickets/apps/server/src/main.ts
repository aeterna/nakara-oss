import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createDb } from './db.js';

const config = loadConfig();

if (config.ROLE === 'migrate') {
  console.log('migrate: not implemented');
  process.exit(0);
}

const { db, close } = createDb(config.DATABASE_URL);
const app = buildApp({ config, db, logger: true });

let stopping = false;
const shutdown = async () => {
  if (stopping) return;
  stopping = true;
  await app.close();
  await close();
  process.exit(0);
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

await app.listen({ port: config.PORT, host: '0.0.0.0' });
