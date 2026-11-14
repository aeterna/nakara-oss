import type { FastifyServerOptions } from 'fastify';
import type { TicketsDb } from '@nakara-tickets/db';
import type { TicketsConfig } from './config.js';

export type { TicketsDb };

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
