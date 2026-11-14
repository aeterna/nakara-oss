import React from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';

export interface AnalyticsProps {
  guildId: string;
  locale: Locale;
}

export const Analytics: React.FC<AnalyticsProps> = ({ guildId, locale }) => {
  return (
    <div className="card">
      <h2 className="card-title">{t('analyticsTitle', locale)}</h2>
    </div>
  );
};
