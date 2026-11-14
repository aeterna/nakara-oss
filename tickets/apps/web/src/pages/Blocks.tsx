import React from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';

export interface BlocksProps {
  guildId: string;
  locale: Locale;
}

export const Blocks: React.FC<BlocksProps> = ({ guildId, locale }) => {
  return (
    <div className="card">
      <h2 className="card-title">{t('blocksTitle', locale)}</h2>
    </div>
  );
};
