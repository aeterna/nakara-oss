import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import React from 'react';
import { Panels } from '../src/pages/Panels.js';

describe('Panels web component (acceptance test n5)', () => {
  const GUILD_ID = '123456789012345678';

  const mockCategories = [
    { id: 'cat-1', name: 'General Support', emoji: '🎫', staffRoleIds: [], mode: 'thread', parentChannelId: '111', createdAt: '2026-01-01' },
    { id: 'cat-2', name: 'Billing Support', emoji: '💳', staffRoleIds: [], mode: 'thread', parentChannelId: '111', createdAt: '2026-01-01' },
  ];

  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string, opts?: RequestInit) => {
      const urlStr = String(url);
      if (urlStr.includes('/categories')) {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => mockCategories,
        };
      }
      if (urlStr.includes('/panels')) {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => [],
        };
      }
      return {
        ok: false,
        status: 404,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: async () => ({ code: 'not_found', message: 'Not found' }),
      };
    }));
  });

  it('n5 web: typing a title updates the preview text; adding 6 buttons shows 2 rows; description <b>x</b> shows as literal text', async () => {
    render(<Panels guildId={GUILD_ID} locale="en" />);

    // Wait for categories to load and editor to be visible
    await waitFor(() => {
      expect(screen.getByTestId('panel-title-input')).toBeDefined();
    });

    // 1. Typing a title updates the preview text
    const titleInput = screen.getByTestId('panel-title-input');
    fireEvent.change(titleInput, { target: { value: 'Live Updated Title' } });

    const previewTitle = screen.getByTestId('preview-title');
    expect(previewTitle.textContent).toBe('Live Updated Title');

    // 2. Adding 6 buttons shows 2 rows
    const addButtonBtn = screen.getByTestId('add-button-btn');

    // Currently 0 or 1 button; let's clear existing buttons or click add until 6 buttons exist
    const currentButtons = screen.queryAllByTestId('panel-button-item');
    const toAdd = 6 - currentButtons.length;
    for (let i = 0; i < toAdd; i++) {
      fireEvent.click(addButtonBtn);
    }

    // Check preview button rows
    const previewRows = screen.getAllByTestId('preview-button-row');
    expect(previewRows.length).toBe(2);

    const firstRowButtons = previewRows[0].querySelectorAll('.preview-button');
    const secondRowButtons = previewRows[1].querySelectorAll('.preview-button');
    expect(firstRowButtons.length).toBe(5);
    expect(secondRowButtons.length).toBe(1);

    // Negative case for rows: if 5 buttons, should show only 1 row
    const removeButtons = screen.getAllByTestId('remove-button-btn');
    fireEvent.click(removeButtons[removeButtons.length - 1]); // Remove 6th button -> 5 remaining
    const rowsAfterRemoval = screen.getAllByTestId('preview-button-row');
    expect(rowsAfterRemoval.length).toBe(1);

    // 3. Description <b>x</b> shows as literal text
    const descInput = screen.getByTestId('panel-description-input');
    fireEvent.change(descInput, { target: { value: 'Important: <b>x</b> not bolded\nSecond line' } });

    const previewDesc = screen.getByTestId('preview-description');
    expect(previewDesc.textContent).toContain('<b>x</b>');
    // Ensure no HTML <b> element is rendered inside the preview description
    expect(previewDesc.querySelector('b')).toBeNull();
    // Negative case: literal text is escaped, not HTML
    expect(previewDesc.innerHTML).toContain('&lt;b&gt;x&lt;/b&gt;');
  });

  it('displays character counter limits correctly', async () => {
    render(<Panels guildId={GUILD_ID} locale="en" />);

    await waitFor(() => {
      expect(screen.getByTestId('panel-title-input')).toBeDefined();
    });

    const titleInput = screen.getByTestId('panel-title-input');
    fireEvent.change(titleInput, { target: { value: 'Test Title' } });

    const titleCounter = screen.getByTestId('title-counter');
    expect(titleCounter.textContent).toContain('10');
    expect(titleCounter.textContent).toContain('256');

    const descInput = screen.getByTestId('panel-description-input');
    fireEvent.change(descInput, { target: { value: 'Test Description' } });

    const descCounter = screen.getByTestId('description-counter');
    expect(descCounter.textContent).toContain('16');
    expect(descCounter.textContent).toContain('4096');
  });
});
