import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createDb } from './db.js';

const config = loadConfig();

if (config.ROLE === 'migrate') {
  console.log('migrate: not implemented');
  process.exit(0);
}

const { db } = createDb(config.DATABASE_URL);
const app = buildApp({ config, db, logger: true });
await app.listen({ port: config.PORT, host: '0.0.0.0' });
