import { buildApp } from './app.js';

const role = process.env.ROLE;
const port = Number(process.env.PORT) || 8080;

if (role === 'migrate') {
  console.log('migrate: not implemented');
  process.exit(0);
}

if (role !== 'all') {
  console.error(`Invalid ROLE: ${role}. Expected "all" or "migrate".`);
  process.exit(1);
}

const app = buildApp({ logger: true });
await app.listen({ port, host: '0.0.0.0' });
