import Fastify from 'fastify';
import routes from './routes/index.js';
import type { BuildAppOptions } from './types.js';
import './types.js';

export function buildApp(opts?: BuildAppOptions) {
  const { config, db, ...fastifyOpts } = opts ?? {};
  const app = Fastify(fastifyOpts);
  app.decorate('config', config ?? null);
  app.decorate('db', db ?? null);
  app.register(routes);
  return app;
}

export type { BuildAppOptions };
