import type { FastifyServerOptions } from 'fastify';
import type { TicketsConfig } from './config.js';
import type { DatabaseHandle } from './db.js';

export type TicketsDb = DatabaseHandle['db'];

declare module 'fastify' {
  interface FastifyInstance {
    config: TicketsConfig | null;
    db: TicketsDb | null;
  }
}

export interface BuildAppOptions extends FastifyServerOptions {
  config?: TicketsConfig | null;
  db?: TicketsDb | null;
}

export type { TicketsConfig };
