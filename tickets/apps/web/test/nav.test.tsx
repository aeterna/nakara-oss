import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { App } from '../src/App.js';
import { api } from '../src/api.js';

describe('web navigation (x3)', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.spyOn(api, 'getMe').mockResolvedValue({
      user: { id: 'u1', username: 'TestUser', avatar: null },
      guilds: [{ id: 'g1', name: 'Test Guild', canManage: true }],
      csrfToken: 'test-csrf-token',
    });
    vi.spyOn(api, 'getCategories').mockResolvedValue([]);
    vi.spyOn(api, 'getSettings').mockResolvedValue({
      locale: 'en',
      retentionDays: 90,
      logChannelId: null,
      ratingDm: false,
      privacyPolicyUrl: null,
    });
  });

  it('renders all nine nav items and switching shows each page heading', async () => {
    render(<App />);

    // Wait for user and guild to load and nav to appear
    await waitFor(() => {
      expect(screen.getByRole('button', { name: /tickets/i })).toBeTruthy();
    });

    // Check all nine nav items are present
    const navButtons = [
      { name: /^tickets$/i, expectedHeading: /tickets/i },
      { name: /^categories$/i, expectedHeading: /categories/i },
      { name: /^panels$/i, expectedHeading: /panels/i },
      { name: /^tags$/i, expectedHeading: /tags/i },
      { name: /^blocks$/i, expectedHeading: /blocks/i },
      { name: /^analytics$/i, expectedHeading: /analytics/i },
      { name: /game servers/i, expectedHeading: /game servers/i },
      { name: /^settings$/i, expectedHeading: /settings/i },
      { name: /^privacy$/i, expectedHeading: /privacy/i },
    ];

    for (const item of navButtons) {
      const btn = screen.getByRole('button', { name: item.name });
      expect(btn).toBeTruthy();

      fireEvent.click(btn);

      await waitFor(() => {
        const heading = screen.getByRole('heading', { level: 2, name: item.expectedHeading });
        expect(heading).toBeTruthy();
      });
    }
  });
});
