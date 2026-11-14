import React, { useState, useEffect } from 'react';
import type { Category, CategoryInput } from '../types.js';
import { api } from '../api.js';
import { t, type Locale } from '../i18n.js';

export interface CategoriesProps {
  guildId: string;
  locale: Locale;
}

export const Categories: React.FC<CategoriesProps> = ({ guildId, locale }) => {
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const [isEditing, setIsEditing] = useState<boolean>(false);
  const [editingId, setEditingId] = useState<string | null>(null);

  // Form fields
  const [formName, setFormName] = useState<string>('');
  const [formEmoji, setFormEmoji] = useState<string>('');
  const [formMode, setFormMode] = useState<'thread' | 'channel'>('thread');
  const [formParentId, setFormParentId] = useState<string>('');
  const [formRoles, setFormRoles] = useState<string>('');
  const [formTemplate, setFormTemplate] = useState<string>('ticket-{number}');
  const [formMaxOpen, setFormMaxOpen] = useState<string>('1');
  const [formWelcome, setFormWelcome] = useState<string>('');
  const [formAutoClose, setFormAutoClose] = useState<string>('');

  const loadCategories = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await api.getCategories(guildId);
      setCategories(data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadCategories();
  }, [guildId]);

  const resetForm = () => {
    setFormName('');
    setFormEmoji('');
    setFormMode('thread');
    setFormParentId('');
    setFormRoles('');
    setFormTemplate('ticket-{number}');
    setFormMaxOpen('1');
    setFormWelcome('');
    setFormAutoClose('');
    setEditingId(null);
    setIsEditing(false);
  };

  const handleOpenCreate = () => {
    resetForm();
    setIsEditing(true);
  };

  const handleOpenEdit = (category: Category) => {
    setEditingId(category.id);
    setFormName(category.name);
    setFormEmoji(category.emoji || '');
    setFormMode(category.mode);
    setFormParentId(category.parentChannelId);
    setFormRoles(category.staffRoleIds.join(', '));
    setFormTemplate(category.nameTemplate || 'ticket-{number}');
    setFormMaxOpen(String(category.maxOpenPerUser ?? 1));
    setFormWelcome(category.welcomeMessage || '');
    setFormAutoClose(category.autoCloseHours ? String(category.autoCloseHours) : '');
    setIsEditing(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const roles = formRoles
      .split(',')
      .map((r) => r.trim())
      .filter(Boolean);

    const payload: CategoryInput = {
      name: formName.trim(),
      mode: formMode,
      parentChannelId: formParentId.trim(),
      staffRoleIds: roles,
      nameTemplate: formTemplate.trim() || 'ticket-{number}',
      maxOpenPerUser: parseInt(formMaxOpen, 10) || 1,
    };

    if (formEmoji.trim()) {
      payload.emoji = formEmoji.trim();
    }
    if (formWelcome.trim()) {
      payload.welcomeMessage = formWelcome.trim();
    }
    if (formAutoClose.trim()) {
      const hours = parseInt(formAutoClose, 10);
      if (!Number.isNaN(hours)) {
        payload.autoCloseHours = hours;
      }
    }

    try {
      if (editingId) {
        const updated = await api.updateCategory(guildId, editingId, payload);
        setCategories((prev) => prev.map((c) => (c.id === editingId ? updated : c)));
      } else {
        const created = await api.createCategory(guildId, payload);
        setCategories((prev) => [...prev, created]);
      }
      resetForm();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    }
  };

  const handleDelete = async (categoryId: string) => {
    if (!window.confirm(t('confirmDelete', locale))) return;

    try {
      await api.deleteCategory(guildId, categoryId);
      setCategories((prev) => prev.filter((c) => c.id !== categoryId));
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    }
  };

  return (
    <div>
      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
          <div>
            <h2 className="card-title">{t('categoriesTitle', locale)}</h2>
            <p className="card-desc" style={{ marginBottom: 0 }}>{t('categoriesDesc', locale)}</p>
          </div>
          {!isEditing && (
            <button type="button" className="btn btn-primary" onClick={handleOpenCreate}>
              {t('createCategory', locale)}
            </button>
          )}
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        {isEditing ? (
          <form onSubmit={handleSubmit}>
            <h3 style={{ marginBottom: '1rem' }}>
              {editingId ? t('editCategory', locale) : t('createCategory', locale)}
            </h3>

            <div className="form-group">
              <label htmlFor="cat-name" className="form-label">{t('categoryName', locale)}</label>
              <input
                id="cat-name"
                type="text"
                className="form-control"
                value={formName}
                onChange={(e) => setFormName(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="cat-emoji" className="form-label">{t('emoji', locale)}</label>
              <input
                id="cat-emoji"
                type="text"
                className="form-control"
                value={formEmoji}
                onChange={(e) => setFormEmoji(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label htmlFor="cat-mode" className="form-label">{t('mode', locale)}</label>
              <select
                id="cat-mode"
                className="form-control"
                value={formMode}
                onChange={(e) => setFormMode(e.target.value as 'thread' | 'channel')}
              >
                <option value="thread">{t('modeThread', locale)}</option>
                <option value="channel">{t('modeChannel', locale)}</option>
              </select>
            </div>

            <div className="form-group">
              <label htmlFor="cat-parent" className="form-label">{t('parentChannelId', locale)}</label>
              <input
                id="cat-parent"
                type="text"
                className="form-control"
                value={formParentId}
                onChange={(e) => setFormParentId(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="cat-roles" className="form-label">{t('staffRoleIds', locale)}</label>
              <input
                id="cat-roles"
                type="text"
                className="form-control"
                value={formRoles}
                onChange={(e) => setFormRoles(e.target.value)}
                placeholder="123456789012345678, 234567890123456789"
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="cat-template" className="form-label">{t('nameTemplate', locale)}</label>
              <input
                id="cat-template"
                type="text"
                className="form-control"
                value={formTemplate}
                onChange={(e) => setFormTemplate(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label htmlFor="cat-max" className="form-label">{t('maxOpenTickets', locale)}</label>
              <input
                id="cat-max"
                type="number"
                min="1"
                max="10"
                className="form-control"
                value={formMaxOpen}
                onChange={(e) => setFormMaxOpen(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label htmlFor="cat-welcome" className="form-label">{t('welcomeMessage', locale)}</label>
              <textarea
                id="cat-welcome"
                rows={3}
                className="form-control"
                value={formWelcome}
                onChange={(e) => setFormWelcome(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label htmlFor="cat-autoclose" className="form-label">{t('autoCloseHours', locale)}</label>
              <input
                id="cat-autoclose"
                type="number"
                min="1"
                max="720"
                className="form-control"
                value={formAutoClose}
                onChange={(e) => setFormAutoClose(e.target.value)}
              />
            </div>

            <div className="form-actions">
              <button type="submit" className="btn btn-primary">
                {t('saveCategory', locale)}
              </button>
              <button type="button" className="btn btn-secondary" onClick={resetForm}>
                {t('cancel', locale)}
              </button>
            </div>
          </form>
        ) : loading ? (
          <div className="empty-state">{t('loading', locale)}</div>
        ) : categories.length === 0 ? (
          <div className="empty-state">{t('noCategories', locale)}</div>
        ) : (
          <table className="table">
            <thead>
              <tr>
                <th>{t('emoji', locale)}</th>
                <th>{t('categoryName', locale)}</th>
                <th>{t('mode', locale)}</th>
                <th>{t('parentChannelId', locale)}</th>
                <th>{t('maxOpenTickets', locale)}</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {categories.map((cat) => (
                <tr key={cat.id}>
                  <td>{cat.emoji || '—'}</td>
                  <td style={{ fontWeight: 600 }}>{cat.name}</td>
                  <td>
                    <span className={`badge ${cat.mode === 'thread' ? 'badge-thread' : 'badge-channel'}`}>
                      {cat.mode}
                    </span>
                  </td>
                  <td style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>{cat.parentChannelId}</td>
                  <td>{cat.maxOpenPerUser ?? 1}</td>
                  <td style={{ textAlign: 'right' }}>
                    <button
                      type="button"
                      className="btn btn-secondary btn-sm"
                      style={{ marginRight: '0.5rem' }}
                      onClick={() => handleOpenEdit(cat)}
                    >
                      {t('edit', locale)}
                    </button>
                    <button
                      type="button"
                      className="btn btn-danger btn-sm"
                      onClick={() => handleDelete(cat.id)}
                    >
                      {t('deleteCategory', locale)}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};
