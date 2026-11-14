import React, { useState, useEffect } from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';
import { getTags, createTag, updateTag, deleteTag, type Tag } from '../api/tags.js';

export interface TagsProps {
  guildId: string;
  locale: Locale;
}

export const Tags: React.FC<TagsProps> = ({ guildId, locale }) => {
  const [tags, setTags] = useState<Tag[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const [isEditing, setIsEditing] = useState<boolean>(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [formName, setFormName] = useState<string>('');
  const [formContent, setFormContent] = useState<string>('');

  const loadTags = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await getTags(guildId);
      setTags(data);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadTags();
  }, [guildId]);

  const resetForm = () => {
    setFormName('');
    setFormContent('');
    setEditingId(null);
    setIsEditing(false);
  };

  const handleOpenCreate = () => {
    resetForm();
    setIsEditing(true);
  };

  const handleOpenEdit = (tag: Tag) => {
    setEditingId(tag.id);
    setFormName(tag.name);
    setFormContent(tag.content ?? tag.body ?? '');
    setIsEditing(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const name = formName.trim().toLowerCase();
    const content = formContent.trim();

    if (!name || !content) {
      return;
    }

    try {
      if (editingId) {
        await updateTag(guildId, editingId, { name, content });
      } else {
        await createTag(guildId, { name, content });
      }
      resetForm();
      await loadTags();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    }
  };

  const handleDelete = async (tagId: string) => {
    if (typeof window !== 'undefined' && window.confirm && !window.confirm(t('confirmDeleteTag', locale))) {
      return;
    }

    try {
      setError(null);
      await deleteTag(guildId, tagId);
      await loadTags();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : t('error', locale));
    }
  };

  return (
    <div className="card">
      <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2 className="card-title">{t('tagsTitle', locale)}</h2>
          <p className="card-subtitle">{t('tagsDesc', locale)}</p>
        </div>
        {!isEditing && (
          <button className="btn btn-primary" onClick={handleOpenCreate}>
            {t('createTag', locale)}
          </button>
        )}
      </div>

      {error && (
        <div className="alert alert-danger" style={{ margin: '1rem 0' }}>
          {error}
        </div>
      )}

      {isEditing && (
        <form onSubmit={handleSubmit} style={{ margin: '1rem 0', padding: '1rem', border: '1px solid #ccc', borderRadius: '4px' }}>
          <h3>{editingId ? t('editTag', locale) : t('createTag', locale)}</h3>

          <div className="form-group" style={{ marginBottom: '1rem' }}>
            <label htmlFor="tag-name" style={{ display: 'block', marginBottom: '0.25rem' }}>
              {t('tagName', locale)}
            </label>
            <input
              id="tag-name"
              type="text"
              className="form-control"
              value={formName}
              onChange={(e) => setFormName(e.target.value)}
              placeholder="e.g. faq-rules"
              pattern="^[a-z0-9-]{1,32}$"
              required
              style={{ width: '100%', padding: '0.5rem' }}
            />
          </div>

          <div className="form-group" style={{ marginBottom: '1rem' }}>
            <label htmlFor="tag-content" style={{ display: 'block', marginBottom: '0.25rem' }}>
              {t('tagContent', locale)}
            </label>
            <textarea
              id="tag-content"
              className="form-control"
              rows={4}
              value={formContent}
              onChange={(e) => setFormContent(e.target.value)}
              placeholder="Tag response text..."
              maxLength={2000}
              required
              style={{ width: '100%', padding: '0.5rem' }}
            />
            <small style={{ color: '#666', display: 'block', marginTop: '0.25rem' }}>
              {t('variableHelp', locale)}
            </small>
          </div>

          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <button type="submit" className="btn btn-primary">
              {t('saveTag', locale)}
            </button>
            <button type="button" className="btn btn-secondary" onClick={resetForm}>
              {t('cancel', locale)}
            </button>
          </div>
        </form>
      )}

      {loading ? (
        <p>{t('loading', locale)}</p>
      ) : tags.length === 0 ? (
        <p>{t('noTags', locale)}</p>
      ) : (
        <table className="table" style={{ width: '100%', marginTop: '1rem', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ddd', padding: '0.5rem' }}>{t('tagName', locale)}</th>
              <th style={{ textAlign: 'left', borderBottom: '1px solid #ddd', padding: '0.5rem' }}>{t('tagContent', locale)}</th>
              <th style={{ textAlign: 'right', borderBottom: '1px solid #ddd', padding: '0.5rem' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {tags.map((tag) => (
              <tr key={tag.id}>
                <td style={{ borderBottom: '1px solid #eee', padding: '0.5rem' }}>
                  <strong>{tag.name}</strong>
                </td>
                <td style={{ borderBottom: '1px solid #eee', padding: '0.5rem', whiteSpace: 'pre-wrap' }}>
                  {tag.content ?? tag.body}
                </td>
                <td style={{ borderBottom: '1px solid #eee', padding: '0.5rem', textAlign: 'right' }}>
                  <button
                    className="btn btn-sm btn-secondary"
                    onClick={() => handleOpenEdit(tag)}
                    style={{ marginRight: '0.5rem' }}
                  >
                    {t('editTag', locale)}
                  </button>
                  <button
                    className="btn btn-sm btn-danger"
                    onClick={() => handleDelete(tag.id)}
                  >
                    {t('deleteTag', locale)}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
};
