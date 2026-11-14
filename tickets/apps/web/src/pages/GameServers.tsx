import React, { useState, useEffect, useCallback, useRef } from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';
import {
  type GameServer,
  type PairCode,
  getGameServers,
  createPairCode,
  patchGameServer,
  deleteGameServer,
} from '../api/servers.js';

export interface GameServersProps {
  guildId: string;
  locale: Locale;
}

export const GameServers: React.FC<GameServersProps> = ({ guildId, locale }) => {
  const [servers, setServers] = useState<GameServer[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  // Pair code state
  const [pairCode, setPairCode] = useState<PairCode | null>(null);
  const [countdownSeconds, setCountdownSeconds] = useState<number>(0);
  const countdownTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Rename state
  const [renamingServerId, setRenamingServerId] = useState<string | null>(null);
  const [renameInput, setRenameInput] = useState<string>('');

  // Revoke state
  const [revokingServerId, setRevokingServerId] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<boolean>(false);

  const fetchServers = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await getGameServers(guildId);
      setServers(data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setLoading(false);
    }
  }, [guildId, locale]);

  useEffect(() => {
    fetchServers();
  }, [fetchServers]);

  // Countdown timer for pairing code
  useEffect(() => {
    if (pairCode) {
      const calcRemaining = () => {
        const diff = Math.floor((new Date(pairCode.expiresAt).getTime() - Date.now()) / 1000);
        return Math.max(0, diff);
      };

      setCountdownSeconds(calcRemaining());

      countdownTimerRef.current = setInterval(() => {
        const remaining = calcRemaining();
        setCountdownSeconds(remaining);
        if (remaining <= 0 && countdownTimerRef.current) {
          clearInterval(countdownTimerRef.current);
          countdownTimerRef.current = null;
        }
      }, 1000);
    }

    return () => {
      if (countdownTimerRef.current) {
        clearInterval(countdownTimerRef.current);
        countdownTimerRef.current = null;
      }
    };
  }, [pairCode]);

  const handleCreatePairCode = async () => {
    setActionLoading(true);
    setError(null);
    try {
      const codeData = await createPairCode(guildId);
      setPairCode(codeData);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setActionLoading(false);
    }
  };

  const handleConfirmServer = async (serverId: string) => {
    setActionLoading(true);
    setError(null);
    try {
      const updated = await patchGameServer(guildId, serverId, { confirmed: true });
      setServers((prev) => prev.map((s) => (s.id === serverId ? updated : s)));
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setActionLoading(false);
    }
  };

  const handleSaveRename = async (serverId: string) => {
    if (!renameInput.trim()) return;
    setActionLoading(true);
    setError(null);
    try {
      const updated = await patchGameServer(guildId, serverId, { name: renameInput.trim() });
      setServers((prev) => prev.map((s) => (s.id === serverId ? updated : s)));
      setRenamingServerId(null);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setActionLoading(false);
    }
  };

  const handleRevokeServer = async (serverId: string) => {
    setActionLoading(true);
    setError(null);
    try {
      await deleteGameServer(guildId, serverId);
      setServers((prev) => prev.map((s) => (s.id === serverId ? { ...s, revoked: true } : s)));
      setRevokingServerId(null);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setActionLoading(false);
    }
  };

  return (
    <div className="card game-servers-page">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h2 className="card-title">{t('gameServersTitle', locale)}</h2>
        <button
          type="button"
          className="btn btn-primary"
          disabled={actionLoading}
          onClick={handleCreatePairCode}
        >
          {t('createPairCode', locale)}
        </button>
      </div>

      {error && <div className="alert alert-error">{error}</div>}

      {/* Pairing code display card */}
      {pairCode && (
        <div
          className="alert alert-info pair-code-banner"
          style={{
            marginTop: '1.5rem',
            padding: '1.25rem',
            border: '1px solid rgba(59, 130, 246, 0.5)',
            borderRadius: '8px',
            background: 'rgba(30, 58, 138, 0.2)',
          }}
        >
          <h3 style={{ marginTop: 0 }}>{t('pairCodeTitle', locale)}</h3>
          <p>{t('pairCodeInstruction', locale)}</p>
          <pre
            style={{
              padding: '0.75rem 1rem',
              background: '#111827',
              borderRadius: '6px',
              color: '#34d399',
              fontSize: '1.1rem',
              overflowX: 'auto',
            }}
          >
            <code>nakara_tickets pair {pairCode.code}</code>
          </pre>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '1rem' }}>
            <span>
              {t('expiresIn', locale)}:{' '}
              <strong>
                {Math.floor(countdownSeconds / 60)}:
                {String(countdownSeconds % 60).padStart(2, '0')}
              </strong>
            </span>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() => setPairCode(null)}
            >
              {t('dismiss', locale)}
            </button>
          </div>
        </div>
      )}

      {/* Revoke confirmation modal */}
      {revokingServerId && (
        <div
          role="dialog"
          aria-labelledby="revoke-dialog-title"
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
            <h4 id="revoke-dialog-title" className="card-title" style={{ marginTop: 0 }}>
              {t('confirmRevoke', locale)}
            </h4>
            <p>{t('revokeWarning', locale)}</p>
            <div style={{ display: 'flex', gap: '0.75rem', justifyContent: 'flex-end', marginTop: '1.25rem' }}>
              <button
                type="button"
                className="btn btn-secondary"
                disabled={actionLoading}
                onClick={() => setRevokingServerId(null)}
              >
                {t('cancel', locale)}
              </button>
              <button
                type="button"
                className="btn btn-danger"
                disabled={actionLoading}
                onClick={() => handleRevokeServer(revokingServerId)}
              >
                {t('confirmRevoke', locale)}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Servers table */}
      <div style={{ marginTop: '2rem', overflowX: 'auto' }}>
        {loading ? (
          <div className="empty-state">{t('loading', locale)}</div>
        ) : servers.length === 0 ? (
          <div className="empty-state">{t('noServers', locale)}</div>
        ) : (
          <table className="table" style={{ width: '100%', textAlign: 'left', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
                <th style={{ padding: '0.75rem' }}>{t('serverName', locale)}</th>
                <th style={{ padding: '0.75rem' }}>{t('edition', locale)}</th>
                <th style={{ padding: '0.75rem' }}>{t('version', locale)}</th>
                <th style={{ padding: '0.75rem' }}>{t('players', locale)}</th>
                <th style={{ padding: '0.75rem' }}>{t('lastSeen', locale)}</th>
                <th style={{ padding: '0.75rem' }}>{t('status', locale)}</th>
                <th style={{ padding: '0.75rem' }}>{t('actions', locale)}</th>
              </tr>
            </thead>
            <tbody>
              {servers.map((server) => {
                const isRenaming = renamingServerId === server.id;

                return (
                  <tr key={server.id} style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                    <td style={{ padding: '0.75rem' }}>
                      {isRenaming ? (
                        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                          <input
                            type="text"
                            className="form-control"
                            value={renameInput}
                            onChange={(e) => setRenameInput(e.target.value)}
                            disabled={actionLoading}
                            style={{ maxWidth: '200px' }}
                          />
                          <button
                            type="button"
                            className="btn btn-sm btn-primary"
                            disabled={actionLoading || !renameInput.trim()}
                            onClick={() => handleSaveRename(server.id)}
                          >
                            {t('save', locale)}
                          </button>
                          <button
                            type="button"
                            className="btn btn-sm btn-secondary"
                            disabled={actionLoading}
                            onClick={() => setRenamingServerId(null)}
                          >
                            {t('cancel', locale)}
                          </button>
                        </div>
                      ) : (
                        <span>{server.name}</span>
                      )}
                    </td>
                    <td style={{ padding: '0.75rem' }}>{server.edition ?? '—'}</td>
                    <td style={{ padding: '0.75rem' }}>{server.resourceVersion ?? '—'}</td>
                    <td style={{ padding: '0.75rem' }}>{server.playersOnline ?? 0}</td>
                    <td style={{ padding: '0.75rem' }}>
                      {server.lastSeenAt
                        ? new Date(server.lastSeenAt).toLocaleString()
                        : t('never', locale)}
                    </td>
                    <td style={{ padding: '0.75rem' }}>
                      {server.revoked ? (
                        <span className="badge badge-danger">{t('revoked', locale)}</span>
                      ) : server.confirmed ? (
                        <span className="badge badge-success">{t('confirmed', locale)}</span>
                      ) : (
                        <span className="badge badge-warning">{t('unconfirmed', locale)}</span>
                      )}
                    </td>
                    <td style={{ padding: '0.75rem' }}>
                      <div style={{ display: 'flex', gap: '0.5rem' }}>
                        {!server.confirmed && !server.revoked && (
                          <button
                            type="button"
                            className="btn btn-sm btn-success"
                            disabled={actionLoading}
                            onClick={() => handleConfirmServer(server.id)}
                          >
                            {t('confirm', locale)}
                          </button>
                        )}
                        {!server.revoked && (
                          <>
                            {!isRenaming && (
                              <button
                                type="button"
                                className="btn btn-sm btn-secondary"
                                disabled={actionLoading}
                                onClick={() => {
                                  setRenamingServerId(server.id);
                                  setRenameInput(server.name);
                                }}
                              >
                                {t('rename', locale)}
                              </button>
                            )}
                            <button
                              type="button"
                              className="btn btn-sm btn-danger"
                              disabled={actionLoading}
                              onClick={() => setRevokingServerId(server.id)}
                            >
                              {t('revoke', locale)}
                            </button>
                          </>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};
