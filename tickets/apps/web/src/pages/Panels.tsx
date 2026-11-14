import React, { useState, useEffect } from 'react';
import type { Locale } from '../i18n.js';
import { t } from '../i18n.js';
import { api } from '../api.js';
import { panelsApi, type Panel, type PanelInput, type PanelButton } from '../api/panels.js';
import type { Category } from '../types.js';
import './Panels.css';

export interface PanelsProps {
  guildId: string;
  locale: Locale;
}

function intToHexColor(colorInt?: number | null): string {
  if (colorInt === undefined || colorInt === null) {
    return '#5865f2';
  }
  return '#' + colorInt.toString(16).padStart(6, '0');
}

function hexToIntColor(hex: string): number {
  const cleaned = hex.replace('#', '');
  const parsed = parseInt(cleaned, 16);
  return isNaN(parsed) ? 0x5865f2 : parsed;
}

export const Panels: React.FC<PanelsProps> = ({ guildId, locale }) => {
  const [panels, setPanels] = useState<Panel[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [saving, setSaving] = useState<boolean>(false);
  const [sending, setSending] = useState<boolean>(false);
  const [statusMessage, setStatusMessage] = useState<{ text: string; type: 'success' | 'error' } | null>(null);

  const [selectedPanelId, setSelectedPanelId] = useState<string | null>(null);

  // Form Fields
  const [channelId, setChannelId] = useState<string>('');
  const [title, setTitle] = useState<string>('Open a Support Ticket');
  const [description, setDescription] = useState<string>('Select an option below to create a ticket.');
  const [colorHex, setColorHex] = useState<string>('#5865f2');
  const [footer, setFooter] = useState<string>('');
  const [imageUrl, setImageUrl] = useState<string>('');
  const [kind, setKind] = useState<'buttons' | 'select'>('buttons');
  const [buttons, setButtons] = useState<PanelButton[]>([
    { categoryId: '', label: 'General Support', emoji: '🎫', style: 'primary' },
  ]);

  const loadData = async () => {
    try {
      setLoading(true);
      const [panelsData, catsData] = await Promise.all([
        panelsApi.getPanels(guildId),
        api.getCategories(guildId),
      ]);
      setPanels(panelsData);
      setCategories(catsData);

      // Default the first button's category if empty and categories exist
      if (catsData.length > 0) {
        setButtons((prev) =>
          prev.map((b) => (b.categoryId ? b : { ...b, categoryId: catsData[0].id }))
        );
      }
    } catch (err: unknown) {
      setStatusMessage({
        text: err instanceof Error ? err.message : t('error', locale),
        type: 'error',
      });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, [guildId]);

  const resetForm = () => {
    setSelectedPanelId(null);
    setChannelId('');
    setTitle('Open a Support Ticket');
    setDescription('Select an option below to create a ticket.');
    setColorHex('#5865f2');
    setFooter('');
    setImageUrl('');
    setKind('buttons');
    setButtons([
      {
        categoryId: categories.length > 0 ? categories[0].id : '',
        label: 'General Support',
        emoji: '🎫',
        style: 'primary',
      },
    ]);
    setStatusMessage(null);
  };

  const selectPanel = (p: Panel) => {
    setSelectedPanelId(p.id);
    setChannelId(p.channelId);
    setTitle(p.embed.title || '');
    setDescription(p.embed.description || '');
    setColorHex(intToHexColor(p.embed.color));
    setFooter(p.embed.footer || '');
    setImageUrl(p.embed.imageUrl || '');
    setKind(p.kind || 'buttons');
    setButtons(
      p.buttons && p.buttons.length > 0
        ? p.buttons
        : [
            {
              categoryId: categories.length > 0 ? categories[0].id : '',
              label: 'General Support',
              emoji: '🎫',
              style: 'primary',
            },
          ]
    );
    setStatusMessage(null);
  };

  const handleAddButton = () => {
    if (buttons.length >= 25) return;
    const defaultCatId = categories.length > 0 ? categories[0].id : '';
    setButtons((prev) => [
      ...prev,
      {
        categoryId: defaultCatId,
        label: `Button ${prev.length + 1}`,
        emoji: '',
        style: 'primary',
      },
    ]);
  };

  const handleRemoveButton = (index: number) => {
    if (buttons.length <= 1) return;
    setButtons((prev) => prev.filter((_, i) => i !== index));
  };

  const handleMoveButton = (index: number, delta: number) => {
    const targetIdx = index + delta;
    if (targetIdx < 0 || targetIdx >= buttons.length) return;
    setButtons((prev) => {
      const copy = [...prev];
      const item = copy[index];
      copy[index] = copy[targetIdx];
      copy[targetIdx] = item;
      return copy;
    });
  };

  const handleButtonChange = (index: number, field: keyof PanelButton, value: any) => {
    setButtons((prev) => {
      const copy = [...prev];
      copy[index] = { ...copy[index], [field]: value };
      return copy;
    });
  };

  const totalChars = (title?.length || 0) + (description?.length || 0) + (footer?.length || 0);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!channelId.trim()) {
      setStatusMessage({ text: 'Channel ID is required', type: 'error' });
      return;
    }
    if (!title.trim()) {
      setStatusMessage({ text: 'Title is required', type: 'error' });
      return;
    }
    if (totalChars > 6000) {
      setStatusMessage({ text: 'Total embed characters cannot exceed 6000', type: 'error' });
      return;
    }
    if (buttons.length === 0) {
      setStatusMessage({ text: t('atLeastOneButton', locale), type: 'error' });
      return;
    }

    const payload: PanelInput = {
      channelId: channelId.trim(),
      embed: {
        title: title.trim(),
        description: description.trim() || null,
        color: hexToIntColor(colorHex),
        footer: footer.trim() || null,
        imageUrl: imageUrl.trim() || null,
      },
      kind,
      buttons: buttons.map((b) => ({
        categoryId: b.categoryId || (categories[0]?.id ?? ''),
        label: b.label.trim() || 'Ticket',
        emoji: b.emoji?.trim() || null,
        style: b.style || 'primary',
      })),
    };

    try {
      setSaving(true);
      setStatusMessage(null);

      if (selectedPanelId) {
        const updated = await panelsApi.updatePanel(guildId, selectedPanelId, payload);
        setPanels((prev) => prev.map((p) => (p.id === updated.id ? updated : p)));
        setSelectedPanelId(updated.id);
        setStatusMessage({ text: t('savedSuccess', locale), type: 'success' });
      } else {
        const created = await panelsApi.createPanel(guildId, payload);
        setPanels((prev) => [...prev, created]);
        setSelectedPanelId(created.id);
        setStatusMessage({ text: t('savedSuccess', locale), type: 'success' });
      }
    } catch (err: unknown) {
      setStatusMessage({
        text: err instanceof Error ? err.message : t('error', locale),
        type: 'error',
      });
    } finally {
      setSaving(false);
    }
  };

  const handleSend = async () => {
    if (!selectedPanelId) return;
    try {
      setSending(true);
      setStatusMessage(null);
      const updated = await panelsApi.sendPanel(guildId, selectedPanelId);
      setPanels((prev) => prev.map((p) => (p.id === updated.id ? updated : p)));
      setStatusMessage({ text: t('sentSuccess', locale), type: 'success' });
    } catch (err: unknown) {
      setStatusMessage({
        text: err instanceof Error ? err.message : t('error', locale),
        type: 'error',
      });
    } finally {
      setSending(false);
    }
  };

  const handleDelete = async () => {
    if (!selectedPanelId) return;
    if (!window.confirm(t('confirmDelete', locale))) {
      return;
    }
    try {
      setLoading(true);
      setStatusMessage(null);
      await panelsApi.deletePanel(guildId, selectedPanelId);
      setPanels((prev) => prev.filter((p) => p.id !== selectedPanelId));
      resetForm();
      setStatusMessage({ text: t('deletedSuccess', locale), type: 'success' });
    } catch (err: unknown) {
      setStatusMessage({
        text: err instanceof Error ? err.message : t('error', locale),
        type: 'error',
      });
    } finally {
      setLoading(false);
    }
  };

  // Preview button chunking: 5 per row
  const buttonRows: PanelButton[][] = [];
  for (let i = 0; i < buttons.length; i += 5) {
    buttonRows.push(buttons.slice(i, i + 5));
  }

  const selectedPanel = panels.find((p) => p.id === selectedPanelId);

  return (
    <div className="panels-page">
      <div className="panels-header">
        <div>
          <h2>{t('panelsTitle', locale)}</h2>
          <p>{t('panelsDesc', locale)}</p>
        </div>
        <button
          type="button"
          className="btn-action btn-action-primary"
          onClick={resetForm}
        >
          {t('createPanel', locale)}
        </button>
      </div>

      {statusMessage && (
        <div
          className={`card ${
            statusMessage.type === 'success' ? 'badge-success' : 'badge-danger'
          }`}
          style={{ padding: '0.75rem 1rem' }}
        >
          {statusMessage.text}
        </div>
      )}

      <div className="panels-layout">
        {/* Left Column: Panel List */}
        <aside className="panels-sidebar">
          <div className="panels-sidebar-title">
            <span>{t('panelList', locale)}</span>
            <span style={{ fontSize: '0.8rem', color: '#949ba4' }}>{panels.length}</span>
          </div>

          {panels.length === 0 && !loading && (
            <p style={{ color: '#949ba4', fontSize: '0.85rem' }}>{t('noPanels', locale)}</p>
          )}

          <div className="panels-list">
            {panels.map((p) => (
              <button
                key={p.id}
                type="button"
                className={`panel-list-item ${selectedPanelId === p.id ? 'active' : ''}`}
                onClick={() => selectPanel(p)}
              >
                <div className="panel-item-title">{p.embed.title || 'Untitled Panel'}</div>
                <div className="panel-item-channel">Channel: {p.channelId}</div>
                {p.messageId && (
                  <span className="panel-item-status">✓ {t('sentToDiscordStatus', locale)}</span>
                )}
              </button>
            ))}
          </div>
        </aside>

        {/* Center Column: Editor Form */}
        <div className="panels-editor">
          <h3 className="editor-section-title">
            {selectedPanelId ? t('editPanel', locale) : t('createPanel', locale)}
          </h3>

          <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            <div className="form-group">
              <label htmlFor="panel-channel-id">{t('channelId', locale)}</label>
              <input
                id="panel-channel-id"
                data-testid="panel-channel-input"
                type="text"
                className="form-control"
                placeholder={t('channelIdPlaceholder', locale)}
                value={channelId}
                onChange={(e) => setChannelId(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <div className="input-label-row">
                <label htmlFor="panel-title">{t('embedTitle', locale)}</label>
                <span
                  data-testid="title-counter"
                  className={`char-counter ${title.length > 256 ? 'limit-exceeded' : ''}`}
                >
                  {title.length} / 256
                </span>
              </div>
              <input
                id="panel-title"
                data-testid="panel-title-input"
                type="text"
                className="form-control"
                placeholder={t('embedTitlePlaceholder', locale)}
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                maxLength={256}
                required
              />
            </div>

            <div className="form-group">
              <div className="input-label-row">
                <label htmlFor="panel-desc">{t('embedDescription', locale)}</label>
                <span
                  data-testid="description-counter"
                  className={`char-counter ${description.length > 4096 ? 'limit-exceeded' : ''}`}
                >
                  {description.length} / 4096
                </span>
              </div>
              <textarea
                id="panel-desc"
                data-testid="panel-description-input"
                className="form-control"
                placeholder={t('embedDescriptionPlaceholder', locale)}
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                maxLength={4096}
                rows={3}
              />
            </div>

            <div className="form-group">
              <label>{t('embedColor', locale)}</label>
              <div className="color-input-wrapper">
                <input
                  type="color"
                  className="color-picker"
                  value={colorHex}
                  onChange={(e) => setColorHex(e.target.value)}
                />
                <input
                  type="text"
                  className="form-control"
                  style={{ width: '120px' }}
                  value={colorHex}
                  onChange={(e) => setColorHex(e.target.value)}
                  maxLength={7}
                />
              </div>
            </div>

            <div className="form-group">
              <div className="input-label-row">
                <label htmlFor="panel-footer">{t('embedFooter', locale)}</label>
                <span
                  data-testid="footer-counter"
                  className={`char-counter ${footer.length > 2048 ? 'limit-exceeded' : ''}`}
                >
                  {footer.length} / 2048
                </span>
              </div>
              <input
                id="panel-footer"
                data-testid="panel-footer-input"
                type="text"
                className="form-control"
                placeholder={t('embedFooterPlaceholder', locale)}
                value={footer}
                onChange={(e) => setFooter(e.target.value)}
                maxLength={2048}
              />
            </div>

            <div className="form-group">
              <label htmlFor="panel-image">{t('embedImageUrl', locale)}</label>
              <input
                id="panel-image"
                data-testid="panel-image-input"
                type="url"
                className="form-control"
                placeholder={t('embedImageUrlPlaceholder', locale)}
                value={imageUrl}
                onChange={(e) => setImageUrl(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label htmlFor="panel-kind">{t('panelKind', locale)}</label>
              <select
                id="panel-kind"
                className="form-control"
                value={kind}
                onChange={(e) => setKind(e.target.value as 'buttons' | 'select')}
              >
                <option value="buttons">{t('kindButtons', locale)}</option>
                <option value="select">{t('kindSelect', locale)}</option>
              </select>
            </div>

            {/* Total Chars Notice */}
            <div
              data-testid="total-counter"
              className={`char-counter ${totalChars > 6000 ? 'limit-exceeded' : ''}`}
              style={{ fontSize: '0.8rem', textAlign: 'right' }}
            >
              {t('totalEmbedChars', locale)}: {totalChars} / 6000
            </div>

            {/* Buttons Editor Section */}
            <div className="buttons-editor-container">
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontWeight: 600, fontSize: '0.95rem' }}>{t('buttons', locale)}</span>
                <button
                  type="button"
                  data-testid="add-button-btn"
                  className="btn-icon"
                  style={{ padding: '0.3rem 0.6rem', fontSize: '0.8rem' }}
                  onClick={handleAddButton}
                  disabled={buttons.length >= 25}
                >
                  {t('addButton', locale)} ({buttons.length}/25)
                </button>
              </div>

              {buttons.map((btn, idx) => (
                <div key={idx} className="panel-button-item" data-testid="panel-button-item">
                  <div className="button-item-header">
                    <span>Button #{idx + 1}</span>
                    <div className="button-item-actions">
                      <button
                        type="button"
                        className="btn-icon"
                        onClick={() => handleMoveButton(idx, -1)}
                        disabled={idx === 0}
                        title={t('moveUp', locale)}
                      >
                        ▲
                      </button>
                      <button
                        type="button"
                        className="btn-icon"
                        onClick={() => handleMoveButton(idx, 1)}
                        disabled={idx === buttons.length - 1}
                        title={t('moveDown', locale)}
                      >
                        ▼
                      </button>
                      <button
                        type="button"
                        data-testid="remove-button-btn"
                        className="btn-icon"
                        onClick={() => handleRemoveButton(idx)}
                        disabled={buttons.length <= 1}
                        style={{ color: '#da373c' }}
                        title={t('removeButton', locale)}
                      >
                        ✕
                      </button>
                    </div>
                  </div>

                  <div className="button-item-grid">
                    <div className="button-item-grid-full">
                      <label style={{ fontSize: '0.75rem', color: '#949ba4' }}>{t('category', locale)}</label>
                      <select
                        className="form-control"
                        value={btn.categoryId}
                        onChange={(e) => handleButtonChange(idx, 'categoryId', e.target.value)}
                        required
                      >
                        {categories.map((c) => (
                          <option key={c.id} value={c.id}>
                            {c.emoji ? `${c.emoji} ` : ''}
                            {c.name}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div>
                      <label style={{ fontSize: '0.75rem', color: '#949ba4' }}>{t('buttonLabel', locale)}</label>
                      <input
                        type="text"
                        className="form-control"
                        value={btn.label}
                        onChange={(e) => handleButtonChange(idx, 'label', e.target.value)}
                        maxLength={80}
                        required
                      />
                    </div>

                    <div>
                      <label style={{ fontSize: '0.75rem', color: '#949ba4' }}>{t('buttonEmoji', locale)}</label>
                      <input
                        type="text"
                        className="form-control"
                        placeholder="🎫"
                        value={btn.emoji || ''}
                        onChange={(e) => handleButtonChange(idx, 'emoji', e.target.value)}
                        maxLength={64}
                      />
                    </div>

                    <div className="button-item-grid-full">
                      <label style={{ fontSize: '0.75rem', color: '#949ba4' }}>{t('buttonStyle', locale)}</label>
                      <select
                        className="form-control"
                        value={btn.style}
                        onChange={(e) =>
                          handleButtonChange(
                            idx,
                            'style',
                            e.target.value as 'primary' | 'secondary' | 'success' | 'danger'
                          )
                        }
                      >
                        <option value="primary">{t('stylePrimary', locale)}</option>
                        <option value="secondary">{t('styleSecondary', locale)}</option>
                        <option value="success">{t('styleSuccess', locale)}</option>
                        <option value="danger">{t('styleDanger', locale)}</option>
                      </select>
                    </div>
                  </div>
                </div>
              ))}
            </div>

            {/* Action Buttons Toolbar */}
            <div className="panels-toolbar">
              <button
                type="submit"
                className="btn-action btn-action-primary"
                disabled={saving || totalChars > 6000}
              >
                {saving ? t('saving', locale) : t('savePanel', locale)}
              </button>

              {selectedPanelId && (
                <>
                  <button
                    type="button"
                    className="btn-action btn-action-success"
                    onClick={handleSend}
                    disabled={sending || saving}
                  >
                    {sending
                      ? t('sending', locale)
                      : selectedPanel?.messageId
                      ? t('updateInDiscord', locale)
                      : t('sendToDiscord', locale)}
                  </button>

                  <button
                    type="button"
                    className="btn-action btn-action-danger"
                    onClick={handleDelete}
                    disabled={saving || sending}
                  >
                    {t('deletePanel', locale)}
                  </button>
                </>
              )}
            </div>
          </form>
        </div>

        {/* Right Column: Discord Live Preview */}
        <div className="panels-preview-container">
          <h3 className="editor-section-title">{t('livePreview', locale)}</h3>

          <div className="discord-preview-card">
            <div className="preview-bot-header">
              <div className="preview-bot-avatar">🤖</div>
              <span className="preview-bot-name">Nakara Bot</span>
              <span className="preview-bot-badge">APP</span>
            </div>

            {/* Embed container with colored left bar */}
            <div className="discord-embed" style={{ borderLeftColor: colorHex }}>
              {title && (
                <div className="preview-title" data-testid="preview-title">
                  {title}
                </div>
              )}

              {description && (
                <div className="preview-description" data-testid="preview-description">
                  {description}
                </div>
              )}

              {imageUrl && (
                <img
                  src={imageUrl}
                  alt="Embed Preview"
                  className="preview-image"
                  data-testid="preview-image"
                  onError={(e) => {
                    (e.target as HTMLElement).style.display = 'none';
                  }}
                />
              )}

              {footer && (
                <div className="preview-footer" data-testid="preview-footer">
                  {footer}
                </div>
              )}
            </div>

            {/* Interactive Component Preview */}
            <div className="preview-components" data-testid="preview-components">
              {kind === 'select' ? (
                <div className="preview-select-menu" data-testid="preview-select-menu">
                  <span className="preview-select-placeholder">
                    {t('selectCategoryPlaceholder', locale)}
                  </span>
                  <span>▼</span>
                </div>
              ) : (
                buttonRows.map((row, rIdx) => (
                  <div
                    key={rIdx}
                    className="preview-button-row"
                    data-testid="preview-button-row"
                  >
                    {row.map((btn, bIdx) => (
                      <button
                        key={bIdx}
                        type="button"
                        className={`preview-button preview-button-${btn.style || 'primary'}`}
                        disabled
                      >
                        {btn.emoji && (
                          <span className="preview-button-emoji">{btn.emoji}</span>
                        )}
                        <span className="preview-button-label">{btn.label || 'Ticket'}</span>
                      </button>
                    ))}
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
