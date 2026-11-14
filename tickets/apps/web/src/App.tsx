import React, { useState, useEffect } from 'react';
import type { Me } from './types.js';
import { api } from './api.js';
import { t, type Locale } from './i18n.js';
import { Login } from './pages/Login.js';
import { GuildPicker } from './pages/GuildPicker.js';
import { Categories } from './pages/Categories.js';
import { Settings } from './pages/Settings.js';

export const App: React.FC = () => {
  const [locale, setLocale] = useState<Locale>('th');
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [selectedGuildId, setSelectedGuildId] = useState<string | null>(null);
  const [currentPage, setCurrentPage] = useState<'guilds' | 'categories' | 'settings'>('guilds');

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
            setCurrentPage('categories');
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
                className={`nav-link ${currentPage === 'categories' ? 'active' : ''}`}
                onClick={() => setCurrentPage('categories')}
              >
                {t('categories', locale)}
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
              setCurrentPage('categories');
            }}
            locale={locale}
          />
        ) : currentPage === 'categories' ? (
          <Categories guildId={selectedGuildId} locale={locale} />
        ) : (
          <Settings guildId={selectedGuildId} locale={locale} />
        )}
      </main>
    </>
  );
};
