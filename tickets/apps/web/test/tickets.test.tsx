import { describe, it, expect, vi, beforeEach } from 'vitest';
import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { Tickets } from '../src/pages/Tickets.js';
import { ticketsApi } from '../src/api/tickets.js';

// Mock TicketActions component (written by Lane L5)
vi.mock('../src/components/TicketActions.js', () => ({
  default: () => <div data-testid="ticket-actions-mock" />,
  TicketActions: () => <div data-testid="ticket-actions-mock" />,
}));

describe('Tickets Web Page (acceptance test t6)', () => {
  const guildId = '123456789012345678';

  const mockTickets = [
    {
      id: 'ticket-uuid-1',
      number: 101,
      guildId,
      categoryId: 'cat-uuid-1',
      status: 'open' as const,
      openerId: 'user-1',
      claimerId: null,
      channelId: 'chan-1',
      createdAt: '2026-01-01T10:00:00Z',
      firstResponseAt: null,
      lastActivityAt: null,
      closedAt: null,
      closeReason: null,
      reopenedCount: 0,
    },
    {
      id: 'ticket-uuid-2',
      number: 102,
      guildId,
      categoryId: 'cat-uuid-1',
      status: 'closed' as const,
      openerId: 'user-2',
      claimerId: 'staff-1',
      channelId: 'chan-2',
      createdAt: '2026-01-01T11:00:00Z',
      firstResponseAt: '2026-01-01T11:05:00Z',
      lastActivityAt: '2026-01-01T11:30:00Z',
      closedAt: '2026-01-01T11:30:00Z',
      closeReason: 'Finished',
      reopenedCount: 0,
    },
  ];

  const mockMessages = [
    {
      id: 'msg-1',
      authorId: 'user-1',
      authorName: 'Player One',
      isStaff: false,
      isSystem: false,
      content: 'I need help with my inventory',
      attachments: [],
      editedAt: null,
      createdAt: '2026-01-01T10:00:05Z',
    },
    {
      id: 'msg-2',
      authorId: 'staff-1',
      authorName: 'Staff Member',
      isStaff: true,
      isSystem: false,
      content: 'Hello, looking into this now!',
      attachments: [
        {
          id: 'att-1',
          filename: 'screenshot.png',
          contentType: 'image/png',
          size: 2048,
          sha256: 'abc123',
          stored: true,
        },
      ],
      editedAt: null,
      createdAt: '2026-01-01T10:02:00Z',
    },
  ];

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('t6: list renders rows from a stubbed api, detail shows messages', async () => {
    // 1. Stub the API methods
    vi.spyOn(ticketsApi, 'getTickets').mockResolvedValue({
      items: mockTickets,
      next: null,
    });

    vi.spyOn(ticketsApi, 'getTicket').mockResolvedValue(mockTickets[0]);

    vi.spyOn(ticketsApi, 'getTicketMessages').mockResolvedValue({
      items: mockMessages,
      next: null,
    });

    // 2. Render Tickets component
    render(<Tickets guildId={guildId} locale="en" />);

    // 3. Verify ticket rows are rendered from the stubbed api
    await waitFor(() => {
      expect(screen.getByText(/#101/)).toBeTruthy();
      expect(screen.getByText(/#102/)).toBeTruthy();
    });
    expect(screen.queryByText(/#999/)).toBeNull();

    // 4. Click on ticket #101 to open detail view
    const ticketRow = screen.getByText(/#101/);
    fireEvent.click(ticketRow);

    // 5. Verify detail view shows messages
    await waitFor(() => {
      expect(screen.getByText('I need help with my inventory')).toBeTruthy();
      expect(screen.getByText('Hello, looking into this now!')).toBeTruthy();
      expect(screen.getByText('Player One')).toBeTruthy();
      expect(screen.getByText('Staff Member')).toBeTruthy();
    });

    // 6. Verify attachments and actions are rendered
    expect(screen.getByText('screenshot.png')).toBeTruthy();
  });

  it('shows no tickets empty state for empty ticket list in both en and th', async () => {
    vi.spyOn(ticketsApi, 'getTickets').mockResolvedValue({
      items: [],
      next: null,
    });

    const { rerender } = render(<Tickets guildId={guildId} locale="en" />);

    await waitFor(() => {
      expect(screen.getByText('No tickets yet')).toBeTruthy();
    });
    expect(screen.queryByText('No messages yet')).toBeNull();

    rerender(<Tickets guildId={guildId} locale="th" />);

    await waitFor(() => {
      expect(screen.getByText('ยังไม่มีทิกเก็ต')).toBeTruthy();
    });
    expect(screen.queryByText('ยังไม่มีข้อความ')).toBeNull();
  });
});
