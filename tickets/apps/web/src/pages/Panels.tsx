import React from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';

export interface PanelsProps {
  guildId: string;
  locale: Locale;
}

export const Panels: React.FC<PanelsProps> = ({ guildId, locale }) => {
  return (
    <div className="card">
      <h2 className="card-title">{t('panelsTitle', locale)}</h2>
    </div>
  );
};
