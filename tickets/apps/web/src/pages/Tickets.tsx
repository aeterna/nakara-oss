import React, { useState, useEffect } from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';
import {
  ticketsApi,
  type TicketItem,
  type MessageItem,
} from '../api/tickets.js';

// @ts-ignore - TicketActions component is written by Lane L5
import TicketActionsComponent, { TicketActions as NamedTicketActions } from '../components/TicketActions.js';

const TicketActions = (NamedTicketActions || TicketActionsComponent) as React.ComponentType<{
  guildId: string;
  ticketId: string;
  locale: Locale;
}> | undefined;

export interface TicketsProps {
  guildId: string;
  locale: Locale;
}

export const Tickets: React.FC<TicketsProps> = ({ guildId, locale }) => {
  const [ticketsList, setTicketsList] = useState<TicketItem[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [nextCursor, setNextCursor] = useState<string | null>(null);

  // Detail view state
  const [selectedTicketId, setSelectedTicketId] = useState<string | null>(null);
  const [selectedTicket, setSelectedTicket] = useState<TicketItem | null>(null);
  const [messages, setMessages] = useState<MessageItem[]>([]);
  const [loadingMessages, setLoadingMessages] = useState<boolean>(false);

  // Close modal/dialog state
  const [isClosing, setIsClosing] = useState<boolean>(false);
  const [closeReason, setCloseReason] = useState<string>('');

  const loadTickets = async (cursor?: string, append = false) => {
    try {
      setLoading(true);
      setError(null);
      const res = await ticketsApi.getTickets(guildId, {
        status: statusFilter || undefined,
        cursor,
        limit: 25,
      });

      if (append) {
        setTicketsList((prev) => [...prev, ...res.items]);
      } else {
        setTicketsList(res.items);
      }
      setNextCursor(res.next);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setLoading(false);
    }
  };

  const loadTicketDetail = async (ticketId: string) => {
    try {
      setSelectedTicketId(ticketId);
      setLoadingMessages(true);
      setError(null);

      const [ticket, msgsRes] = await Promise.all([
        ticketsApi.getTicket(guildId, ticketId),
        ticketsApi.getTicketMessages(guildId, ticketId),
      ]);

      setSelectedTicket(ticket);
      setMessages(msgsRes.items);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setLoadingMessages(false);
    }
  };

  useEffect(() => {
    if (!selectedTicketId) {
      loadTickets();
    }
  }, [guildId, statusFilter]);

  const handleSelectTicket = (tItem: TicketItem) => {
    loadTicketDetail(tItem.id);
  };

  const handleBackToList = () => {
    setSelectedTicketId(null);
    setSelectedTicket(null);
    setMessages([]);
    setIsClosing(false);
    loadTickets();
  };

  const handleTransition = async (
    transition: 'claim' | 'unclaim' | 'transfer' | 'close' | 'reopen',
    body?: { toUserId?: string; reason?: string }
  ) => {
    if (!selectedTicket) return;
    try {
      setError(null);
      const updated = await ticketsApi.transitionTicket(guildId, selectedTicket.id, transition, body);
      setSelectedTicket(updated);
      setIsClosing(false);
      setCloseReason('');
      // Reload messages in case system line was posted
      const msgsRes = await ticketsApi.getTicketMessages(guildId, selectedTicket.id);
      setMessages(msgsRes.items);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    }
  };

  const getStatusBadgeClass = (status: string) => {
    switch (status) {
      case 'open':
        return 'badge badge-open';
      case 'claimed':
        return 'badge badge-claimed';
      case 'closed':
        return 'badge badge-closed';
      default:
        return 'badge';
    }
  };

  return (
    <div>
      <div className="card">
        {error && (
          <div style={{ color: '#ef4444', marginBottom: '1rem', padding: '0.5rem', background: '#450a0a', borderRadius: '4px' }}>
            {error}
          </div>
        )}

        {selectedTicket ? (
          /* Detail View */
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
              <button type="button" className="btn btn-secondary btn-sm" onClick={handleBackToList}>
                {t('backToList', locale)}
              </button>

              <div style={{ display: 'flex', gap: '0.5rem' }}>
                {selectedTicket.status === 'open' && (
                  <button
                    type="button"
                    className="btn btn-primary btn-sm"
                    onClick={() => handleTransition('claim')}
                  >
                    {t('claim', locale)}
                  </button>
                )}

                {selectedTicket.status !== 'closed' && (
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    style={{ background: '#dc2626', borderColor: '#b91c1c', color: 'white' }}
                    onClick={() => setIsClosing(true)}
                  >
                    {t('close', locale)}
                  </button>
                )}

                {selectedTicket.status === 'closed' && (
                  <button
                    type="button"
                    className="btn btn-primary btn-sm"
                    onClick={() => handleTransition('reopen')}
                  >
                    {t('reopen', locale)}
                  </button>
                )}

                <a
                  href={`/api/v1/guilds/${encodeURIComponent(guildId)}/tickets/${encodeURIComponent(selectedTicket.id)}/transcript`}
                  download
                  className="btn btn-secondary btn-sm"
                >
                  {t('downloadTranscript', locale)}
                </a>
              </div>
            </div>

            {/* Close Reason prompt */}
            {isClosing && (
              <div style={{ background: '#1e293b', border: '1px solid #334155', borderRadius: '6px', padding: '1rem', marginBottom: '1rem' }}>
                <h4 style={{ margin: '0 0 0.5rem 0' }}>{t('confirmClose', locale)}</h4>
                <div className="form-group" style={{ marginBottom: '0.5rem' }}>
                  <label className="form-label">{t('closeReason', locale)}</label>
                  <input
                    type="text"
                    className="form-control"
                    placeholder={t('reasonPlaceholder', locale)}
                    value={closeReason}
                    onChange={(e) => setCloseReason(e.target.value)}
                  />
                </div>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <button
                    type="button"
                    className="btn btn-primary btn-sm"
                    style={{ background: '#dc2626', borderColor: '#b91c1c' }}
                    onClick={() => handleTransition('close', { reason: closeReason || undefined })}
                  >
                    {t('close', locale)}
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={() => setIsClosing(false)}
                  >
                    {t('cancel', locale)}
                  </button>
                </div>
              </div>
            )}

            {/* Ticket Info Card */}
            <div style={{ background: '#0f172a', padding: '1rem', borderRadius: '6px', marginBottom: '1.5rem', border: '1px solid #334155' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <h3 style={{ margin: 0 }}>
                  Ticket #{selectedTicket.number}
                </h3>
                <span className={getStatusBadgeClass(selectedTicket.status)}>
                  {selectedTicket.status}
                </span>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '0.75rem', marginTop: '1rem', fontSize: '0.875rem' }}>
                <div><strong>{t('opener', locale)}:</strong> {selectedTicket.openerId}</div>
                <div><strong>{t('claimer', locale)}:</strong> {selectedTicket.claimerId || t('unassigned', locale)}</div>
                <div><strong>{t('createdAt', locale)}:</strong> {new Date(selectedTicket.createdAt).toLocaleString()}</div>
                {selectedTicket.closeReason && (
                  <div><strong>{t('closeReason', locale)}:</strong> {selectedTicket.closeReason}</div>
                )}
              </div>
            </div>

            {/* Render Game Actions Component from Lane L5 */}
            {TicketActions && (
              <div style={{ marginBottom: '1.5rem' }}>
                <TicketActions guildId={guildId} ticketId={selectedTicket.id} locale={locale} />
              </div>
            )}

            {/* Messages Section */}
            <div>
              <h3 style={{ marginBottom: '1rem' }}>{t('messages', locale)}</h3>
              {loadingMessages ? (
                <div className="empty-state">{t('loading', locale)}</div>
              ) : messages.length === 0 ? (
                <div className="empty-state">{t('noMessages', locale)}</div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                  {messages.map((msg) => (
                    <div
                      key={msg.id}
                      style={{
                        background: '#1e293b',
                        borderRadius: '6px',
                        padding: '0.75rem 1rem',
                        border: '1px solid #334155',
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.25rem', fontSize: '0.8125rem' }}>
                        <div>
                          {msg.isStaff && (
                            <span className="badge" style={{ background: '#0284c7', color: 'white', marginRight: '0.5rem' }}>
                              {t('staffBadge', locale)}
                            </span>
                          )}
                          {msg.isSystem && (
                            <span className="badge" style={{ background: '#475569', color: 'white', marginRight: '0.5rem' }}>
                              {t('systemBadge', locale)}
                            </span>
                          )}
                          <strong>{msg.authorName}</strong>
                        </div>
                        <span style={{ color: '#94a3b8' }}>
                          {new Date(msg.createdAt).toLocaleTimeString()}
                        </span>
                      </div>
                      <div style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word', color: '#e2e8f0', fontSize: '0.9375rem' }}>
                        {msg.content}
                      </div>

                      {/* Attachments List */}
                      {msg.attachments && msg.attachments.length > 0 && (
                        <div style={{ marginTop: '0.5rem', paddingTop: '0.5rem', borderTop: '1px solid #334155', fontSize: '0.8125rem' }}>
                          <span style={{ color: '#94a3b8', marginRight: '0.5rem' }}>{t('attachments', locale)}:</span>
                          {msg.attachments.map((att) => (
                            <span key={att.id} style={{ marginRight: '1rem' }}>
                              {att.stored ? (
                                <a
                                  href={`/api/v1/guilds/${encodeURIComponent(guildId)}/attachments/${encodeURIComponent(att.id)}`}
                                  download
                                  style={{ color: '#38bdf8', textDecoration: 'underline' }}
                                >
                                  {att.filename}
                                </a>
                              ) : (
                                <span style={{ color: '#94a3b8' }}>{att.filename}</span>
                              )}
                              <span style={{ color: '#64748b', marginLeft: '0.25rem' }}>
                                ({Math.round(att.size / 1024)} KB)
                              </span>
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        ) : (
          /* Tickets List View */
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
              <div>
                <h2 className="card-title">{t('ticketsTitle', locale)}</h2>
              </div>
              <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                <label style={{ fontSize: '0.875rem' }}>{t('filterStatus', locale)}:</label>
                <select
                  className="form-control"
                  style={{ width: 'auto', display: 'inline-block' }}
                  value={statusFilter}
                  onChange={(e) => setStatusFilter(e.target.value)}
                >
                  <option value="">{t('allStatuses', locale)}</option>
                  <option value="open">{t('statusOpen', locale)}</option>
                  <option value="claimed">{t('statusClaimed', locale)}</option>
                  <option value="closed">{t('statusClosed', locale)}</option>
                </select>
              </div>
            </div>

            {loading && ticketsList.length === 0 ? (
              <div className="empty-state">{t('loading', locale)}</div>
            ) : ticketsList.length === 0 ? (
              <div className="empty-state">{t('noMessages', locale)}</div>
            ) : (
              <div>
                <table className="table">
                  <thead>
                    <tr>
                      <th>{t('ticketNumber', locale)}</th>
                      <th>{t('filterStatus', locale)}</th>
                      <th>{t('opener', locale)}</th>
                      <th>{t('claimer', locale)}</th>
                      <th>{t('createdAt', locale)}</th>
                      <th style={{ textAlign: 'right' }}>{t('actions', locale)}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {ticketsList.map((tk) => (
                      <tr
                        key={tk.id}
                        style={{ cursor: 'pointer' }}
                        onClick={() => handleSelectTicket(tk)}
                      >
                        <td style={{ fontWeight: 600 }}>#{tk.number}</td>
                        <td>
                          <span className={getStatusBadgeClass(tk.status)}>
                            {tk.status}
                          </span>
                        </td>
                        <td style={{ fontSize: '0.85rem' }}>{tk.openerId}</td>
                        <td style={{ fontSize: '0.85rem' }}>{tk.claimerId || t('unassigned', locale)}</td>
                        <td style={{ fontSize: '0.85rem', color: '#94a3b8' }}>
                          {new Date(tk.createdAt).toLocaleDateString()}
                        </td>
                        <td style={{ textAlign: 'right' }}>
                          <button
                            type="button"
                            className="btn btn-secondary btn-sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              handleSelectTicket(tk);
                            }}
                          >
                            {t('view', locale)}
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>

                {nextCursor && (
                  <div style={{ textAlign: 'center', marginTop: '1rem' }}>
                    <button
                      type="button"
                      className="btn btn-secondary"
                      onClick={() => loadTickets(nextCursor, true)}
                    >
                      {t('loadMore', locale)}
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
