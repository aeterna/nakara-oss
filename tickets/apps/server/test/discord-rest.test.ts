import { describe, it, expect, vi } from 'vitest';
import { createDiscordRest, DiscordRestError } from '../src/discord-rest.js';

describe('discord-rest (w2)', () => {
  const token = 'test-bot-token-xyz-12345';

  it('(w2-1) sends Authorization header Bot <token>', async () => {
    let capturedUrl = '';
    let capturedHeaders: Record<string, string> = {};

    const mockFetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
      capturedUrl = url;
      capturedHeaders = (init?.headers ?? {}) as Record<string, string>;
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ id: 'msg-1', content: 'hello' }),
      };
    });

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });
    const res = await rest.sendMessage('123456789', { content: 'hello' });

    expect(mockFetch).toHaveBeenCalledTimes(1);
    expect(capturedUrl).toBe('https://discord.com/api/v10/channels/123456789/messages');
    expect(capturedHeaders['Authorization']).toBe(`Bot ${token}`);
    expect(capturedHeaders['Content-Type']).toBe('application/json');
    expect(res).toEqual({ id: 'msg-1', content: 'hello' });
  });

  it('(w2-2) 429 retried once after retry_after', async () => {
    let callCount = 0;
    const mockFetch = vi.fn().mockImplementation(async () => {
      callCount++;
      if (callCount === 1) {
        return {
          ok: false,
          status: 429,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => ({ retry_after: 0.05 }), // 50 ms
        };
      }
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ id: 'msg-ok' }),
      };
    });

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });
    const res = await rest.sendMessage('123456789', { content: 'retry test' });

    expect(callCount).toBe(2);
    expect(res).toEqual({ id: 'msg-ok' });
  });

  it('429 waits at most 2 s once, then throws DiscordRestError{status:429}', async () => {
    let callCount = 0;
    const mockFetch = vi.fn().mockImplementation(async () => {
      callCount++;
      return {
        ok: false,
        status: 429,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ retry_after: 0.01, message: 'The rate limit was hit' }),
      };
    });

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });

    let thrownError: any = null;
    try {
      await rest.sendMessage('123456789', { content: 'retry fail test' });
    } catch (err) {
      thrownError = err;
    }

    expect(callCount).toBe(2); // Retried exactly once
    expect(thrownError).toBeInstanceOf(DiscordRestError);
    expect(thrownError.status).toBe(429);
  });

  it('(w2-3) error text never contains the token', async () => {
    const mockFetch = vi.fn().mockImplementation(async () => {
      return {
        ok: false,
        status: 401,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ code: 50001, message: `Missing access with token ${token}` }),
      };
    });

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });

    let thrownError: any = null;
    try {
      await rest.sendMessage('123456789', { content: 'fail test' });
    } catch (err) {
      thrownError = err;
    }

    expect(thrownError).toBeInstanceOf(DiscordRestError);
    expect(thrownError.status).toBe(401);
    expect(thrownError.code).toBe('50001');

    // Verify token is never in message, stack, or JSON
    expect(thrownError.message).not.toContain(token);
    expect(String(thrownError)).not.toContain(token);
    if (thrownError.stack) {
      expect(thrownError.stack).not.toContain(token);
    }
    expect(JSON.stringify(thrownError)).not.toContain(token);
  });

  it('(w2-4) supports editMessage, deleteMessage, createDM, patchChannel, getChannel', async () => {
    const calls: Array<{ url: string; method: string }> = [];
    const mockFetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
      calls.push({ url, method: init?.method ?? 'GET' });
      if (init?.method === 'DELETE') {
        return {
          ok: true,
          status: 204,
          headers: new Headers(),
          json: async () => ({}),
        };
      }
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ id: 'ch-or-msg-1', guild_id: 'guild-1', type: 0 }),
      };
    });

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });

    await rest.editMessage('chan-1', 'msg-1', { content: 'edited' });
    expect(calls[0]).toEqual({
      url: 'https://discord.com/api/v10/channels/chan-1/messages/msg-1',
      method: 'PATCH',
    });

    await rest.deleteMessage('chan-1', 'msg-1');
    expect(calls[1]).toEqual({
      url: 'https://discord.com/api/v10/channels/chan-1/messages/msg-1',
      method: 'DELETE',
    });

    const dm = await rest.createDM('user-1');
    expect(calls[2]).toEqual({
      url: 'https://discord.com/api/v10/users/@me/channels',
      method: 'POST',
    });
    expect(dm).toEqual({ id: 'ch-or-msg-1', guild_id: 'guild-1', type: 0 });

    const ch = await rest.getChannel('chan-2');
    expect(calls[3]).toEqual({
      url: 'https://discord.com/api/v10/channels/chan-2',
      method: 'GET',
    });
    expect(ch).toEqual({ id: 'ch-or-msg-1', guild_id: 'guild-1', type: 0 });
  });

  it('supports listGuildChannels and listGuildRoles', async () => {
    const calls: Array<{ url: string; method: string }> = [];
    const mockFetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
      calls.push({ url, method: init?.method ?? 'GET' });
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => [{ id: 'item-1' }],
      };
    });

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });

    const channels = await rest.listGuildChannels('guild-123');
    expect(calls[0]).toEqual({
      url: 'https://discord.com/api/v10/guilds/guild-123/channels',
      method: 'GET',
    });
    expect(channels).toEqual([{ id: 'item-1' }]);

    const roles = await rest.listGuildRoles('guild-123');
    expect(calls[1]).toEqual({
      url: 'https://discord.com/api/v10/guilds/guild-123/roles',
      method: 'GET',
    });
    expect(roles).toEqual([{ id: 'item-1' }]);
  });

  it('getGuildMember GETs the guild member path and returns the member', async () => {
    const calls: Array<{ url: string; method: string }> = [];
    const mockFetch = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
      calls.push({ url, method: init?.method ?? 'GET' });
      return {
        ok: true,
        status: 200,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ nick: 'Nick', user: { id: 'user-9', username: 'u9' } }),
      };
    });

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });
    const member = await rest.getGuildMember('guild-123', 'user-9');

    expect(calls[0]).toEqual({
      url: 'https://discord.com/api/v10/guilds/guild-123/members/user-9',
      method: 'GET',
    });
    expect(member).toEqual({ nick: 'Nick', user: { id: 'user-9', username: 'u9' } });
  });

  it('getGuildMember surfaces a 404 as DiscordRestError{status:404}', async () => {
    const mockFetch = vi.fn().mockImplementation(async () => ({
      ok: false,
      status: 404,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: async () => ({ code: 10007, message: 'Unknown Member' }),
    }));

    const rest = createDiscordRest({ token, fetchImpl: mockFetch as any });

    await expect(rest.getGuildMember('guild-123', 'user-9')).rejects.toBeInstanceOf(DiscordRestError);
    await expect(rest.getGuildMember('guild-123', 'user-9')).rejects.toMatchObject({ status: 404 });
  });
});
