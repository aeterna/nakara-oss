import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import React from 'react';
import { Panels } from '../src/pages/Panels.js';
import panelsDict from '../src/i18n/panels.js';

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

  it('new panel in th shows Thai defaults, in en English', async () => {
    const { unmount } = render(<Panels guildId={GUILD_ID} locale="th" />);

    await waitFor(() => {
      expect(screen.getByTestId('panel-title-input')).toBeDefined();
    });

    const thTitleInput = screen.getByTestId('panel-title-input') as HTMLInputElement;
    expect(thTitleInput.value).toBe(panelsDict.th.defaultTitle);
    expect(screen.getByTestId('preview-title').textContent).toBe(panelsDict.th.defaultTitle);

    const thDescInput = screen.getByTestId('panel-description-input') as HTMLTextAreaElement;
    expect(thDescInput.value).toBe(panelsDict.th.defaultDescription);
    expect(screen.getByTestId('preview-description').textContent).toBe(panelsDict.th.defaultDescription);

    const thButton = screen.getByTestId('panel-button-item');
    const thButtonInput = (screen.queryByTestId('button-label-input') || thButton.querySelectorAll('input')[0]) as HTMLInputElement;
    expect(thButtonInput.value).toBe(panelsDict.th.defaultButtonLabel);
    expect(screen.getByTestId('preview-components').textContent).toContain(panelsDict.th.defaultButtonLabel);

    unmount();

    render(<Panels guildId={GUILD_ID} locale="en" />);

    await waitFor(() => {
      expect(screen.getByTestId('panel-title-input')).toBeDefined();
    });

    const enTitleInput = screen.getByTestId('panel-title-input') as HTMLInputElement;
    expect(enTitleInput.value).toBe(panelsDict.en.defaultTitle);
    expect(screen.getByTestId('preview-title').textContent).toBe(panelsDict.en.defaultTitle);

    const enDescInput = screen.getByTestId('panel-description-input') as HTMLTextAreaElement;
    expect(enDescInput.value).toBe(panelsDict.en.defaultDescription);
    expect(screen.getByTestId('preview-description').textContent).toBe(panelsDict.en.defaultDescription);

    const enButton = screen.getByTestId('panel-button-item');
    const enButtonInput = (screen.queryByTestId('button-label-input') || enButton.querySelectorAll('input')[0]) as HTMLInputElement;
    expect(enButtonInput.value).toBe(panelsDict.en.defaultButtonLabel);
    expect(screen.getByTestId('preview-components').textContent).toContain(panelsDict.en.defaultButtonLabel);
  });

  it('switching locale on untouched panel updates defaults, but never overwrites text user typed', async () => {
    const { rerender } = render(<Panels guildId={GUILD_ID} locale="en" />);

    await waitFor(() => {
      expect(screen.getByTestId('panel-title-input')).toBeDefined();
    });

    // Untouched panel switches defaults when locale changes to 'th'
    rerender(<Panels guildId={GUILD_ID} locale="th" />);

    const titleInput = screen.getByTestId('panel-title-input') as HTMLInputElement;
    const descInput = screen.getByTestId('panel-description-input') as HTMLTextAreaElement;
    expect(titleInput.value).toBe(panelsDict.th.defaultTitle);
    expect(descInput.value).toBe(panelsDict.th.defaultDescription);

    // User types custom text into title
    fireEvent.change(titleInput, { target: { value: 'My Custom Typed Title' } });
    expect(titleInput.value).toBe('My Custom Typed Title');

    // Switch locale back to 'en': typed title is preserved, untouched description switches
    rerender(<Panels guildId={GUILD_ID} locale="en" />);
    expect(titleInput.value).toBe('My Custom Typed Title');
    expect(descInput.value).toBe(panelsDict.en.defaultDescription);
  });

  it('editing an existing panel keeps its saved text when locale changes', async () => {
    const savedPanel = {
      id: 'panel-saved-1',
      guildId: GUILD_ID,
      channelId: '555666777',
      messageId: 'msg-999',
      embed: {
        title: 'Saved Panel Title',
        description: 'Saved Panel Description',
        color: 0x5865f2,
        footer: 'Saved Footer',
        imageUrl: null,
      },
      kind: 'buttons' as const,
      buttons: [
        { categoryId: 'cat-1', label: 'Saved Button Label', emoji: '🎫', style: 'primary' as const },
      ],
      createdAt: '2026-01-01T00:00:00Z',
    };

    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
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
          json: async () => [savedPanel],
        };
      }
      return { ok: false, status: 404, headers: new Headers(), json: async () => ({}) };
    }));

    const { rerender } = render(<Panels guildId={GUILD_ID} locale="en" />);

    const panelItem = await screen.findByText('Saved Panel Title');
    fireEvent.click(panelItem);

    const titleInput = screen.getByTestId('panel-title-input') as HTMLInputElement;
    const descInput = screen.getByTestId('panel-description-input') as HTMLTextAreaElement;
    expect(titleInput.value).toBe('Saved Panel Title');
    expect(descInput.value).toBe('Saved Panel Description');

    // Change dashboard locale to 'th' while editing saved panel
    rerender(<Panels guildId={GUILD_ID} locale="th" />);

    // Saved panel text must NOT be changed
    expect(titleInput.value).toBe('Saved Panel Title');
    expect(descInput.value).toBe('Saved Panel Description');
  });

  it('saves panel with target channel selected via ChannelSelect', async () => {
    let capturedBody: any = null;
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string, opts?: RequestInit) => {
      const urlStr = String(url);
      if (urlStr.includes('/categories')) {
        return { ok: true, status: 200, headers: new Headers({ 'content-type': 'application/json' }), json: async () => mockCategories };
      }
      if (urlStr.includes('/discord/channels')) {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'content-type': 'application/json' }),
          json: async () => [{ id: 'chan-888', name: 'ticket-drop', type: 0, parentId: null, position: 0 }],
        };
      }
      if (urlStr.includes('/panels')) {
        if (opts?.method === 'POST') {
          capturedBody = JSON.parse(opts.body as string);
          return {
            ok: true,
            status: 201,
            headers: new Headers({ 'content-type': 'application/json' }),
            json: async () => ({ id: 'new-panel', ...capturedBody, createdAt: '2026-01-01' }),
          };
        }
        return { ok: true, status: 200, headers: new Headers({ 'content-type': 'application/json' }), json: async () => [] };
      }
      return { ok: false, status: 404, headers: new Headers({ 'content-type': 'application/json' }), json: async () => ({}) };
    }));

    render(<Panels guildId={GUILD_ID} locale="en" />);
    await screen.findByRole('option', { name: '# ticket-drop' });
    const channelSelect = screen.getByLabelText('Channel');
    fireEvent.change(channelSelect, { target: { value: 'chan-888' } });
    fireEvent.click(screen.getByText('Save Panel'));

    await waitFor(() => {
      expect(capturedBody?.channelId).toBe('chan-888');
    });
  });

  it('asks for a channel with the Choose a channel message when none is picked', async () => {
    render(<Panels guildId={GUILD_ID} locale="en" />);

    await waitFor(() => {
      expect(screen.getByTestId('panel-title-input')).toBeDefined();
    });

    fireEvent.submit(screen.getByText('Save Panel').closest('form') as HTMLFormElement);

    expect(await screen.findByText('Choose a channel')).toBeTruthy();
    expect(screen.queryByText('Channel ID is required')).toBeNull();
  });
});
