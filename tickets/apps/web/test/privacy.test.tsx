import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Privacy } from '../src/pages/Privacy.js';
import * as privacyApi from '../src/api/privacy.js';
import { api } from '../src/api.js';

describe('Privacy web component (p5)', () => {
  const GUILD_ID = '123456789012345678';

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // Acceptance test p5:
  // p5 web confirm flow calls the API once.
  it('p5: web confirm flow calls the API once', async () => {
    // Mock getMe returning non-staff
    vi.spyOn(api, 'getMe').mockResolvedValue({
      user: { id: 'user-1', username: 'TestUser', avatar: null },
      guilds: [{ id: GUILD_ID, name: 'Test Guild', icon: null, canManage: false }],
      csrfToken: 'test-csrf-token',
    });

    const deleteSpy = vi.spyOn(privacyApi, 'deleteMyData').mockResolvedValue({
      ok: true,
      counts: {
        messages: 5,
        attachments: 2,
        ratings: 1,
        tickets: 3,
      },
      messages: 5,
      attachments: 2,
      ratings: 1,
      tickets: 3,
    });

    render(<Privacy guildId={GUILD_ID} locale="en" />);

    // Initial state: "Delete My Data" button is visible
    const initialDeleteBtn = await screen.findByRole('button', { name: /delete my data/i });
    expect(initialDeleteBtn).toBeDefined();

    // API has NOT been called yet
    expect(deleteSpy).not.toHaveBeenCalled();

    // 1. Click "Delete My Data" -> enters confirm step
    fireEvent.click(initialDeleteBtn);

    // Confirm step prompt and buttons are visible
    const confirmBtn = await screen.findByRole('button', { name: /confirm delete/i });
    const cancelBtn = await screen.findByRole('button', { name: /cancel/i });
    expect(confirmBtn).toBeDefined();
    expect(cancelBtn).toBeDefined();

    // Still, API has NOT been called
    expect(deleteSpy).not.toHaveBeenCalled();

    // 2. Click "Cancel" -> returns to initial step
    fireEvent.click(cancelBtn);
    expect(deleteSpy).not.toHaveBeenCalled();
    expect(screen.queryByRole('button', { name: /confirm delete/i })).toBeNull();
    const deleteBtnAgain = await screen.findByRole('button', { name: /delete my data/i });
    expect(deleteBtnAgain).toBeDefined();

    // 3. Click "Delete My Data" then click "Confirm Delete"
    fireEvent.click(deleteBtnAgain);
    const finalConfirmBtn = await screen.findByRole('button', { name: /confirm delete/i });
    fireEvent.click(finalConfirmBtn);

    // Verify API called exactly once!
    await waitFor(() => {
      expect(deleteSpy).toHaveBeenCalledTimes(1);
    });

    // Counts are shown on screen
    const successMsg = await screen.findByTestId('delete-success');
    expect(successMsg.textContent).toContain('5');
    expect(successMsg.textContent).toContain('2');
    expect(successMsg.textContent).toContain('1');
    expect(successMsg.textContent).toContain('3');
  });

  it('renders staff-only export guild button when canManage is true', async () => {
    vi.spyOn(api, 'getMe').mockResolvedValue({
      user: { id: 'staff-1', username: 'StaffUser', avatar: null },
      guilds: [{ id: GUILD_ID, name: 'Staff Guild', icon: null, canManage: true }],
      csrfToken: 'staff-csrf-token',
    });

    render(<Privacy guildId={GUILD_ID} locale="en" />);

    const exportBtn = await screen.findByRole('button', { name: /download export/i });
    expect(exportBtn).toBeDefined();
  });
});
