import Fastify, { type FastifyServerOptions } from 'fastify';
import routes from './routes/index.js';

export function buildApp(opts?: FastifyServerOptions) {
  const app = Fastify(opts);
  app.register(routes);
  return app;
}
