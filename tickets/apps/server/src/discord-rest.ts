export class DiscordRestError extends Error {
  readonly status: number;
  readonly code?: string;

  constructor(status: number, message: string, code?: string) {
    super(message);
    this.name = 'DiscordRestError';
    this.status = status;
    this.code = code;
  }
}

export interface DiscordRestOptions {
  token: string;
  fetchImpl?: typeof fetch;
}

export interface DiscordRest {
  sendMessage(channelId: string, body: any): Promise<any>;
  editMessage(channelId: string, messageId: string, body: any): Promise<any>;
  deleteMessage(channelId: string, messageId: string): Promise<void>;
  createDM(userId: string): Promise<any>;
  patchChannel(channelId: string, body: any): Promise<any>;
}

export function createDiscordRest(opts: DiscordRestOptions): DiscordRest {
  const token = opts.token;
  const fetchImpl = opts.fetchImpl ?? fetch;
  const baseUrl = 'https://discord.com/api/v10';

  const sanitize = (text: string): string => {
    return text.replaceAll(token, '[REDACTED]');
  };

  const request = async (
    path: string,
    init: { method: string; body?: any; retry?: boolean }
  ): Promise<any> => {
    const url = `${baseUrl}${path}`;
    const headers: Record<string, string> = {
      Authorization: `Bot ${token}`,
    };
    if (init.body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }

    const res = await fetchImpl(url, {
      method: init.method,
      headers,
      body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
      signal: AbortSignal.timeout(10_000),
    });

    if (res.status === 429 && !init.retry) {
      let retryAfterSec = 1;
      try {
        const data = (await res.json()) as { retry_after?: number };
        if (typeof data?.retry_after === 'number') {
          retryAfterSec = data.retry_after;
        }
      } catch {
        const headerSec = res.headers.get('retry-after');
        if (headerSec) {
          retryAfterSec = Number(headerSec) || 1;
        }
      }
      const waitMs = Math.ceil(retryAfterSec * 1000);
      await new Promise((resolve) => setTimeout(resolve, waitMs));
      return request(path, { ...init, retry: true });
    }

    if (!res.ok) {
      let code: string | undefined;
      let msg = `Discord API error (${res.status})`;
      try {
        const errorData = (await res.json()) as { code?: string | number; message?: string };
        if (errorData?.code !== undefined) {
          code = String(errorData.code);
        }
        if (errorData?.message) {
          msg = errorData.message;
        }
      } catch {
        // ignore JSON parse error on non-ok response
      }
      throw new DiscordRestError(res.status, sanitize(msg), code);
    }

    if (res.status === 204) {
      return undefined;
    }

    try {
      return await res.json();
    } catch {
      return undefined;
    }
  };

  return {
    async sendMessage(channelId: string, body: any): Promise<any> {
      return request(`/channels/${channelId}/messages`, {
        method: 'POST',
        body,
      });
    },

    async editMessage(channelId: string, messageId: string, body: any): Promise<any> {
      return request(`/channels/${channelId}/messages/${messageId}`, {
        method: 'PATCH',
        body,
      });
    },

    async deleteMessage(channelId: string, messageId: string): Promise<void> {
      await request(`/channels/${channelId}/messages/${messageId}`, {
        method: 'DELETE',
      });
    },

    async createDM(userId: string): Promise<any> {
      return request('/users/@me/channels', {
        method: 'POST',
        body: { recipient_id: userId },
      });
    },

    async patchChannel(channelId: string, body: any): Promise<any> {
      return request(`/channels/${channelId}`, {
        method: 'PATCH',
        body,
      });
    },
  };
}
