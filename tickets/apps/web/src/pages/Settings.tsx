import React, { useState, useEffect } from 'react';
import type { GuildSettings } from '../types.js';
import { api } from '../api.js';
import { t, type Locale } from '../i18n.js';

export interface SettingsProps {
  guildId: string;
  locale: Locale;
}

export const Settings: React.FC<SettingsProps> = ({ guildId, locale }) => {
  const [settingsLocale, setSettingsLocale] = useState<'th' | 'en'>('th');
  const [retentionDays, setRetentionDays] = useState<string>('90');
  const [logChannelId, setLogChannelId] = useState<string>('');
  const [ratingDm, setRatingDm] = useState<boolean>(false);
  const [privacyPolicyUrl, setPrivacyPolicyUrl] = useState<string>('');

  const [loading, setLoading] = useState<boolean>(true);
  const [saving, setSaving] = useState<boolean>(false);
  const [success, setSuccess] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;
    const fetchSettings = async () => {
      try {
        setLoading(true);
        setError(null);
        const data = await api.getSettings(guildId);
        if (mounted && data) {
          setSettingsLocale(data.locale);
          setRetentionDays(String(data.retentionDays ?? 90));
          setLogChannelId(data.logChannelId || '');
          setRatingDm(Boolean(data.ratingDm));
          setPrivacyPolicyUrl(data.privacyPolicyUrl || '');
        }
      } catch (err: unknown) {
        if (mounted) {
          setError(err instanceof Error ? err.message : t('error', locale));
        }
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    };

    fetchSettings();
    return () => {
      mounted = false;
    };
  }, [guildId]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    setSuccess(false);

    const payload: GuildSettings = {
      locale: settingsLocale,
      retentionDays: parseInt(retentionDays, 10) || 90,
      logChannelId: logChannelId.trim() || null,
      ratingDm,
      privacyPolicyUrl: privacyPolicyUrl.trim() || null,
    };

    try {
      await api.putSettings(guildId, payload);
      setSuccess(true);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="card">
        <div className="empty-state">{t('loading', locale)}</div>
      </div>
    );
  }

  return (
    <div className="card">
      <h2 className="card-title">{t('settingsTitle', locale)}</h2>
      <p className="card-desc">{t('settingsDesc', locale)}</p>

      {success && <div className="alert alert-success">{t('settingsSaved', locale)}</div>}
      {error && <div className="alert alert-error">{error}</div>}

      <form onSubmit={handleSubmit}>
        <div className="form-group">
          <label htmlFor="settings-locale" className="form-label">{t('locale', locale)}</label>
          <select
            id="settings-locale"
            className="form-control"
            value={settingsLocale}
            onChange={(e) => setSettingsLocale(e.target.value as 'th' | 'en')}
          >
            <option value="th">ไทย (th)</option>
            <option value="en">English (en)</option>
          </select>
        </div>

        <div className="form-group">
          <label htmlFor="settings-retention" className="form-label">{t('retentionDays', locale)}</label>
          <input
            id="settings-retention"
            type="number"
            min="1"
            max="3650"
            className="form-control"
            value={retentionDays}
            onChange={(e) => setRetentionDays(e.target.value)}
            required
          />
        </div>

        <div className="form-group">
          <label htmlFor="settings-log-channel" className="form-label">{t('logChannelId', locale)}</label>
          <input
            id="settings-log-channel"
            type="text"
            className="form-control"
            value={logChannelId}
            onChange={(e) => setLogChannelId(e.target.value)}
            placeholder="123456789012345678"
          />
        </div>

        <div className="form-group">
          <label className="form-checkbox-label">
            <input
              type="checkbox"
              checked={ratingDm}
              onChange={(e) => setRatingDm(e.target.checked)}
            />
            {t('ratingDm', locale)}
          </label>
        </div>

        <div className="form-group">
          <label htmlFor="settings-privacy" className="form-label">{t('privacyPolicyUrl', locale)}</label>
          <input
            id="settings-privacy"
            type="url"
            className="form-control"
            value={privacyPolicyUrl}
            onChange={(e) => setPrivacyPolicyUrl(e.target.value)}
            placeholder="https://example.com/privacy"
          />
        </div>

        <div className="form-actions">
          <button type="submit" className="btn btn-primary" disabled={saving}>
            {t('saveSettings', locale)}
          </button>
        </div>
      </form>
    </div>
  );
};
