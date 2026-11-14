import Fastify, { type FastifyInstance } from 'fastify';
import fastifyStatic from '@fastify/static';
import routes from './routes/index.js';
import type { BuildAppOptions } from './types.js';
import type { TicketsConfig } from './config.js';
import type { TicketsDb } from '@nakara-tickets/db';
import { installSession } from './session.js';
import { installBridgeAuth } from './bridge/auth.js';
import './types.js';

export function buildApp(opts?: BuildAppOptions) {
  const { config, db, gateway, discord, ...fastifyOpts } = opts ?? {};
  const app = Fastify(fastifyOpts);
  app.decorate('config', config ?? null);
  app.decorate('db', db ?? null);
  app.decorate('gateway', gateway ?? null);
  app.decorate('discord', discord ?? null);
  app.register(routes);
  return app;
}

export async function installStatic(app: FastifyInstance, webDir?: string): Promise<void> {
  if (!webDir) return;
  await app.register(fastifyStatic, {
    root: webDir,
    prefix: '/',
  });
}

export async function installAll(
  app: FastifyInstance,
  opts: {
    config: TicketsConfig;
    db?: TicketsDb | null;
    webDir?: string;
  }
): Promise<void> {
  await installSession(app, { config: opts.config, db: opts.db });
  installBridgeAuth(app, { db: opts.db, dataKey: opts.config.TICKETS_DATA_KEY });
  if (opts.webDir) {
    await installStatic(app, opts.webDir);
  }
}

export type { BuildAppOptions };
