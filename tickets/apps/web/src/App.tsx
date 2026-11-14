import React, { useState, useEffect } from 'react';
import type { Me } from './types.js';
import { api } from './api.js';
import { t, type Locale } from './i18n.js';
import { Login } from './pages/Login.js';
import { GuildPicker } from './pages/GuildPicker.js';
import { Tickets } from './pages/Tickets.js';
import { Categories } from './pages/Categories.js';
import { Panels } from './pages/Panels.js';
import { Tags } from './pages/Tags.js';
import { Blocks } from './pages/Blocks.js';
import { Analytics } from './pages/Analytics.js';
import { GameServers } from './pages/GameServers.js';
import { Settings } from './pages/Settings.js';
import { Privacy } from './pages/Privacy.js';

export type Page =
  | 'guilds'
  | 'tickets'
  | 'categories'
  | 'panels'
  | 'tags'
  | 'blocks'
  | 'analytics'
  | 'servers'
  | 'settings'
  | 'privacy';

export const App: React.FC = () => {
  const [locale, setLocale] = useState<Locale>('th');
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [selectedGuildId, setSelectedGuildId] = useState<string | null>(null);
  const [currentPage, setCurrentPage] = useState<Page>('guilds');

  useEffect(() => {
    let mounted = true;
    const checkAuth = async () => {
      try {
        setLoading(true);
        const data = await api.getMe();
        if (mounted) {
          setMe(data);
          const firstManageable = data.guilds?.find((g) => g.canManage);
          if (firstManageable) {
            setSelectedGuildId(firstManageable.id);
            setCurrentPage('tickets');
          }
        }
      } catch {
        if (mounted) {
          setMe(null);
        }
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    };

    checkAuth();
    return () => {
      mounted = false;
    };
  }, []);

  const handleLogout = async () => {
    try {
      await api.logout();
    } catch {
      // ignore
    } finally {
      setMe(null);
      setSelectedGuildId(null);
      setCurrentPage('guilds');
    }
  };

  const toggleLanguage = () => {
    setLocale((prev) => (prev === 'th' ? 'en' : 'th'));
  };

  return (
    <>
      <nav className="navbar">
        <div className="navbar-brand">
          <span>{t('appTitle', locale)}</span>
        </div>

        <div className="navbar-nav">
          {me && selectedGuildId && (
            <>
              <button
                type="button"
                className={`nav-link ${currentPage === 'tickets' ? 'active' : ''}`}
                onClick={() => setCurrentPage('tickets')}
              >
                {t('tickets', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'categories' ? 'active' : ''}`}
                onClick={() => setCurrentPage('categories')}
              >
                {t('categories', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'panels' ? 'active' : ''}`}
                onClick={() => setCurrentPage('panels')}
              >
                {t('panels', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'tags' ? 'active' : ''}`}
                onClick={() => setCurrentPage('tags')}
              >
                {t('tags', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'blocks' ? 'active' : ''}`}
                onClick={() => setCurrentPage('blocks')}
              >
                {t('blocks', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'analytics' ? 'active' : ''}`}
                onClick={() => setCurrentPage('analytics')}
              >
                {t('analytics', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'servers' ? 'active' : ''}`}
                onClick={() => setCurrentPage('servers')}
              >
                {t('gameServers', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'settings' ? 'active' : ''}`}
                onClick={() => setCurrentPage('settings')}
              >
                {t('settings', locale)}
              </button>
              <button
                type="button"
                className={`nav-link ${currentPage === 'privacy' ? 'active' : ''}`}
                onClick={() => setCurrentPage('privacy')}
              >
                {t('privacy', locale)}
              </button>
              <button
                type="button"
                className="nav-link"
                onClick={() => setCurrentPage('guilds')}
              >
                {t('switchGuild', locale)}
              </button>
            </>
          )}

          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={toggleLanguage}
            aria-label={locale === 'th' ? 'Switch to English' : 'Switch to Thai'}
          >
            {locale === 'th' ? 'EN' : 'TH'}
          </button>

          {me && (
            <div className="user-profile">
              {me.user.avatar ? (
                <img
                  src={`https://cdn.discordapp.com/avatars/${me.user.id}/${me.user.avatar}.png`}
                  alt={me.user.username}
                  className="avatar"
                />
              ) : (
                <div className="avatar" />
              )}
              <span>{me.user.username}</span>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={handleLogout}
                style={{ marginLeft: '0.5rem' }}
              >
                {t('logout', locale)}
              </button>
            </div>
          )}
        </div>
      </nav>

      <main className="container">
        {loading ? (
          <div className="card">
            <div className="empty-state">{t('loading', locale)}</div>
          </div>
        ) : !me ? (
          <Login locale={locale} />
        ) : currentPage === 'guilds' || !selectedGuildId ? (
          <GuildPicker
            guilds={me.guilds || []}
            onSelectGuild={(id) => {
              setSelectedGuildId(id);
              setCurrentPage('tickets');
            }}
            locale={locale}
          />
        ) : currentPage === 'tickets' ? (
          <Tickets guildId={selectedGuildId} locale={locale} />
        ) : currentPage === 'categories' ? (
          <Categories guildId={selectedGuildId} locale={locale} />
        ) : currentPage === 'panels' ? (
          <Panels guildId={selectedGuildId} locale={locale} />
        ) : currentPage === 'tags' ? (
          <Tags guildId={selectedGuildId} locale={locale} />
        ) : currentPage === 'blocks' ? (
          <Blocks guildId={selectedGuildId} locale={locale} />
        ) : currentPage === 'analytics' ? (
          <Analytics guildId={selectedGuildId} locale={locale} />
        ) : currentPage === 'servers' ? (
          <GameServers guildId={selectedGuildId} locale={locale} />
        ) : currentPage === 'privacy' ? (
          <Privacy guildId={selectedGuildId} locale={locale} />
        ) : (
          <Settings guildId={selectedGuildId} locale={locale} />
        )}
      </main>
    </>
  );
};
