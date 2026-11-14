import { describe, it, expect } from 'vitest';
import { writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadConfig } from '../src/config.js';

describe('server config acceptance tests', () => {
  const validBaseEnv = {
    ROLE: 'migrate',
    DATABASE_URL: 'postgres://user:pass@localhost:5432/tickets',
    TICKETS_DATA_KEY: Buffer.alloc(32, 7).toString('base64'),
    ALLOWED_GUILD_IDS: '123456789012345678',
    PUBLIC_ORIGIN: 'https://tickets.example.com',
  };

  it('(e1) minimal valid env (ROLE=migrate, DATABASE_URL, key, ALLOWED_GUILD_IDS, PUBLIC_ORIGIN) loads', () => {
    const config = loadConfig(validBaseEnv);
    expect(config.ROLE).toBe('migrate');
    expect(config.PORT).toBe(8080);
    expect(config.STORAGE_DIR).toBe('/data/files');
    expect(config.DATABASE_URL).toBe('postgres://user:pass@localhost:5432/tickets');
    expect(config.TICKETS_DATA_KEY).toEqual(Buffer.alloc(32, 7));
    expect(config.ALLOWED_GUILD_IDS).toEqual(['123456789012345678']);
    expect(config.PUBLIC_ORIGIN).toBe('https://tickets.example.com');
    expect(Object.isFrozen(config)).toBe(true);
  });

  it('(e2) PORT=abc and PORT=0 throw naming PORT', () => {
    expect(() => loadConfig({ ...validBaseEnv, PORT: 'abc' })).toThrow(/PORT/);
    expect(() => loadConfig({ ...validBaseEnv, PORT: '0' })).toThrow(/PORT/);
  });

  it('(e3) ROLE=all without DISCORD_TOKEN throws naming it', () => {
    const envAll = {
      ...validBaseEnv,
      ROLE: 'all',
      DISCORD_APP_ID: '123456789012345678',
      DISCORD_CLIENT_SECRET: 'some-client-secret',
    };
    expect(() => loadConfig(envAll)).toThrow(/DISCORD_TOKEN/);
  });

  it('(e4) DISCORD_TOKEN_FILE is read', () => {
    const tokenFile = join(tmpdir(), `discord-token-test-${Date.now()}-${Math.random().toString(36).slice(2)}.txt`);
    writeFileSync(tokenFile, 'super-secret-discord-token\n');

    try {
      const env = {
        ...validBaseEnv,
        ROLE: 'all',
        DISCORD_TOKEN_FILE: tokenFile,
        DISCORD_APP_ID: '123456789012345678',
        DISCORD_CLIENT_SECRET: 'some-client-secret',
      };
      const config = loadConfig(env);
      expect(config.DISCORD_TOKEN).toBe('super-secret-discord-token');
    } finally {
      unlinkSync(tokenFile);
    }
  });

  it('(e5) no error message contains the token or key value', () => {
    const secretKeyVal = 'MY_SUPER_SECRET_KEY_NEVER_LEAK_THIS_STRING';
    try {
      loadConfig({
        ...validBaseEnv,
        TICKETS_DATA_KEY: secretKeyVal,
      });
      expect.unreachable('should have thrown');
    } catch (err: any) {
      expect(err.message).not.toContain(secretKeyVal);
    }

    const secretTokenVal = 'MY_SUPER_SECRET_DISCORD_TOKEN_NEVER_LEAK';
    try {
      loadConfig({
        ...validBaseEnv,
        ROLE: 'all',
        DISCORD_TOKEN: secretTokenVal,
      });
      expect.unreachable('should have thrown');
    } catch (err: any) {
      expect(err.message).not.toContain(secretTokenVal);
    }
  });

  it('(e6) PUBLIC_ORIGIN=http://example.com throws, http://localhost:8080 loads', () => {
    expect(() =>
      loadConfig({
        ...validBaseEnv,
        PUBLIC_ORIGIN: 'http://example.com',
      })
    ).toThrow(/PUBLIC_ORIGIN/);

    const configLocal = loadConfig({
      ...validBaseEnv,
      PUBLIC_ORIGIN: 'http://localhost:8080',
    });
    expect(configLocal.PUBLIC_ORIGIN).toBe('http://localhost:8080');
  });
});
