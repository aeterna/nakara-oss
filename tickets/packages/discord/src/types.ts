import type { TicketsDb } from '@nakara-tickets/db';
import type pg from 'pg';
import type { Client } from 'discord.js';

export interface DiscordPort {
  createPrivateThread(channelId: string, name: string): Promise<{ id: string; name: string }>;
  addMember(threadId: string, userId: string): Promise<void>;
  sendMessage(
    channelId: string,
    payload: { content?: string; embeds?: any[]; components?: any[] }
  ): Promise<{ id: string }>;
  editMessage(
    channelId: string,
    messageId: string,
    payload: { content?: string; embeds?: any[]; components?: any[] }
  ): Promise<void>;
  showModal(
    interaction: any,
    modal: { customId: string; title: string; components: any[] }
  ): Promise<void>;
  replyEphemeral(
    interaction: any,
    message: string | { content: string; embeds?: any[]; components?: any[] }
  ): Promise<void>;
  deferReply(interaction: any, opts?: { ephemeral?: boolean }): Promise<void>;
  editReply(
    interaction: any,
    message: string | { content: string; embeds?: any[]; components?: any[] }
  ): Promise<void>;
  lockAndArchiveThread(threadId: string): Promise<void>;
}

export type GatewayStatus = 'standby' | 'connecting' | 'connected';

export interface StartGatewayDeps {
  token: string;
  appId: string;
  allowedGuildIds: string[];
  db: TicketsDb;
  pool: pg.Pool;
  dataKey: Buffer;
  log: {
    info: (msg: string, ...args: any[]) => void;
    warn: (msg: string, ...args: any[]) => void;
    error: (msg: string, ...args: any[]) => void;
  };
  client?: Client;
  lockOpts?: {
    intervalMs?: number;
    signal?: AbortSignal;
    onStandby?: () => void;
  };
}

export interface GatewayHandle {
  status(): GatewayStatus;
  stop(): Promise<void>;
}
