import React, { useState, useEffect, useMemo } from 'react';
import type { Locale } from '../i18n.js';
import analyticsDict from '../i18n/analytics.js';
import {
  getStats,
  getAudit,
  type StatsResponse,
  type AuditResponse,
  type StatsStaff,
} from '../api/analytics.js';

export interface AnalyticsProps {
  guildId: string;
  locale: Locale;
}

type SortField = 'user_id' | 'claimed' | 'closed' | 'rating_avg';
type SortDirection = 'asc' | 'desc';

export const Analytics: React.FC<AnalyticsProps> = ({ guildId, locale }) => {
  const t = (key: string): string => {
    return (analyticsDict as any)[locale]?.[key] ?? (analyticsDict as any).en?.[key] ?? key;
  };

  const [rangeDays, setRangeDays] = useState<7 | 30 | 90>(30);
  const [stats, setStats] = useState<StatsResponse | null>(null);
  const [statsLoading, setStatsLoading] = useState<boolean>(true);
  const [statsError, setStatsError] = useState<string | null>(null);

  // Staff sorting
  const [sortField, setSortField] = useState<SortField>('claimed');
  const [sortDirection, setSortDirection] = useState<SortDirection>('desc');

  // Audit log state
  const [audit, setAudit] = useState<AuditResponse | null>(null);
  const [auditLoading, setAuditLoading] = useState<boolean>(true);
  const [auditError, setAuditError] = useState<string | null>(null);
  const [auditActionFilter, setAuditActionFilter] = useState<string>('');
  const [cursorHistory, setCursorHistory] = useState<(string | null)[]>([null]);
  const [pageIndex, setPageIndex] = useState<number>(0);

  // Load stats
  useEffect(() => {
    let mounted = true;
    const fetchStats = async () => {
      try {
        setStatsLoading(true);
        setStatsError(null);

        const now = new Date();
        const toDate = now.toISOString().slice(0, 10);
        const fromDateObj = new Date(now.getTime() - (rangeDays - 1) * 86400000);
        const fromDate = fromDateObj.toISOString().slice(0, 10);

        const data = await getStats(guildId, fromDate, toDate);
        if (mounted) {
          setStats(data);
        }
      } catch (err: unknown) {
        if (mounted) {
          setStatsError(err instanceof Error ? err.message : t('error'));
        }
      } finally {
        if (mounted) {
          setStatsLoading(false);
        }
      }
    };

    fetchStats();
    return () => {
      mounted = false;
    };
  }, [guildId, rangeDays]);

  // Load audit logs
  useEffect(() => {
    let mounted = true;
    const fetchAudit = async () => {
      try {
        setAuditLoading(true);
        setAuditError(null);

        const currentCursor = cursorHistory[pageIndex] ?? null;
        const data = await getAudit(guildId, {
          cursor: currentCursor,
          limit: 10,
          action: auditActionFilter || undefined,
        });

        if (mounted) {
          setAudit(data);
        }
      } catch (err: unknown) {
        if (mounted) {
          setAuditError(err instanceof Error ? err.message : t('error'));
        }
      } finally {
        if (mounted) {
          setAuditLoading(false);
        }
      }
    };

    fetchAudit();
    return () => {
      mounted = false;
    };
  }, [guildId, auditActionFilter, pageIndex]);

  // Sort staff
  const sortedStaff = useMemo(() => {
    const list = [...(stats?.staff ?? stats?.byStaff ?? [])];
    list.sort((a: StatsStaff, b: StatsStaff) => {
      let valA: any = a[sortField];
      let valB: any = b[sortField];

      if (sortField === 'rating_avg') {
        valA = a.rating_avg ?? a.ratingAverage ?? -1;
        valB = b.rating_avg ?? b.ratingAverage ?? -1;
      } else if (sortField === 'user_id') {
        valA = a.user_id ?? a.userId ?? '';
        valB = b.user_id ?? b.userId ?? '';
      }

      if (valA < valB) return sortDirection === 'asc' ? -1 : 1;
      if (valA > valB) return sortDirection === 'asc' ? 1 : -1;
      return 0;
    });
    return list;
  }, [stats, sortField, sortDirection]);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection((prev) => (prev === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortField(field);
      setSortDirection('desc');
    }
  };

  const handleNextPage = () => {
    if (!audit?.next) return;
    const nextCursor = audit.next;
    setCursorHistory((prev) => {
      const nextHist = [...prev.slice(0, pageIndex + 1), nextCursor];
      return nextHist;
    });
    setPageIndex((prev) => prev + 1);
  };

  const handlePrevPage = () => {
    if (pageIndex > 0) {
      setPageIndex((prev) => prev - 1);
    }
  };

  const handleFilterChange = (action: string) => {
    setAuditActionFilter(action);
    setCursorHistory([null]);
    setPageIndex(0);
  };

  // SVG Chart Dimensions & Computations
  const dailyData = stats?.daily ?? [];
  const svgWidth = 680;
  const svgHeight = 220;
  const padding = { top: 20, right: 30, bottom: 35, left: 45 };
  const chartW = svgWidth - padding.left - padding.right;
  const chartH = svgHeight - padding.top - padding.bottom;

  const maxY = Math.max(
    1,
    ...dailyData.map((d) => Math.max(d.opened, d.closed))
  );

  const getX = (index: number) => {
    if (dailyData.length <= 1) return padding.left + chartW / 2;
    return padding.left + (index / (dailyData.length - 1)) * chartW;
  };

  const getY = (val: number) => {
    return padding.top + (1 - val / maxY) * chartH;
  };

  const openedPoints = dailyData.map((d, i) => ({ x: getX(i), y: getY(d.opened), date: d.date, val: d.opened }));
  const closedPoints = dailyData.map((d, i) => ({ x: getX(i), y: getY(d.closed), date: d.date, val: d.closed }));

  const openedPolyline = openedPoints.map((p) => `${p.x},${p.y}`).join(' ');
  const closedPolyline = closedPoints.map((p) => `${p.x},${p.y}`).join(' ');

  // Category max opened for proportional bar widths
  const categoriesList = stats?.by_category ?? stats?.byCategory ?? [];
  const maxCatOpened = Math.max(1, ...categoriesList.map((c) => c.opened));

  return (
    <div className="analytics-container" style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem', width: '100%', maxWidth: '1000px', margin: '0 auto', padding: '1rem' }}>
      {/* Header and Range Picker */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem' }}>
        <h2 style={{ fontSize: '1.5rem', fontWeight: 700 }}>{t('analyticsTitle')}</h2>
        <div style={{ display: 'flex', gap: '0.5rem' }}>
          {([7, 30, 90] as const).map((r) => (
            <button
              key={r}
              type="button"
              className="btn"
              style={{
                padding: '0.4rem 0.8rem',
                borderRadius: '6px',
                border: '1px solid var(--border-color)',
                background: rangeDays === r ? 'var(--primary-btn)' : 'var(--bg-secondary)',
                color: 'var(--text-primary)',
                cursor: 'pointer',
                fontWeight: rangeDays === r ? 600 : 400,
              }}
              onClick={() => setRangeDays(r)}
            >
              {r === 7 ? t('range7') : r === 30 ? t('range30') : t('range90')}
            </button>
          ))}
        </div>
      </div>

      {statsLoading && !stats && (
        <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-secondary)' }}>
          {t('loading')}
        </div>
      )}

      {statsError && (
        <div style={{ padding: '1rem', backgroundColor: '#ef444422', border: '1px solid #ef4444', borderRadius: '8px', color: '#f87171' }}>
          {statsError}
        </div>
      )}

      {/* Stat Tiles */}
      {stats && (
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))',
            gap: '1rem',
          }}
        >
          <div className="card" style={{ padding: '1rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
            <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{t('opened')}</div>
            <div style={{ fontSize: '1.8rem', fontWeight: 700, marginTop: '0.25rem', color: '#3b82f6' }}>
              {stats.opened}
            </div>
          </div>

          <div className="card" style={{ padding: '1rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
            <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{t('closed')}</div>
            <div style={{ fontSize: '1.8rem', fontWeight: 700, marginTop: '0.25rem', color: '#10b981' }}>
              {stats.closed}
            </div>
          </div>

          <div className="card" style={{ padding: '1rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
            <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{t('openNow')}</div>
            <div style={{ fontSize: '1.8rem', fontWeight: 700, marginTop: '0.25rem', color: '#f59e0b' }}>
              {stats.open_now ?? stats.openNow ?? 0}
            </div>
          </div>

          <div className="card" style={{ padding: '1rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
            <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{t('medianFirstResponse')}</div>
            <div style={{ fontSize: '1.8rem', fontWeight: 700, marginTop: '0.25rem' }}>
              {stats.median_first_response_s != null
                ? `${stats.median_first_response_s}s`
                : (stats.medianFirstResponseSeconds != null ? `${stats.medianFirstResponseSeconds}s` : '-')}
            </div>
          </div>

          <div className="card" style={{ padding: '1rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
            <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{t('medianClose')}</div>
            <div style={{ fontSize: '1.8rem', fontWeight: 700, marginTop: '0.25rem' }}>
              {stats.median_close_s != null
                ? `${stats.median_close_s}s`
                : (stats.medianResolutionSeconds != null ? `${stats.medianResolutionSeconds}s` : '-')}
            </div>
          </div>

          <div className="card" style={{ padding: '1rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
            <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{t('ratingAvg')}</div>
            <div style={{ fontSize: '1.8rem', fontWeight: 700, marginTop: '0.25rem', color: '#eab308' }}>
              {stats.rating_avg != null
                ? `${stats.rating_avg} ⭐`
                : (stats.ratingAverage != null ? `${stats.ratingAverage} ⭐` : '-')}
              <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)', marginLeft: '0.5rem', fontWeight: 400 }}>
                ({stats.rating_count ?? stats.ratingCount ?? 0})
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Daily Opened/Closed Chart (inline SVG) */}
      <div className="card" style={{ padding: '1.25rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600 }}>{t('dailyChart')}</h3>
          <div style={{ display: 'flex', gap: '1rem', fontSize: '0.85rem' }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
              <span style={{ width: '10px', height: '10px', background: '#3b82f6', borderRadius: '50%', display: 'inline-block' }} />
              {t('chartOpened')}
            </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
              <span style={{ width: '10px', height: '10px', background: '#10b981', borderRadius: '50%', display: 'inline-block' }} />
              {t('chartClosed')}
            </span>
          </div>
        </div>

        {dailyData.length > 0 ? (
          <div style={{ width: '100%', overflowX: 'auto' }}>
            <svg
              viewBox={`0 0 ${svgWidth} ${svgHeight}`}
              style={{ width: '100%', minWidth: '500px', height: 'auto', display: 'block' }}
              role="img"
              aria-label="Daily tickets chart"
            >
              {/* Y Axis Grid lines & labels */}
              {[0, 0.5, 1].map((ratio) => {
                const yVal = Math.round(maxY * ratio);
                const yPos = getY(yVal);
                return (
                  <g key={ratio}>
                    <line
                      x1={padding.left}
                      y1={yPos}
                      x2={svgWidth - padding.right}
                      y2={yPos}
                      stroke="var(--border-color)"
                      strokeDasharray="4 4"
                      strokeWidth="1"
                    />
                    <text
                      x={padding.left - 8}
                      y={yPos + 4}
                      fill="var(--text-secondary)"
                      fontSize="11"
                      textAnchor="end"
                    >
                      {yVal}
                    </text>
                  </g>
                );
              })}

              {/* X Axis line */}
              <line
                x1={padding.left}
                y1={getY(0)}
                x2={svgWidth - padding.right}
                y2={getY(0)}
                stroke="var(--border-color)"
                strokeWidth="1"
              />

              {/* X Axis Date labels */}
              {dailyData.map((d, i) => {
                const showLabel =
                  dailyData.length <= 10 ||
                  i === 0 ||
                  i === dailyData.length - 1 ||
                  i % Math.ceil(dailyData.length / 7) === 0;
                if (!showLabel) return null;
                const xPos = getX(i);
                return (
                  <text
                    key={d.date}
                    x={xPos}
                    y={svgHeight - 10}
                    fill="var(--text-secondary)"
                    fontSize="10"
                    textAnchor="middle"
                  >
                    {d.date.slice(5)}
                  </text>
                );
              })}

              {/* Lines */}
              {dailyData.length > 1 && (
                <>
                  <polyline
                    fill="none"
                    stroke="#3b82f6"
                    strokeWidth="2.5"
                    points={openedPolyline}
                  />
                  <polyline
                    fill="none"
                    stroke="#10b981"
                    strokeWidth="2.5"
                    points={closedPolyline}
                  />
                </>
              )}

              {/* Data points per day with tooltips */}
              {openedPoints.map((p, idx) => (
                <circle
                  key={`opened-pt-${idx}`}
                  cx={p.x}
                  cy={p.y}
                  r="4"
                  fill="#3b82f6"
                  stroke="#1e293b"
                  strokeWidth="1.5"
                >
                  <title>{`${p.date}: ${p.val} ${t('chartOpened')}`}</title>
                </circle>
              ))}

              {closedPoints.map((p, idx) => (
                <circle
                  key={`closed-pt-${idx}`}
                  cx={p.x}
                  cy={p.y}
                  r="4"
                  fill="#10b981"
                  stroke="#1e293b"
                  strokeWidth="1.5"
                >
                  <title>{`${p.date}: ${p.val} ${t('chartClosed')}`}</title>
                </circle>
              ))}
            </svg>
          </div>
        ) : (
          <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-muted)' }}>
            {t('noData')}
          </div>
        )}
      </div>

      {/* By-Category Bars & Staff Table Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '1.5rem' }}>
        {/* By Category Bars */}
        <div className="card" style={{ padding: '1.25rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600, marginBottom: '1rem' }}>{t('byCategory')}</h3>
          {categoriesList.length > 0 ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
              {categoriesList.map((c) => {
                const widthPercent = Math.round((c.opened / maxCatOpened) * 100);
                return (
                  <div key={c.category_id || (c as any).categoryId} style={{ display: 'flex', flexDirection: 'column', gap: '0.25rem' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.9rem' }}>
                      <span style={{ fontWeight: 500 }}>{c.name}</span>
                      <span style={{ color: 'var(--text-secondary)' }}>{c.opened}</span>
                    </div>
                    <div style={{ width: '100%', height: '8px', background: 'var(--bg-tertiary)', borderRadius: '4px', overflow: 'hidden' }}>
                      <div
                        style={{
                          width: `${widthPercent}%`,
                          height: '100%',
                          background: 'var(--primary-btn)',
                          borderRadius: '4px',
                        }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div style={{ padding: '1.5rem', textAlign: 'center', color: 'var(--text-muted)' }}>
              {t('noData')}
            </div>
          )}
        </div>

        {/* Staff Leaderboard */}
        <div className="card" style={{ padding: '1.25rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600, marginBottom: '1rem' }}>{t('staffLeaderboard')}</h3>
          {sortedStaff.length > 0 ? (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', color: 'var(--text-secondary)' }}>
                    <th
                      style={{ padding: '0.5rem', cursor: 'pointer' }}
                      onClick={() => handleSort('user_id')}
                    >
                      {t('staffUser')} {sortField === 'user_id' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                    </th>
                    <th
                      style={{ padding: '0.5rem', cursor: 'pointer', textAlign: 'right' }}
                      onClick={() => handleSort('claimed')}
                    >
                      {t('staffClaimed')} {sortField === 'claimed' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                    </th>
                    <th
                      style={{ padding: '0.5rem', cursor: 'pointer', textAlign: 'right' }}
                      onClick={() => handleSort('closed')}
                    >
                      {t('staffClosed')} {sortField === 'closed' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                    </th>
                    <th
                      style={{ padding: '0.5rem', cursor: 'pointer', textAlign: 'right' }}
                      onClick={() => handleSort('rating_avg')}
                    >
                      {t('staffRating')} {sortField === 'rating_avg' ? (sortDirection === 'asc' ? '▲' : '▼') : ''}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {sortedStaff.map((s) => (
                    <tr key={s.user_id || s.userId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '0.5rem', fontFamily: 'monospace' }}>
                        {s.user_id || s.userId}
                      </td>
                      <td style={{ padding: '0.5rem', textAlign: 'right' }}>{s.claimed}</td>
                      <td style={{ padding: '0.5rem', textAlign: 'right' }}>{s.closed}</td>
                      <td style={{ padding: '0.5rem', textAlign: 'right', color: '#eab308' }}>
                        {s.rating_avg != null
                          ? `${s.rating_avg} ⭐`
                          : (s.ratingAverage != null ? `${s.ratingAverage} ⭐` : '-')}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div style={{ padding: '1.5rem', textAlign: 'center', color: 'var(--text-muted)' }}>
              {t('noData')}
            </div>
          )}
        </div>
      </div>

      {/* Audit Log Table with Pagination & Action Filter */}
      <div className="card" style={{ padding: '1.25rem', background: 'var(--card-bg)', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem', flexWrap: 'wrap', gap: '0.75rem' }}>
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600 }}>{t('auditLog')}</h3>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <span style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{t('auditAction')}:</span>
            <select
              value={auditActionFilter}
              onChange={(e) => handleFilterChange(e.target.value)}
              style={{
                background: 'var(--bg-secondary)',
                color: 'var(--text-primary)',
                border: '1px solid var(--border-color)',
                padding: '0.35rem 0.6rem',
                borderRadius: '6px',
                fontSize: '0.85rem',
              }}
            >
              <option value="">{t('allActions')}</option>
              <option value="ticket.claim">ticket.claim</option>
              <option value="ticket.close">ticket.close</option>
              <option value="ticket.reopen">ticket.reopen</option>
              <option value="ticket.transfer">ticket.transfer</option>
              <option value="settings.update">settings.update</option>
              <option value="category.create">category.create</option>
              <option value="action.queue">action.queue</option>
            </select>
          </div>
        </div>

        {auditLoading && !audit && (
          <div style={{ padding: '1.5rem', textAlign: 'center', color: 'var(--text-secondary)' }}>
            {t('loading')}
          </div>
        )}

        {auditError && (
          <div style={{ padding: '0.75rem', backgroundColor: '#ef444422', border: '1px solid #ef4444', borderRadius: '6px', color: '#f87171', marginBottom: '1rem' }}>
            {auditError}
          </div>
        )}

        {audit && audit.items.length > 0 ? (
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem' }}>
              <thead>
                <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', color: 'var(--text-secondary)' }}>
                  <th style={{ padding: '0.6rem' }}>{t('auditTime')}</th>
                  <th style={{ padding: '0.6rem' }}>{t('auditActor')}</th>
                  <th style={{ padding: '0.6rem' }}>{t('auditAction')}</th>
                  <th style={{ padding: '0.6rem' }}>{t('auditTarget')}</th>
                  <th style={{ padding: '0.6rem' }}>{t('auditDetails')}</th>
                </tr>
              </thead>
              <tbody>
                {audit.items.map((entry) => {
                  const timeStr = new Date(entry.createdAt || (entry as any).created_at).toLocaleString(
                    locale === 'th' ? 'th-TH' : 'en-US'
                  );
                  const detailStr = entry.detail ? JSON.stringify(entry.detail) : '-';
                  return (
                    <tr key={entry.id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '0.6rem', whiteSpace: 'nowrap', color: 'var(--text-muted)' }}>
                        {timeStr}
                      </td>
                      <td style={{ padding: '0.6rem', fontFamily: 'monospace' }}>
                        {entry.actorId || entry.actor_id}
                      </td>
                      <td style={{ padding: '0.6rem' }}>
                        <span
                          style={{
                            background: 'var(--bg-tertiary)',
                            padding: '0.2rem 0.4rem',
                            borderRadius: '4px',
                            fontSize: '0.8rem',
                          }}
                        >
                          {entry.kind}
                        </span>
                      </td>
                      <td style={{ padding: '0.6rem', fontFamily: 'monospace' }}>
                        {entry.target || '-'}
                      </td>
                      <td style={{ padding: '0.6rem', color: 'var(--text-secondary)', maxWidth: '250px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {detailStr}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          !auditLoading && (
            <div style={{ padding: '1.5rem', textAlign: 'center', color: 'var(--text-muted)' }}>
              {t('noData')}
            </div>
          )
        )}

        {/* Paging controls */}
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem', marginTop: '1rem' }}>
          <button
            type="button"
            className="btn"
            disabled={pageIndex === 0 || auditLoading}
            onClick={handlePrevPage}
            style={{
              padding: '0.35rem 0.75rem',
              borderRadius: '6px',
              border: '1px solid var(--border-color)',
              background: 'var(--bg-secondary)',
              color: pageIndex === 0 ? 'var(--text-muted)' : 'var(--text-primary)',
              cursor: pageIndex === 0 ? 'not-allowed' : 'pointer',
              fontSize: '0.85rem',
            }}
          >
            {t('prevPage')}
          </button>
          <button
            type="button"
            className="btn"
            disabled={!audit?.next || auditLoading}
            onClick={handleNextPage}
            style={{
              padding: '0.35rem 0.75rem',
              borderRadius: '6px',
              border: '1px solid var(--border-color)',
              background: 'var(--bg-secondary)',
              color: !audit?.next ? 'var(--text-muted)' : 'var(--text-primary)',
              cursor: !audit?.next ? 'not-allowed' : 'pointer',
              fontSize: '0.85rem',
            }}
          >
            {t('nextPage')}
          </button>
        </div>
      </div>
    </div>
  );
};
