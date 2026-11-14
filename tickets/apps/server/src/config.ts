import { readFileSync } from 'node:fs';
import { z } from 'zod';
import { parseDataKey } from '@nakara-tickets/core';

export interface TicketsConfig {
  readonly ROLE: 'all' | 'migrate';
  readonly PORT: number;
  readonly DATABASE_URL: string;
  readonly TICKETS_DATA_KEY: Buffer;
  readonly DISCORD_TOKEN?: string;
  readonly DISCORD_APP_ID?: string;
  readonly DISCORD_CLIENT_SECRET?: string;
  readonly PUBLIC_ORIGIN: string;
  readonly ALLOWED_GUILD_IDS: readonly string[];
  readonly STORAGE_DIR: string;
}

function resolveEnvValue(env: Record<string, string | undefined>, name: string): string | undefined {
  const direct = env[name];
  if (direct !== undefined && direct !== '') {
    return direct;
  }
  const fileKey = `${name}_FILE`;
  const filePath = env[fileKey];
  if (filePath !== undefined && filePath !== '') {
    try {
      return readFileSync(filePath, 'utf8').trim();
    } catch {
      throw new Error(`Failed to read file for variable ${name} from ${fileKey}`);
    }
  }
  return direct;
}

const snowflakeRegex = /^[0-9]{17,20}$/;

export function loadConfig(env: Record<string, string | undefined> = process.env): TicketsConfig {
  const rawRole = resolveEnvValue(env, 'ROLE');
  const rawPort = resolveEnvValue(env, 'PORT');
  const rawDbUrl = resolveEnvValue(env, 'DATABASE_URL');
  const rawDataKey = resolveEnvValue(env, 'TICKETS_DATA_KEY');
  const rawDiscordToken = resolveEnvValue(env, 'DISCORD_TOKEN');
  const rawDiscordAppId = resolveEnvValue(env, 'DISCORD_APP_ID');
  const rawDiscordClientSecret = resolveEnvValue(env, 'DISCORD_CLIENT_SECRET');
  const rawPublicOrigin = resolveEnvValue(env, 'PUBLIC_ORIGIN');
  const rawAllowedGuildIds = resolveEnvValue(env, 'ALLOWED_GUILD_IDS');
  const rawStorageDir = resolveEnvValue(env, 'STORAGE_DIR');

  const rawConfig = {
    ROLE: rawRole,
    PORT: rawPort,
    DATABASE_URL: rawDbUrl,
    TICKETS_DATA_KEY: rawDataKey,
    DISCORD_TOKEN: rawDiscordToken,
    DISCORD_APP_ID: rawDiscordAppId,
    DISCORD_CLIENT_SECRET: rawDiscordClientSecret,
    PUBLIC_ORIGIN: rawPublicOrigin,
    ALLOWED_GUILD_IDS: rawAllowedGuildIds,
    STORAGE_DIR: rawStorageDir,
  };

  const schema = z.object({
    ROLE: z.enum(['all', 'migrate'], {
      error: 'ROLE must be "all" or "migrate"',
    }),
    PORT: z.string().optional().refine((val) => {
      if (val === undefined || val === '') return true;
      const num = Number(val);
      return Number.isInteger(num) && num >= 1 && num <= 65535 && String(num) === val.trim();
    }, {
      message: 'PORT must be an integer between 1 and 65535',
    }).transform((val) => {
      if (val === undefined || val === '') return 8080;
      return Number(val);
    }),
    DATABASE_URL: z.string({
      error: 'DATABASE_URL is required',
    }).min(1, 'DATABASE_URL is required'),
    TICKETS_DATA_KEY: z.string({
      error: 'TICKETS_DATA_KEY is required',
    }).transform((val, ctx) => {
      try {
        return parseDataKey(val);
      } catch {
        ctx.addIssue({
          code: 'custom',
          message: 'TICKETS_DATA_KEY must be 32 bytes base64/base64url',
        });
        return z.NEVER;
      }
    }),
    DISCORD_TOKEN: z.string().optional(),
    DISCORD_APP_ID: z.string().optional(),
    DISCORD_CLIENT_SECRET: z.string().optional(),
    PUBLIC_ORIGIN: z.string({
      error: 'PUBLIC_ORIGIN is required',
    }).refine((val) => {
      try {
        const url = new URL(val);
        if (url.protocol === 'https:') return true;
        if (url.protocol === 'http:' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1' || url.hostname === '[::1]')) {
          return true;
        }
        return false;
      } catch {
        return false;
      }
    }, {
      message: 'PUBLIC_ORIGIN must be a https URL, or http for localhost',
    }),
    ALLOWED_GUILD_IDS: z.string({
      error: 'ALLOWED_GUILD_IDS is required',
    }).refine((val) => val.trim().length > 0, {
      message: 'ALLOWED_GUILD_IDS is required',
    }).transform((val, ctx) => {
      const items = val.split(',').map((s) => s.trim()).filter(Boolean);
      if (items.length === 0) {
        ctx.addIssue({
          code: 'custom',
          message: 'ALLOWED_GUILD_IDS must contain at least one snowflake',
        });
        return [];
      }
      for (const item of items) {
        if (!snowflakeRegex.test(item)) {
          ctx.addIssue({
            code: 'custom',
            message: 'ALLOWED_GUILD_IDS contains invalid snowflake',
          });
          return [];
        }
      }
      return items;
    }),
    STORAGE_DIR: z.string().optional().transform((val) => {
      if (val === undefined || val === '') return '/data/files';
      return val;
    }),
  }).superRefine((data, ctx) => {
    if (data.ROLE === 'all') {
      if (!data.DISCORD_TOKEN) {
        ctx.addIssue({
          code: 'custom',
          path: ['DISCORD_TOKEN'],
          message: 'DISCORD_TOKEN is required when ROLE is all',
        });
      }
      if (!data.DISCORD_APP_ID) {
        ctx.addIssue({
          code: 'custom',
          path: ['DISCORD_APP_ID'],
          message: 'DISCORD_APP_ID is required when ROLE is all',
        });
      }
      if (!data.DISCORD_CLIENT_SECRET) {
        ctx.addIssue({
          code: 'custom',
          path: ['DISCORD_CLIENT_SECRET'],
          message: 'DISCORD_CLIENT_SECRET is required when ROLE is all',
        });
      }
    }
  });

  const parsed = schema.safeParse(rawConfig);
  if (!parsed.success) {
    const errorDetails = parsed.error.issues.map((issue) => {
      const field = issue.path[0] ? String(issue.path[0]) : 'CONFIG';
      return `${field}: ${issue.message}`;
    });
    throw new Error(`Config validation error: ${errorDetails.join('; ')}`);
  }

  const { data } = parsed;

  const config: TicketsConfig = {
    ROLE: data.ROLE,
    PORT: data.PORT,
    DATABASE_URL: data.DATABASE_URL,
    TICKETS_DATA_KEY: data.TICKETS_DATA_KEY,
    DISCORD_TOKEN: data.DISCORD_TOKEN,
    DISCORD_APP_ID: data.DISCORD_APP_ID,
    DISCORD_CLIENT_SECRET: data.DISCORD_CLIENT_SECRET,
    PUBLIC_ORIGIN: data.PUBLIC_ORIGIN,
    ALLOWED_GUILD_IDS: Object.freeze([...data.ALLOWED_GUILD_IDS]),
    STORAGE_DIR: data.STORAGE_DIR,
  };

  return Object.freeze(config);
}
