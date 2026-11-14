import { describe, it, expect, vi, beforeEach } from 'vitest';
import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import { Analytics } from '../src/pages/Analytics.js';
import * as analyticsApi from '../src/api/analytics.js';

describe('Analytics Page (acceptance test s6)', () => {
  const stubStats: analyticsApi.StatsResponse = {
    opened: 42,
    closed: 35,
    open_now: 7,
    median_first_response_s: 120,
    median_close_s: 300,
    rating_avg: 4.8,
    rating_count: 25,
    daily: [
      { date: '2026-11-01', opened: 5, closed: 3 },
      { date: '2026-11-02', opened: 8, closed: 6 },
      { date: '2026-11-03', opened: 4, closed: 5 },
      { date: '2026-11-04', opened: 6, closed: 4 },
      { date: '2026-11-05', opened: 7, closed: 7 },
      { date: '2026-11-06', opened: 9, closed: 5 },
      { date: '2026-11-07', opened: 3, closed: 5 },
    ],
    by_category: [
      { category_id: 'cat-1', name: 'Technical Support', opened: 24 },
      { category_id: 'cat-2', name: 'Billing Issues', opened: 18 },
    ],
    staff: [
      { user_id: 'staff-user-1', claimed: 25, closed: 20, rating_avg: 4.9 },
      { user_id: 'staff-user-2', claimed: 17, closed: 15, rating_avg: 4.5 },
    ],
  };

  const stubAudit: analyticsApi.AuditResponse = {
    items: [
      {
        id: 'audit-entry-1',
        actorId: 'admin-1',
        kind: 'ticket.close',
        target: 'ticket-99',
        detail: { reason: 'Resolved' },
        createdAt: '2026-11-07T12:00:00Z',
      },
    ],
    next: null,
  };

  beforeEach(() => {
    vi.restoreAllMocks();
    vi.spyOn(analyticsApi, 'getStats').mockResolvedValue(stubStats);
    vi.spyOn(analyticsApi, 'getAudit').mockResolvedValue(stubAudit);
  });

  it('s6: tiles show stub numbers and SVG has one point per day', async () => {
    const { container } = render(<Analytics guildId="guild-xyz" locale="en" />);

    // Wait for data to load
    await waitFor(() => {
      expect(screen.getByText('42')).toBeInTheDocument();
    });

    // 1. Verify stat tiles show stub numbers
    // Opened
    expect(screen.getByText('42')).toBeInTheDocument();
    // Closed
    expect(screen.getByText('35')).toBeInTheDocument();
    // Open Now
    expect(screen.getByText('7')).toBeInTheDocument();
    // Rating average & count
    expect(screen.getByText(/4\.8/)).toBeInTheDocument();

    // 2. Verify inline SVG chart
    const svgEl = container.querySelector('svg');
    expect(svgEl).toBeInTheDocument();

    // SVG has one point per day (or points per day for lines)
    // 7 days in daily array -> circles with daily titles or data points
    const circles = container.querySelectorAll('svg circle');
    // For 7 days with opened and closed points: at least 7 points (or 14 points for both series)
    expect(circles.length).toBeGreaterThanOrEqual(7);

    // Verify SVG tooltip titles exist per day
    const titles = container.querySelectorAll('svg circle title');
    expect(titles.length).toBeGreaterThanOrEqual(7);
    const titleTexts = Array.from(titles).map((t) => t.textContent);
    expect(titleTexts.some((txt) => txt?.includes('2026-11-01'))).toBe(true);
    expect(titleTexts.some((txt) => txt?.includes('2026-11-07'))).toBe(true);

    // 3. Verify Categories are displayed
    expect(screen.getByText('Technical Support')).toBeInTheDocument();
    expect(screen.getByText('Billing Issues')).toBeInTheDocument();

    // 4. Verify Staff Table
    expect(screen.getByText('staff-user-1')).toBeInTheDocument();
    expect(screen.getByText('staff-user-2')).toBeInTheDocument();

    // 5. Verify Range Picker (7, 30, 90 days)
    const range7Btn = screen.getByRole('button', { name: /7/i });
    expect(range7Btn).toBeInTheDocument();

    fireEvent.click(range7Btn);

    await waitFor(() => {
      expect(analyticsApi.getStats).toHaveBeenCalledTimes(2);
    });

    // 6. Verify Audit Log Table
    expect(screen.getByText('ticket.close')).toBeInTheDocument();
    expect(screen.getByText('admin-1')).toBeInTheDocument();
  });
});
