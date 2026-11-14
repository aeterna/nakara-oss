import React, { useState, useEffect, useCallback, useRef } from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';
import {
  type GameAction,
  getTicketActions,
  postTicketAction,
} from '../api/servers.js';

export interface TicketActionsProps {
  guildId: string;
  ticketId: string;
  locale: Locale;
}

export const TicketActions: React.FC<TicketActionsProps> = ({ guildId, ticketId, locale }) => {
  const [actions, setActions] = useState<GameAction[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState<boolean>(false);

  // Form inputs
  const [spot, setSpot] = useState<string>('');
  const [item, setItem] = useState<string>('');
  const [count, setCount] = useState<string>('1');

  // Repeat confirmation dialog state
  const [pendingRepeatAction, setPendingRepeatAction] = useState<{
    action: string;
    params?: Record<string, unknown>;
  } | null>(null);

  const pollTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const fetchActions = useCallback(async () => {
    try {
      const data = await getTicketActions(guildId, ticketId);
      setActions(data);
    } catch (err: unknown) {
      // Background poll error silently preserved if actions already loaded
      if (actions.length === 0) {
        setError(err instanceof Error ? err.message : t('actionFailed', locale));
      }
    } finally {
      setLoading(false);
    }
  }, [guildId, ticketId, locale, actions.length]);

  useEffect(() => {
    fetchActions();
  }, [fetchActions]);

  // Polling every 3 s while any action is queued or leased
  useEffect(() => {
    const hasPending = actions.some((a) => a.status === 'queued' || a.status === 'leased');

    if (hasPending) {
      pollTimerRef.current = setTimeout(() => {
        fetchActions();
      }, 3000);
    }

    return () => {
      if (pollTimerRef.current) {
        clearTimeout(pollTimerRef.current);
        pollTimerRef.current = null;
      }
    };
  }, [actions, fetchActions]);

  const handleAction = async (
    actionName: string,
    params?: Record<string, unknown>,
    confirmRepeat = false
  ) => {
    setSubmitting(true);
    setError(null);

    try {
      const queued = await postTicketAction(guildId, ticketId, {
        action: actionName,
        params,
        confirmRepeat,
      });

      setPendingRepeatAction(null);
      setActions((prev) => [queued, ...prev.filter((a) => a.id !== queued.id)]);

      if (actionName === 'player.teleport') setSpot('');
      if (actionName === 'player.give_item') {
        setItem('');
        setCount('1');
      }
    } catch (err: any) {
      if (err?.status === 409 || err?.code === 'repeat_confirm') {
        setPendingRepeatAction({ action: actionName, params });
      } else {
        setError(err instanceof Error ? err.message : t('actionFailed', locale));
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="card ticket-actions">
      <h3 className="card-title">{t('ticketActionsTitle', locale)}</h3>

      {error && <div className="alert alert-error">{error}</div>}

      {/* Action buttons and inputs */}
      <div className="action-buttons" style={{ display: 'flex', flexDirection: 'column', gap: '1rem', marginTop: '1rem' }}>
        {/* Quick action buttons: Info and Revive */}
        <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
          <button
            type="button"
            className="btn btn-secondary"
            disabled={submitting}
            onClick={() => handleAction('player.info', {})}
          >
            {t('info', locale)}
          </button>

          <button
            type="button"
            className="btn btn-secondary"
            disabled={submitting}
            onClick={() => handleAction('player.revive', {})}
          >
            {t('revive', locale)}
          </button>
        </div>

        {/* Teleport section */}
        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
          <input
            type="text"
            className="form-control"
            placeholder={t('spotPlaceholder', locale)}
            value={spot}
            onChange={(e) => setSpot(e.target.value)}
            disabled={submitting}
            style={{ maxWidth: '240px' }}
          />
          <button
            type="button"
            className="btn btn-secondary"
            disabled={submitting || !spot.trim()}
            onClick={() => handleAction('player.teleport', { spot: spot.trim() })}
          >
            {t('teleport', locale)}
          </button>
        </div>

        {/* Give item section */}
        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap' }}>
          <input
            type="text"
            className="form-control"
            placeholder={t('itemPlaceholder', locale)}
            value={item}
            onChange={(e) => setItem(e.target.value)}
            disabled={submitting}
            style={{ maxWidth: '200px' }}
          />
          <input
            type="number"
            min="1"
            className="form-control"
            placeholder={t('countPlaceholder', locale)}
            value={count}
            onChange={(e) => setCount(e.target.value)}
            disabled={submitting}
            style={{ maxWidth: '100px' }}
          />
          <button
            type="button"
            className="btn btn-primary"
            disabled={submitting || !item.trim()}
            onClick={() => {
              const num = parseInt(count, 10);
              handleAction('player.give_item', {
                item: item.trim(),
                count: Number.isInteger(num) && num >= 1 ? num : 1,
              });
            }}
          >
            {t('giveItem', locale)}
          </button>
        </div>
      </div>

      {/* Repeat Confirm Dialog */}
      {pendingRepeatAction && (
        <div
          role="dialog"
          aria-labelledby="repeat-confirm-title"
          className="modal-backdrop"
          style={{
            position: 'fixed',
            inset: 0,
            background: 'rgba(0,0,0,0.5)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
          }}
        >
          <div
            className="card modal-content"
            style={{ maxWidth: '450px', margin: '1rem', background: '#1e1e2e', padding: '1.5rem', borderRadius: '8px' }}
          >
            <h4 id="repeat-confirm-title" className="card-title" style={{ marginTop: 0 }}>
              {t('repeatConfirmTitle', locale)}
            </h4>
            <p>{t('repeatConfirmMessage', locale)}</p>
            <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '1.25rem' }}>
              <button
                type="button"
                className="btn btn-secondary"
                disabled={submitting}
                onClick={() => setPendingRepeatAction(null)}
              >
                {t('cancel', locale)}
              </button>
              <button
                type="button"
                className="btn btn-danger"
                disabled={submitting}
                onClick={() => handleAction(pendingRepeatAction.action, pendingRepeatAction.params, true)}
              >
                {t('repeatConfirmButton', locale)}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Recent Actions List */}
      <div style={{ marginTop: '2rem' }}>
        <h4>{t('recentActions', locale)}</h4>
        {loading && actions.length === 0 ? (
          <div>{t('loading', locale)}</div>
        ) : actions.length === 0 ? (
          <div className="empty-state">{t('noRecentActions', locale)}</div>
        ) : (
          <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
            {actions.map((act) => (
              <li
                key={act.id}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  padding: '0.5rem 0',
                  borderBottom: '1px solid rgba(255,255,255,0.1)',
                }}
              >
                <div>
                  <strong>{act.action}</strong>
                  {act.params && Object.keys(act.params).length > 0 && (
                    <span style={{ marginLeft: '0.5rem', opacity: 0.8 }}>
                      ({JSON.stringify(act.params)})
                    </span>
                  )}
                  {act.result && (
                    <span style={{ marginLeft: '0.5rem', opacity: 0.8 }}>
                      {act.result.ok ? '✅' : '❌'} [{act.result.code}]
                    </span>
                  )}
                </div>
                <div>
                  <span className={`badge badge-${act.status}`}>{act.status}</span>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
};
