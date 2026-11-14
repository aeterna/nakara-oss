import React from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';

export interface GameServersProps {
  guildId: string;
  locale: Locale;
}

export const GameServers: React.FC<GameServersProps> = ({ guildId, locale }) => {
  return (
    <div className="card">
      <h2 className="card-title">{t('gameServersTitle', locale)}</h2>
    </div>
  );
};
