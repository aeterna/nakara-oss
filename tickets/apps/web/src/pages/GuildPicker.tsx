import React from 'react';
import type { Guild } from '../types.js';
import { t, type Locale } from '../i18n.js';

export interface GuildPickerProps {
  guilds: Guild[];
  onSelectGuild: (guildId: string) => void;
  locale: Locale;
}

export const GuildPicker: React.FC<GuildPickerProps> = ({ guilds, onSelectGuild, locale }) => {
  return (
    <div>
      <div className="card">
        <h2 className="card-title">{t('guildPickerTitle', locale)}</h2>
        <p className="card-desc">{t('guildPickerDesc', locale)}</p>

        {guilds.length === 0 ? (
          <div className="empty-state">{t('noCategories', locale)}</div>
        ) : (
          <div className="server-grid">
            {guilds.map((guild) => {
              const iconUrl = guild.icon
                ? `https://cdn.discordapp.com/icons/${guild.id}/${guild.icon}.png`
                : null;
              return (
                <div key={guild.id} className="server-card">
                  <div className="server-header">
                    {iconUrl ? (
                      <img src={iconUrl} alt={guild.name} className="server-icon" />
                    ) : (
                      <div className="server-icon">{guild.name.slice(0, 2).toUpperCase()}</div>
                    )}
                    <div>
                      <div style={{ fontWeight: 600 }}>{guild.name}</div>
                      <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>{guild.id}</div>
                    </div>
                  </div>
                  <div>
                    {guild.canManage ? (
                      <button
                        type="button"
                        className="btn btn-primary btn-sm"
                        style={{ width: '100%' }}
                        onClick={() => onSelectGuild(guild.id)}
                      >
                        {t('manage', locale)}
                      </button>
                    ) : (
                      <button type="button" className="btn btn-secondary btn-sm" style={{ width: '100%' }} disabled>
                        {t('noPermission', locale)}
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
