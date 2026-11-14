import type { FastifyServerOptions } from 'fastify';
import type { TicketsDb } from '@nakara-tickets/db';
import type { TicketsConfig } from './config.js';
import type { DiscordRest } from './discord-rest.js';

export type { TicketsDb };
export type { TicketsConfig };
export type { DiscordRest };

export type GatewayStatus = 'standby' | 'connecting' | 'connected';

export interface GatewayHandleLike {
  status(): GatewayStatus;
  stop?(): Promise<void>;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: TicketsConfig | null;
    db: TicketsDb | null;
    gateway: GatewayHandleLike | null;
    discord: DiscordRest | null;
  }
}

export interface BuildAppOptions extends FastifyServerOptions {
  config?: TicketsConfig | null;
  db?: TicketsDb | null;
  gateway?: GatewayHandleLike | null;
  discord?: DiscordRest | null;
}
