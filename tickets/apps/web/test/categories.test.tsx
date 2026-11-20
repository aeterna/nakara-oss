import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import React from 'react';
import { Categories } from '../src/pages/Categories.js';
import { api } from '../src/api.js';
import * as serversApi from '../src/api/servers.js';
import type { Category } from '../src/types.js';
import type { GameServer } from '../src/api/servers.js';

describe('Categories component', () => {
  const guildId = '123456789012345678';
  const mockCategory: Category = {
    id: '11111111-1111-1111-1111-111111111111',
    name: 'General Support',
    emoji: '🎫',
    staffRoleIds: ['role-123', 'role-456'],
    mode: 'thread',
    parentChannelId: '987654321098765432',
    nameTemplate: 'ticket-{number}',
    welcomeMessage: 'Hello!',
    maxOpenPerUser: 2,
    autoCloseHours: 48,
    gameServerId: 'srv-1',
    createdAt: '2026-11-20T00:00:00.000Z',
  };

  const mockServers: GameServer[] = [
    {
      id: 'srv-1',
      name: 'Alpha Server',
      confirmed: true,
      edition: 'fivem',
      resourceVersion: '1.0.0',
      playersOnline: 5,
      lastSeenAt: '2026-11-20T00:00:00.000Z',
      revoked: false,
    },
    {
      id: 'srv-2',
      name: 'Beta Server',
      confirmed: true,
      edition: 'fivem',
      resourceVersion: '1.0.0',
      playersOnline: 12,
      lastSeenAt: '2026-11-20T00:00:00.000Z',
      revoked: false,
    },
  ];

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('renders server name in the table and Edit fills the form then saving sends selected gameServerId', async () => {
    vi.spyOn(api, 'getCategories').mockResolvedValue([mockCategory]);
    vi.spyOn(serversApi, 'getGameServers').mockResolvedValue(mockServers);
    const updateSpy = vi.spyOn(api, 'updateCategory').mockResolvedValue({
      ...mockCategory,
      gameServerId: 'srv-2',
    });

    render(<Categories guildId={guildId} locale="en" />);

    await waitFor(() => {
      expect(screen.getByText('General Support')).toBeTruthy();
    });

    // Server name appears in the table
    expect(screen.getByText('Alpha Server')).toBeTruthy();

    // Click Edit button
    const editBtn = screen.getByText('Edit');
    fireEvent.click(editBtn);

    // Form should be populated from category
    const nameInput = screen.getByLabelText('Category Name') as HTMLInputElement;
    expect(nameInput.value).toBe('General Support');

    const parentInput = screen.getByLabelText('Parent Channel ID') as HTMLInputElement;
    expect(parentInput.value).toBe('987654321098765432');

    const rolesInput = screen.getByLabelText('Staff Role IDs') as HTMLInputElement;
    expect(rolesInput.value).toBe('role-123, role-456');

    const serverSelect = screen.getByLabelText('Game server') as HTMLSelectElement;
    expect(serverSelect.value).toBe('srv-1');

    // Select another server and save
    fireEvent.change(serverSelect, { target: { value: 'srv-2' } });
    expect(serverSelect.value).toBe('srv-2');

    const saveBtn = screen.getByText('Save Category');
    fireEvent.click(saveBtn);

    await waitFor(() => {
      expect(updateSpy).toHaveBeenCalledWith(
        guildId,
        mockCategory.id,
        expect.objectContaining({
          name: 'General Support',
          gameServerId: 'srv-2',
        })
      );
    });
  });

  it('sends null gameServerId when none is selected', async () => {
    vi.spyOn(api, 'getCategories').mockResolvedValue([mockCategory]);
    vi.spyOn(serversApi, 'getGameServers').mockResolvedValue(mockServers);
    const updateSpy = vi.spyOn(api, 'updateCategory').mockResolvedValue({
      ...mockCategory,
      gameServerId: null,
    });

    render(<Categories guildId={guildId} locale="en" />);

    await waitFor(() => {
      expect(screen.getByText('General Support')).toBeTruthy();
    });

    fireEvent.click(screen.getByText('Edit'));

    const serverSelect = screen.getByLabelText('Game server') as HTMLSelectElement;
    expect(serverSelect.value).toBe('srv-1');

    fireEvent.change(serverSelect, { target: { value: '' } });
    fireEvent.click(screen.getByText('Save Category'));

    await waitFor(() => {
      expect(updateSpy).toHaveBeenCalledWith(
        guildId,
        mockCategory.id,
        expect.objectContaining({
          gameServerId: null,
        })
      );
    });
  });
});
