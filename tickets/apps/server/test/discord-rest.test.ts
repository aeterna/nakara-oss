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

  it('(w2-4) supports editMessage, deleteMessage, createDM', async () => {
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
        json: async () => ({ id: 'ch-or-msg-1' }),
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
    expect(dm).toEqual({ id: 'ch-or-msg-1' });
  });
});
