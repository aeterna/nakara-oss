import type { FastifyServerOptions } from 'fastify';
import type { TicketsDb } from '@nakara-tickets/db';
import type { TicketsConfig } from './config.js';
import type { DiscordRest } from './discord-rest.js';
import type { Storage } from './storage.js';

export type { TicketsDb };
export type { TicketsConfig };
export type { DiscordRest };
export type { Storage };

export type GatewayStatus = 'standby' | 'connecting' | 'connected';

export interface GatewayHandleLike {
  status(): GatewayStatus;
  stop?(): Promise<void>;
  closeHooks?(guildId: string, ticketId: string, actorId: string): Promise<void>;
}

declare module 'fastify' {
  interface FastifyInstance {
    config: TicketsConfig | null;
    db: TicketsDb | null;
    gateway: GatewayHandleLike | null;
    discord: DiscordRest | null;
    storage: Storage | null;
  }
}

export interface BuildAppOptions extends FastifyServerOptions {
  config?: TicketsConfig | null;
  db?: TicketsDb | null;
  gateway?: GatewayHandleLike | null;
  discord?: DiscordRest | null;
  storage?: Storage | null;
}
