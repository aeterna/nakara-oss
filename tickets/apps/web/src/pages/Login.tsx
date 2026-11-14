import React from 'react';
import { t, type Locale } from '../i18n.js';

export interface LoginProps {
  locale: Locale;
}

export const Login: React.FC<LoginProps> = ({ locale }) => {
  return (
    <div className="center-box">
      <div className="card">
        <h1 className="card-title">{t('appTitle', locale)}</h1>
        <p className="card-desc">{t('loginDesc', locale)}</p>
        <a href="/auth/login" className="btn btn-primary" style={{ width: '100%', padding: '0.75rem' }}>
          {t('loginWithDiscord', locale)}
        </a>
      </div>
    </div>
  );
};
