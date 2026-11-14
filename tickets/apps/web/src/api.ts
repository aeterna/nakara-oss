import type { Me, GuildSettings, Category, CategoryInput, ApiErrorPayload } from './types.js';

let csrfToken: string | null = null;

export function setCsrfToken(token: string | null): void {
  csrfToken = token;
}

export function getCsrfToken(): string | null {
  return csrfToken;
}

export class ApiError extends Error {
  code: string;
  status: number;
  details?: Record<string, unknown>;

  constructor(message: string, status: number, code: string = 'unknown_error', details?: Record<string, unknown>) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers || {});
  const method = (options.method || 'GET').toUpperCase();

  if (options.body && typeof options.body === 'string' && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  if (method !== 'GET' && method !== 'HEAD' && csrfToken && !headers.has('X-CSRF-Token')) {
    headers.set('X-CSRF-Token', csrfToken);
  }

  const res = await fetch(path, {
    ...options,
    headers,
  });

  if (res.status === 204) {
    return undefined as unknown as T;
  }

  const contentType = res.headers.get('content-type');
  const isJson = contentType && contentType.includes('application/json');
  const data = isJson ? await res.json() : await res.text();

  if (!res.ok) {
    let message = res.statusText || 'Request failed';
    let code = 'unknown_error';
    let details: Record<string, unknown> | undefined;

    if (data && typeof data === 'object') {
      const payload = data as ApiErrorPayload;
      if (payload.message) message = payload.message;
      if (payload.code) code = payload.code;
      if (payload.details) details = payload.details;
    }

    throw new ApiError(message, res.status, code, details);
  }

  return data as T;
}

export const api = {
  async getMe(): Promise<Me> {
    const data = await request<Me>('/api/v1/me');
    if (data && typeof data.csrfToken === 'string') {
      setCsrfToken(data.csrfToken);
    }
    return data;
  },

  async getSettings(guildId: string): Promise<GuildSettings> {
    return request<GuildSettings>(`/api/v1/guilds/${encodeURIComponent(guildId)}/settings`);
  },

  async putSettings(guildId: string, settings: GuildSettings): Promise<GuildSettings> {
    return request<GuildSettings>(`/api/v1/guilds/${encodeURIComponent(guildId)}/settings`, {
      method: 'PUT',
      body: JSON.stringify(settings),
    });
  },

  async getCategories(guildId: string): Promise<Category[]> {
    return request<Category[]>(`/api/v1/guilds/${encodeURIComponent(guildId)}/categories`);
  },

  async createCategory(guildId: string, input: CategoryInput): Promise<Category> {
    return request<Category>(`/api/v1/guilds/${encodeURIComponent(guildId)}/categories`, {
      method: 'POST',
      body: JSON.stringify(input),
    });
  },

  async updateCategory(guildId: string, categoryId: string, input: CategoryInput): Promise<Category> {
    return request<Category>(`/api/v1/guilds/${encodeURIComponent(guildId)}/categories/${encodeURIComponent(categoryId)}`, {
      method: 'PUT',
      body: JSON.stringify(input),
    });
  },

  async deleteCategory(guildId: string, categoryId: string): Promise<void> {
    await request<void>(`/api/v1/guilds/${encodeURIComponent(guildId)}/categories/${encodeURIComponent(categoryId)}`, {
      method: 'DELETE',
    });
  },

  async logout(): Promise<void> {
    await request<void>('/auth/logout', {
      method: 'POST',
    });
    setCsrfToken(null);
  },
};
