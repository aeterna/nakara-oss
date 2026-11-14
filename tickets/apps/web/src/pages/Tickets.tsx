import React from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';

export interface TicketsProps {
  guildId: string;
  locale: Locale;
}

export const Tickets: React.FC<TicketsProps> = ({ guildId, locale }) => {
  return (
    <div className="card">
      <h2 className="card-title">{t('ticketsTitle', locale)}</h2>
    </div>
  );
};
