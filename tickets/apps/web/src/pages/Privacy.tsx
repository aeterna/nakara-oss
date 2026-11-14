import React from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';

export interface PrivacyProps {
  guildId: string;
  locale: Locale;
}

export const Privacy: React.FC<PrivacyProps> = ({ guildId, locale }) => {
  return (
    <div className="card">
      <h2 className="card-title">{t('privacyTitle', locale)}</h2>
    </div>
  );
};
