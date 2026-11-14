import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react';
import React from 'react';
import { Categories } from '../src/pages/Categories.js';
import { App } from '../src/App.js';
import { api } from '../src/api.js';
import type { Category } from '../src/types.js';

describe('Web acceptance tests (w1-w3)', () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('(w1) Categories renders rows from a stubbed api and shows error on failure', async () => {
    const mockCategories: Category[] = [
      {
        id: '11111111-1111-1111-1111-111111111111',
        name: 'General Support',
        emoji: '🎫',
        staffRoleIds: ['987654321098765432'],
        mode: 'thread',
        parentChannelId: '123456789012345678',
        nameTemplate: 'ticket-{number}',
        welcomeMessage: 'Welcome to support!',
        maxOpenPerUser: 1,
        createdAt: '2026-11-14T12:00:00Z',
      },
      {
        id: '22222222-2222-2222-2222-222222222222',
        name: 'Billing Inquiries',
        emoji: '💰',
        staffRoleIds: ['987654321098765433'],
        mode: 'channel',
        parentChannelId: '123456789012345679',
        nameTemplate: 'billing-{number}',
        welcomeMessage: 'Billing support here.',
        maxOpenPerUser: 2,
        createdAt: '2026-11-14T12:00:00Z',
      },
    ];

    const getCategoriesSpy = vi.spyOn(api, 'getCategories').mockResolvedValue(mockCategories);

    render(<Categories guildId="123456789012345678" locale="en" />);

    // Initially loading, rows should not be present yet
    expect(screen.getByText(/loading/i)).toBeDefined();
    expect(screen.queryByText('General Support')).toBeNull();

    // After loading, category rows are rendered
    await waitFor(() => {
      expect(screen.getByText('General Support')).toBeDefined();
      expect(screen.getByText('Billing Inquiries')).toBeDefined();
    });

    expect(screen.getByText('🎫')).toBeDefined();
    expect(screen.getByText('💰')).toBeDefined();
    expect(getCategoriesSpy).toHaveBeenCalledWith('123456789012345678');

    // Negative control: render with rejected API call
    cleanup();
    vi.spyOn(api, 'getCategories').mockRejectedValue(new Error('Failed to fetch categories'));
    render(<Categories guildId="123456789012345678" locale="en" />);

    await waitFor(() => {
      expect(screen.getByText('Failed to fetch categories')).toBeDefined();
    });
    expect(screen.queryByText('General Support')).toBeNull();
  });

  it('(w2) create form posts the right body and handles validation/errors', async () => {
    vi.spyOn(api, 'getCategories').mockResolvedValue([]);
    const createCategorySpy = vi.spyOn(api, 'createCategory').mockResolvedValue({
      id: '33333333-3333-3333-3333-333333333333',
      name: 'Technical Issue',
      emoji: '🛠️',
      staffRoleIds: ['111111111111111111', '222222222222222222'],
      mode: 'channel',
      parentChannelId: '555555555555555555',
      nameTemplate: 'tech-{number}',
      welcomeMessage: 'Describe your tech issue',
      maxOpenPerUser: 3,
      createdAt: '2026-11-14T12:00:00Z',
    });

    render(<Categories guildId="123456789012345678" locale="en" />);

    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).toBeNull();
    });

    // Open create form
    const createBtn = screen.getByRole('button', { name: /create category/i });
    fireEvent.click(createBtn);

    // Fill form fields
    const nameInput = screen.getByLabelText(/category name/i);
    const emojiInput = screen.getByLabelText(/emoji/i);
    const modeSelect = screen.getByLabelText(/mode/i);
    const parentChannelInput = screen.getByLabelText(/parent channel id/i);
    const staffRolesInput = screen.getByLabelText(/staff role ids/i);
    const nameTemplateInput = screen.getByLabelText(/name template/i);
    const maxOpenInput = screen.getByLabelText(/max open tickets/i);
    const welcomeInput = screen.getByLabelText(/welcome message/i);

    fireEvent.change(nameInput, { target: { value: 'Technical Issue' } });
    fireEvent.change(emojiInput, { target: { value: '🛠️' } });
    fireEvent.change(modeSelect, { target: { value: 'channel' } });
    fireEvent.change(parentChannelInput, { target: { value: '555555555555555555' } });
    fireEvent.change(staffRolesInput, { target: { value: '111111111111111111, 222222222222222222' } });
    fireEvent.change(nameTemplateInput, { target: { value: 'tech-{number}' } });
    fireEvent.change(maxOpenInput, { target: { value: '3' } });
    fireEvent.change(welcomeInput, { target: { value: 'Describe your tech issue' } });

    // Submit form
    const submitBtn = screen.getByRole('button', { name: /save category|submit/i });
    fireEvent.click(submitBtn);

    await waitFor(() => {
      expect(createCategorySpy).toHaveBeenCalledTimes(1);
    });

    expect(createCategorySpy).toHaveBeenCalledWith('123456789012345678', {
      name: 'Technical Issue',
      emoji: '🛠️',
      mode: 'channel',
      parentChannelId: '555555555555555555',
      staffRoleIds: ['111111111111111111', '222222222222222222'],
      nameTemplate: 'tech-{number}',
      welcomeMessage: 'Describe your tech issue',
      maxOpenPerUser: 3,
    });

    // Negative control: error from api displays message and does not add category
    createCategorySpy.mockRejectedValueOnce(new Error('Category creation failed'));
    fireEvent.click(screen.getByRole('button', { name: /create category/i }));
    fireEvent.change(screen.getByLabelText(/category name/i), { target: { value: 'Bad Category' } });
    fireEvent.change(screen.getByLabelText(/parent channel id/i), { target: { value: '999999999999999999' } });
    fireEvent.change(screen.getByLabelText(/staff role ids/i), { target: { value: '888888888888888888' } });
    fireEvent.click(screen.getByRole('button', { name: /save category|submit/i }));

    await waitFor(() => {
      expect(screen.getByText('Category creation failed')).toBeDefined();
    });
  });

  it('(w3) language switch changes a label', async () => {
    // Stub getMe to not be authenticated so Login page renders
    vi.spyOn(api, 'getMe').mockRejectedValue(new Error('Unauthorized'));

    render(<App />);

    // Default locale is Thai ('th')
    await waitFor(() => {
      // In Thai, login label or header should be visible
      expect(screen.getByText('เข้าสู่ระบบด้วย Discord')).toBeDefined();
      expect(screen.queryByText('Login with Discord')).toBeNull();
    });

    // Language switch button should be present
    const langBtn = screen.getByRole('button', { name: /switch to english|en/i });
    fireEvent.click(langBtn);

    // After switching, the English text should appear and Thai should not be present
    await waitFor(() => {
      expect(screen.getByText('Login with Discord')).toBeDefined();
      expect(screen.queryByText('เข้าสู่ระบบด้วย Discord')).toBeNull();
    });

    // And clicking TH switches back
    const thBtn = screen.getByRole('button', { name: /switch to thai|th/i });
    fireEvent.click(thBtn);

    await waitFor(() => {
      expect(screen.getByText('เข้าสู่ระบบด้วย Discord')).toBeDefined();
      expect(screen.queryByText('Login with Discord')).toBeNull();
    });
  });
});
