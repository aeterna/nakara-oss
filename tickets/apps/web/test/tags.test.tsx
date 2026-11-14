import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Tags } from '../src/pages/Tags.js';
import { Blocks } from '../src/pages/Blocks.js';

describe('a5 web tags and blocks acceptance tests', () => {
  const GUILD_ID = '111111111111111111';

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('a5-1: web tag create posts the right body', async () => {
    const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
      const urlStr = String(url);
      const method = (init?.method || 'GET').toUpperCase();

      if (urlStr.includes('/tags') && method === 'GET') {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => [
            { id: 'tag-1', name: 'rule-tag', content: 'Existing rule' },
          ],
        };
      }

      if (urlStr.includes('/tags') && method === 'POST') {
        const payload = JSON.parse(init?.body as string);
        return {
          ok: true,
          status: 201,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => ({
            id: 'tag-new',
            name: payload.name,
            content: payload.content ?? payload.body,
          }),
        };
      }

      return { ok: false, status: 404 };
    });

    vi.stubGlobal('fetch', fetchMock);

    render(<Tags guildId={GUILD_ID} locale="en" />);

    // Wait for initial load
    await waitFor(() => {
      expect(screen.getByText('rule-tag')).toBeDefined();
    });

    // Open create form
    const createBtn = screen.getByRole('button', { name: /create tag/i });
    fireEvent.click(createBtn);

    // Fill form
    const nameInput = screen.getByLabelText(/tag name/i);
    const contentInput = screen.getByLabelText(/tag content/i);

    fireEvent.change(nameInput, { target: { value: 'custom-faq' } });
    fireEvent.change(contentInput, { target: { value: 'Hello {user}, this is {staff}!' } });

    // Submit form
    const saveBtn = screen.getByRole('button', { name: /save tag/i });
    fireEvent.click(saveBtn);

    await waitFor(() => {
      // Find the POST request
      const postCall = fetchMock.mock.calls.find(
        (call: any[]) =>
          String(call[0]).includes(`/api/v1/guilds/${GUILD_ID}/tags`) &&
          call[1]?.method === 'POST'
      );
      expect(postCall).toBeDefined();

      const sentBody = JSON.parse(postCall[1].body);
      expect(sentBody.name).toBe('custom-faq');
      // Must post the right tag body / content
      const content = sentBody.content ?? sentBody.body;
      expect(content).toBe('Hello {user}, this is {staff}!');
    });
  });

  it('a5-2: web block remove calls DELETE', async () => {
    const BLOCKED_USER = '222222222222222222';

    const fetchMock = vi.fn().mockImplementation(async (url: string, init?: RequestInit) => {
      const urlStr = String(url);
      const method = (init?.method || 'GET').toUpperCase();

      if (urlStr.includes('/blocks') && method === 'GET') {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => [
            {
              id: 'block-1',
              userId: BLOCKED_USER,
              reason: 'Trolling staff in tickets',
              createdAt: '2026-11-14T12:00:00.000Z',
            },
          ],
        };
      }

      if (urlStr.includes(`/blocks/${BLOCKED_USER}`) && method === 'DELETE') {
        return {
          ok: true,
          status: 204,
          headers: new Headers(),
          text: async () => '',
        };
      }

      return { ok: false, status: 404 };
    });

    vi.stubGlobal('fetch', fetchMock);

    render(<Blocks guildId={GUILD_ID} locale="en" />);

    // Wait for initial load
    await waitFor(() => {
      expect(screen.getByText(BLOCKED_USER)).toBeDefined();
      expect(screen.getByText(/Trolling staff/)).toBeDefined();
    });

    // Click remove block
    const removeBtn = screen.getByRole('button', { name: /unblock|remove/i });
    fireEvent.click(removeBtn);

    await waitFor(() => {
      const deleteCall = fetchMock.mock.calls.find(
        (call: any[]) =>
          String(call[0]).includes(`/api/v1/guilds/${GUILD_ID}/blocks/${BLOCKED_USER}`) &&
          call[1]?.method === 'DELETE'
      );
      expect(deleteCall).toBeDefined();
    });
  });
});
