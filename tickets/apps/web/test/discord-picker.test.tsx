import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import React from 'react';
import { ChannelSelect, RoleMultiSelect } from '../src/components/DiscordPicker.js';
import type { DiscordChannel, DiscordRole } from '../src/api/discord.js';

describe('DiscordPicker components', () => {
  const mockChannels: DiscordChannel[] = [
    { id: 'cat-1', name: 'TICKETS', type: 4, parentId: null, position: 0 },
    { id: 'ch-1', name: 'support', type: 0, parentId: 'cat-1', position: 1 },
    { id: 'ch-2', name: 'news', type: 5, parentId: 'cat-1', position: 2 },
    { id: 'ch-3', name: 'random', type: 2, parentId: null, position: 3 },
  ];
  const mockRoles: DiscordRole[] = [
    { id: 'role-1', name: 'Admin', color: 16711680, position: 2 },
    { id: 'role-2', name: 'Staff', color: 65280, position: 1 },
  ];

  it('ChannelSelect filters allowed types and groups channels under category name', () => {
    render(<ChannelSelect channels={mockChannels} allowedTypes={[0, 5]} value="" onChange={vi.fn()} />);
    expect((screen.getByRole('group') as HTMLOptGroupElement).label).toBe('TICKETS');
    expect(screen.getByText('# support')).toBeTruthy();
    expect(screen.getByText('# news')).toBeTruthy();
    expect(screen.queryByText('# random')).toBeNull();
  });

  it('ChannelSelect shows unknown saved ID as option and keeps it selected', () => {
    render(<ChannelSelect channels={mockChannels} allowedTypes={[0, 5]} value="unknown-999" onChange={vi.fn()} />);
    expect((screen.getByRole('combobox') as HTMLSelectElement).value).toBe('unknown-999');
    expect(screen.getByText('unknown-999')).toBeTruthy();
  });

  it('ChannelSelect falls back to text input with error line when lookup fails', () => {
    const onChange = vi.fn();
    render(<ChannelSelect error="Discord API unavailable" value="saved-id-1" onChange={onChange} />);
    const input = screen.getByRole('textbox') as HTMLInputElement;
    expect(input.value).toBe('saved-id-1');
    expect(screen.getByText('Discord API unavailable')).toBeTruthy();
    fireEvent.change(input, { target: { value: 'saved-id-2' } });
    expect(onChange).toHaveBeenCalledWith('saved-id-2');
  });

  it('RoleMultiSelect renders checkboxes with colour dot and unknown saved IDs', () => {
    const onChange = vi.fn();
    render(<RoleMultiSelect roles={mockRoles} value={['role-1', 'unknown-role-9']} onChange={onChange} />);
    expect(screen.getByText('Admin')).toBeTruthy();
    expect(screen.getByText('Staff')).toBeTruthy();
    expect(screen.getByText('unknown-role-9')).toBeTruthy();
    const staffCheckbox = screen.getByLabelText('Staff') as HTMLInputElement;
    expect(staffCheckbox.checked).toBe(false);
    fireEvent.click(staffCheckbox);
    expect(onChange).toHaveBeenCalledWith(['role-1', 'unknown-role-9', 'role-2']);
  });

  it('RoleMultiSelect falls back to text input with error line when lookup fails', () => {
    const onChange = vi.fn();
    render(<RoleMultiSelect error="Failed to load roles" value={['role-1', 'role-2']} onChange={onChange} />);
    const input = screen.getByRole('textbox') as HTMLInputElement;
    expect(input.value).toBe('role-1, role-2');
    expect(screen.getByText('Failed to load roles')).toBeTruthy();
    fireEvent.change(input, { target: { value: 'role-3' } });
    expect(onChange).toHaveBeenCalledWith(['role-3']);
  });
});
