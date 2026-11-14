import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { GameServers } from '../src/pages/GameServers.js';

describe('GameServers page acceptance tests (g4)', () => {
  const guildId = '123456789012345678';

  const mockServers = [
    {
      id: 'server-uuid-1',
      name: 'Main Roleplay Server',
      edition: 'gta5',
      resourceVersion: '0.1.0',
      playersOnline: 42,
      lastSeenAt: new Date().toISOString(),
      confirmed: true,
      revoked: false,
    },
    {
      id: 'server-uuid-2',
      name: 'Staging Server',
      edition: 'gta5',
      resourceVersion: '0.1.0',
      playersOnline: 0,
      lastSeenAt: null,
      confirmed: false,
      revoked: false,
    },
  ];

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('(g4) pair code is shown with the console command "nakara_tickets pair <code>"', async () => {
    const generatedCode = 'TESTPAIRCODE42';

    globalThis.fetch = vi.fn().mockImplementation(async (url: string, options: any = {}) => {
      if (url.endsWith(`/api/v1/guilds/${guildId}/game-servers`)) {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => mockServers,
        };
      }

      if (url.endsWith(`/api/v1/guilds/${guildId}/game-servers/pair-codes`)) {
        return {
          ok: true,
          status: 201,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => ({
            code: generatedCode,
            expiresAt: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
          }),
        };
      }

      return {
        ok: false,
        status: 404,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ code: 'not_found' }),
      };
    }) as any;

    render(<GameServers guildId={guildId} locale="en" />);

    // Wait for server list to load
    await waitFor(() => {
      expect(screen.getByText('Main Roleplay Server')).toBeDefined();
    });

    // Click "Create Pair Code" button
    const createBtn = screen.getByRole('button', { name: /create pair code/i });
    fireEvent.click(createBtn);

    // Verify pairing code and exact console command are shown
    await waitFor(() => {
      expect(screen.getByText(new RegExp(`nakara_tickets pair ${generatedCode}`))).toBeDefined();
    });
  });

  it('allows confirming, renaming, and revoking a server', async () => {
    let patchPayload: any = null;
    let deletedServerId: string | null = null;

    globalThis.fetch = vi.fn().mockImplementation(async (url: string, options: any = {}) => {
      if (url.endsWith(`/api/v1/guilds/${guildId}/game-servers`)) {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => mockServers,
        };
      }

      if (options.method === 'PATCH' && url.includes('server-uuid-2')) {
        patchPayload = JSON.parse(options.body);
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => ({ ...mockServers[1], ...patchPayload }),
        };
      }

      if (options.method === 'DELETE' && url.includes('server-uuid-1')) {
        deletedServerId = 'server-uuid-1';
        return {
          ok: true,
          status: 204,
          headers: new Headers(),
          text: async () => '',
        };
      }

      return {
        ok: false,
        status: 404,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ code: 'not_found' }),
      };
    }) as any;

    render(<GameServers guildId={guildId} locale="en" />);

    await waitFor(() => {
      expect(screen.getByText('Staging Server')).toBeDefined();
    });

    // 1. Confirm unconfirmed server
    const confirmBtn = screen.getByRole('button', { name: /confirm/i });
    fireEvent.click(confirmBtn);

    await waitFor(() => {
      expect(patchPayload).toEqual({ confirmed: true });
    });

    // 2. Revoke server
    const revokeButtons = screen.getAllByRole('button', { name: /revoke/i });
    fireEvent.click(revokeButtons[0]);

    // Click confirm in the revoke confirmation
    const confirmRevokeBtn = screen.getByRole('button', { name: /confirm revoke|yes, revoke/i });
    fireEvent.click(confirmRevokeBtn);

    await waitFor(() => {
      expect(deletedServerId).toBe('server-uuid-1');
    });
  });
});
