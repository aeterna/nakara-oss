import React, { useState, useEffect } from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';
import { api } from '../api.js';
import { deleteMyData, exportGuildData, type DeleteDataCounts } from '../api/privacy.js';

export interface PrivacyProps {
  guildId: string;
  locale: Locale;
}

export const Privacy: React.FC<PrivacyProps> = ({ guildId, locale }) => {
  const [isStaff, setIsStaff] = useState<boolean>(false);
  const [confirmStep, setConfirmStep] = useState<boolean>(false);
  const [deleting, setDeleting] = useState<boolean>(false);
  const [deletedCounts, setDeletedCounts] = useState<DeleteDataCounts | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exporting, setExporting] = useState<boolean>(false);

  useEffect(() => {
    let mounted = true;
    api
      .getMe()
      .then((me) => {
        if (!mounted) return;
        const currentGuild = me.guilds?.find((g) => g.id === guildId);
        if (currentGuild?.canManage) {
          setIsStaff(true);
        }
      })
      .catch(() => {});

    return () => {
      mounted = false;
    };
  }, [guildId]);

  const handleDeleteClick = () => {
    setError(null);
    setConfirmStep(true);
  };

  const handleCancelClick = () => {
    setConfirmStep(false);
    setError(null);
  };

  const handleConfirmDelete = async () => {
    if (deleting) return;
    setDeleting(true);
    setError(null);
    try {
      const res = await deleteMyData();
      const counts: DeleteDataCounts = {
        messages: res.counts?.messages ?? res.messages ?? 0,
        attachments: res.counts?.attachments ?? res.attachments ?? 0,
        ratings: res.counts?.ratings ?? res.ratings ?? 0,
        tickets: res.counts?.tickets ?? res.tickets ?? 0,
      };
      setDeletedCounts(counts);
      setConfirmStep(false);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setDeleting(false);
    }
  };

  const handleExportGuild = async () => {
    if (exporting) return;
    setExporting(true);
    setError(null);
    try {
      const data = await exportGuildData(guildId);
      const blob = new Blob([JSON.stringify(data, null, 2)], {
        type: 'application/json',
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `nakara-tickets-${guildId}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="card">
      <h2 className="card-title">{t('privacyTitle', locale)}</h2>
      <p className="card-desc">{t('privacyDesc', locale)}</p>

      {error && <div className="alert alert-error">{error}</div>}

      <div className="privacy-section" style={{ marginTop: '1.5rem' }}>
        <h3>{t('deleteMyData', locale)}</h3>
        <p>{t('deleteMyDataDesc', locale)}</p>

        {deletedCounts && (
          <div className="alert alert-success" data-testid="delete-success">
            <p>{t('deleteSuccess', locale)}</p>
            <p>
              {t('deletedCounts', locale)
                .replace('{messages}', String(deletedCounts.messages))
                .replace('{attachments}', String(deletedCounts.attachments))
                .replace('{ratings}', String(deletedCounts.ratings))
                .replace('{tickets}', String(deletedCounts.tickets))}
            </p>
          </div>
        )}

        {!confirmStep ? (
          <button
            type="button"
            className="btn btn-danger"
            onClick={handleDeleteClick}
            disabled={deleting}
          >
            {t('deleteMyData', locale)}
          </button>
        ) : (
          <div className="confirm-box" style={{ padding: '1rem', border: '1px solid #e00', borderRadius: '4px' }}>
            <p style={{ fontWeight: 'bold' }}>{t('confirmDeletePrompt', locale)}</p>
            <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem' }}>
              <button
                type="button"
                className="btn btn-danger"
                onClick={handleConfirmDelete}
                disabled={deleting}
              >
                {deleting ? t('deleting', locale) : t('confirmDeleteButton', locale)}
              </button>
              <button
                type="button"
                className="btn btn-secondary"
                onClick={handleCancelClick}
                disabled={deleting}
              >
                {t('cancelButton', locale)}
              </button>
            </div>
          </div>
        )}
      </div>

      {isStaff && (
        <div className="privacy-section" style={{ marginTop: '2rem', borderTop: '1px solid #ccc', paddingTop: '1.5rem' }}>
          <h3>{t('exportGuild', locale)}</h3>
          <p>{t('exportGuildDesc', locale)}</p>
          <button
            type="button"
            className="btn btn-primary"
            onClick={handleExportGuild}
            disabled={exporting}
          >
            {exporting ? t('exporting', locale) : t('exportButton', locale)}
          </button>
        </div>
      )}
    </div>
  );
};
