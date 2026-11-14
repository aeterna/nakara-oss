import React, { useState, useEffect } from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';
import { getBlocks, createBlock, deleteBlock, type Block } from '../api/tags.js';

export interface BlocksProps {
  guildId: string;
  locale: Locale;
}

export const Blocks: React.FC<BlocksProps> = ({ guildId, locale }) => {
  const [blocksList, setBlocksList] = useState<Block[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const [isAdding, setIsAdding] = useState<boolean>(false);
  const [formUserId, setFormUserId] = useState<string>('');
  const [formReason, setFormReason] = useState<string>('');

  const loadBlocks = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await getBlocks(guildId);
      setBlocksList(data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadBlocks();
  }, [guildId]);

  const resetForm = () => {
    setFormUserId('');
    setFormReason('');
    setIsAdding(false);
  };

  const handleAddBlock = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const userId = formUserId.trim();
    const reason = formReason.trim() || undefined;

    if (!userId) {
      return;
    }

    try {
      await createBlock(guildId, { userId, reason });
      resetForm();
      await loadBlocks();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    }
  };

  const handleRemoveBlock = async (userId: string) => {
    if (typeof window !== 'undefined' && window.confirm && !window.confirm(t('confirmRemoveBlock', locale))) {
      return;
    }

    try {
      setError(null);
      await deleteBlock(guildId, userId);
      await loadBlocks();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    }
  };

  return (
    <div className="card">
      <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2 className="card-title">{t('blocksTitle', locale)}</h2>
          <p className="card-subtitle">{t('blocksDesc', locale)}</p>
        </div>
        {!isAdding && (
          <button className="btn btn-primary" onClick={() => setIsAdding(true)}>
            {t('addBlock', locale)}
          </button>
        )}
      </div>

      {error && (
        <div className="alert alert-danger" style={{ margin: '1rem 0' }}>
          {error}
        </div>
      )}

      {isAdding && (
        <form onSubmit={handleAddBlock} style={{ margin: '1rem 0', padding: '1rem', border: '1px solid #ccc', borderRadius: '4px' }}>
          <h3>{t('addBlock', locale)}</h3>

          <div className="form-group" style={{ marginBottom: '1rem' }}>
            <label htmlFor="block-userid" style={{ display: 'block', marginBottom: '0.25rem' }}>
              {t('userId', locale)}
            </label>
            <input
              id="block-userid"
              type="text"
              className="form-control"
              value={formUserId}
              onChange={(e) => setFormUserId(e.target.value)}
              placeholder="e.g. 123456789012345678"
              pattern="^[0-9]{17,20}$"
              required
              style={{ width: '100%', padding: '0.5rem' }}
            />
          </div>

          <div className="form-group" style={{ marginBottom: '1rem' }}>
            <label htmlFor="block-reason" style={{ display: 'block', marginBottom: '0.25rem' }}>
              {t('reason', locale)}
            </label>
            <input
              id="block-reason"
              type="text"
              className="form-control"
              value={formReason}
              onChange={(e) => setFormReason(e.target.value)}
              placeholder="Reason for blocking..."
              maxLength={500}
              style={{ width: '100%', padding: '0.5rem' }}
            />
          </div>

          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <button type="submit" className="btn btn-primary">
              {t('addBlock', locale)}
            </button>
            <button type="button" className="btn btn-secondary" onClick={resetForm}>
              {t('cancel', locale)}
            </button>
          </div>
        </form>
      )}

      {loading ? (
        <p>{t('loading', locale)}</p>
      ) : blocksList.length === 0 ? (
        <p>{t('noBlocks', locale)}</p>
      ) : (
        <table className="table" style={{ width: '100%', marginTop: '1rem', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ddd', padding: '0.5rem' }}>{t('userId', locale)}</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ddd', padding: '0.5rem' }}>{t('reason', locale)}</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ddd', padding: '0.5rem' }}>{t('blockedAt', locale)}</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ddd', padding: '0.5rem' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {blocksList.map((block) => {
              const targetUserId = block.userId ?? block.user_id ?? '';
              const dateStr = block.createdAt ?? block.created_at ?? '';
              const formattedDate = dateStr ? new Date(dateStr).toLocaleString() : '';

              return (
                <tr key={targetUserId}>
                  <td style={{ borderBottom: '1px solid #eee', padding: '0.5rem' }}>
                    <code>{targetUserId}</code>
                  </td>
                  <td style={{ borderBottom: '1px solid #eee', padding: '0.5rem' }}>
                    {block.reason || '-'}
                  </td>
                  <td style={{ borderBottom: '1px solid #eee', padding: '0.5rem' }}>
                    {formattedDate}
                  </td>
                  <td style={{ borderBottom: '1px solid #eee', padding: '0.5rem', textAlign: 'right' }}>
                    <button
                      className="btn btn-sm btn-danger"
                      onClick={() => handleRemoveBlock(targetUserId)}
                    >
                      {t('removeBlock', locale)}
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </div>
  );
};
