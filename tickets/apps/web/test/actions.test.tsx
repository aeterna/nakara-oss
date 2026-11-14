import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { TicketActions } from '../src/components/TicketActions.js';

describe('TicketActions component acceptance tests (g4)', () => {
  const guildId = '123456789012345678';
  const ticketId = '11111111-1111-1111-1111-111111111111';

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('(g4) repeat-confirm dialog appears on 409 and resends with confirmRepeat: true', async () => {
    const fetchCalls: { url: string; options: any }[] = [];

    let postCount = 0;
    globalThis.fetch = vi.fn().mockImplementation(async (url: string, options: any = {}) => {
      fetchCalls.push({ url, options });

      if (url.includes(`/api/v1/guilds/${guildId}/tickets/${ticketId}/actions`)) {
        if (!options.method || options.method === 'GET') {
          return {
            ok: true,
            status: 200,
            headers: new Headers({ 'content-type': 'application/json' }),
            json: async () => [],
          };
        }

        if (options.method === 'POST') {
          postCount++;
          const body = JSON.parse(options.body);

          if (postCount === 1) {
            // First POST returns 409 repeat_confirm
            return {
              ok: false,
              status: 409,
              headers: new Headers({ 'content-type': 'application/json' }),
              json: async () => ({
                code: 'repeat_confirm',
                message: 'A matching give_item exists in the last 10 minutes',
              }),
            };
          }

          // Second POST (with confirmRepeat: true) succeeds
          return {
            ok: true,
            status: 202,
            headers: new Headers({ 'content-type': 'application/json' }),
            json: async () => ({
              id: 'action-queued-1',
              ticketId,
              serverId: 'server-1',
              action: body.action,
              params: body.params,
              status: 'queued',
              requestedBy: 'staff-1',
              createdAt: new Date().toISOString(),
              expiresAt: new Date().toISOString(),
            }),
          };
        }
      }

      return {
        ok: false,
        status: 404,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ code: 'not_found' }),
      };
    }) as any;

    render(<TicketActions guildId={guildId} ticketId={ticketId} locale="en" />);

    // Wait for initial fetch
    await waitFor(() => {
      expect(screen.getByRole('button', { name: /give item/i })).toBeDefined();
    });

    // Enter item name and count
    const itemInput = screen.getByPlaceholderText(/item name/i);
    const countInput = screen.getByPlaceholderText(/count/i);

    fireEvent.change(itemInput, { target: { value: 'bandage' } });
    fireEvent.change(countInput, { target: { value: '3' } });

    // Click Give Item button
    const giveBtn = screen.getByRole('button', { name: /give item/i });
    fireEvent.click(giveBtn);

    // Verify 409 triggers repeat-confirm dialog
    await waitFor(() => {
      expect(screen.getByRole('dialog')).toBeDefined();
      expect(screen.getByText(/duplicate item warning|repeat/i)).toBeDefined();
    });

    // Click the confirm button in the dialog
    const confirmBtn = screen.getByRole('button', { name: /confirm repeat|confirm/i });
    fireEvent.click(confirmBtn);

    // Verify second request was made with confirmRepeat: true
    await waitFor(() => {
      expect(postCount).toBe(2);
    });

    const secondPost = fetchCalls.filter((c) => c.options?.method === 'POST')[1];
    expect(secondPost).toBeDefined();
    const secondBody = JSON.parse(secondPost.options.body);
    expect(secondBody.action).toBe('player.give_item');
    expect(secondBody.params).toEqual({ item: 'bandage', count: 3 });
    expect(secondBody.confirmRepeat).toBe(true);
  });
});
