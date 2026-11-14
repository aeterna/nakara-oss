import React from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';

export interface TagsProps {
  guildId: string;
  locale: Locale;
}

export const Tags: React.FC<TagsProps> = ({ guildId, locale }) => {
  return (
    <div className="card">
      <h2 className="card-title">{t('tagsTitle', locale)}</h2>
    </div>
  );
};
