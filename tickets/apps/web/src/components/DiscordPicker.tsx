import React, { useState, useEffect } from 'react';
import { getGuildChannels, getGuildRoles, type DiscordChannel, type DiscordRole } from '../api/discord.js';
import { t, type Locale } from '../i18n.js';

export interface ChannelSelectProps {
  id?: string;
  'data-testid'?: string;
  guildId?: string;
  channels?: DiscordChannel[];
  allowedTypes?: number[];
  value: string;
  onChange: (value: string) => void;
  error?: string | null;
  required?: boolean;
  placeholder?: string;
  locale?: Locale;
}

export const ChannelSelect: React.FC<ChannelSelectProps> = ({
  id, 'data-testid': testId, guildId, channels, allowedTypes, value, onChange, error, required, placeholder, locale = 'th',
}) => {
  const [internalChannels, setInternalChannels] = useState<DiscordChannel[]>([]);
  const [internalError, setInternalError] = useState<string | null>(null);

  useEffect(() => {
    if (channels === undefined && guildId) {
      getGuildChannels(guildId).then(setInternalChannels).catch((e) => setInternalError(e?.message || t('discordLookupFailed', locale)));
    }
  }, [guildId, channels, locale]);

  const channelList = channels ?? internalChannels;
  const displayError = error ?? internalError;

  if (displayError) {
    return (
      <div>
        <input id={id} data-testid={testId} type="text" className="form-control" value={value} onChange={(e) => onChange(e.target.value)} required={required} />
        <div style={{ color: '#ed4245', fontSize: '0.8rem', marginTop: '0.25rem' }}>{displayError}</div>
      </div>
    );
  }

  const categories = channelList.filter((c) => c.type === 4);
  const allowed = allowedTypes ? channelList.filter((c) => allowedTypes.includes(c.type)) : channelList;
  const isUnknown = value && !allowed.some((c) => c.id === value);

  return (
    <select id={id} data-testid={testId} className="form-control" value={value} onChange={(e) => onChange(e.target.value)} required={required}>
      <option value="">{placeholder || t('selectChannel', locale)}</option>
      {isUnknown && <option value={value}>{value}</option>}
      {allowedTypes?.length === 1 && allowedTypes[0] === 4
        ? allowed.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)
        : (
          <>
            {categories.map((cat) => {
              const children = allowed.filter((c) => c.parentId === cat.id);
              if (children.length === 0) return null;
              return (
                <optgroup key={cat.id} label={cat.name}>
                  {children.map((c) => <option key={c.id} value={c.id}># {c.name}</option>)}
                </optgroup>
              );
            })}
            {allowed.filter((c) => !c.parentId || !categories.some((cat) => cat.id === c.parentId)).map((c) => (
              <option key={c.id} value={c.id}>{c.type === 4 ? c.name : `# ${c.name}`}</option>
            ))}
          </>
        )}
    </select>
  );
};

export interface RoleMultiSelectProps {
  id?: string;
  'data-testid'?: string;
  guildId?: string;
  roles?: DiscordRole[];
  value: string[];
  onChange: (value: string[]) => void;
  error?: string | null;
  locale?: Locale;
}

export const RoleMultiSelect: React.FC<RoleMultiSelectProps> = ({
  id, 'data-testid': testId, guildId, roles, value, onChange, error, locale = 'th',
}) => {
  const [internalRoles, setInternalRoles] = useState<DiscordRole[]>([]);
  const [internalError, setInternalError] = useState<string | null>(null);

  useEffect(() => {
    if (roles === undefined && guildId) {
      getGuildRoles(guildId).then(setInternalRoles).catch((e) => setInternalError(e?.message || t('discordLookupFailed', locale)));
    }
  }, [guildId, roles, locale]);

  const roleList = roles ?? internalRoles;
  const displayError = error ?? internalError;

  if (displayError) {
    return (
      <div>
        <input
          id={id} data-testid={testId} type="text" className="form-control" value={value.join(', ')}
          onChange={(e) => onChange(e.target.value.split(',').map((s) => s.trim()).filter(Boolean))}
        />
        <div style={{ color: '#ed4245', fontSize: '0.8rem', marginTop: '0.25rem' }}>{displayError}</div>
      </div>
    );
  }

  const unknownIds = value.filter((vid) => !roleList.some((r) => r.id === vid));

  return (
    <div id={id} style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', maxHeight: '180px', overflowY: 'auto' }}>
      {roleList.map((r) => {
        const checked = value.includes(r.id);
        const colorHex = r.color ? `#${r.color.toString(16).padStart(6, '0')}` : '#99aab5';
        return (
          <label key={r.id} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', cursor: 'pointer', fontSize: '0.9rem' }}>
            <input type="checkbox" checked={checked} onChange={() => onChange(checked ? value.filter((v) => v !== r.id) : [...value, r.id])} />
            <span style={{ width: 10, height: 10, borderRadius: '50%', backgroundColor: colorHex, display: 'inline-block' }} />
            <span>{r.name}</span>
          </label>
        );
      })}
      {unknownIds.map((uid) => (
        <label key={uid} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', cursor: 'pointer', fontSize: '0.9rem' }}>
          <input type="checkbox" checked onChange={() => onChange(value.filter((v) => v !== uid))} />
          <span>{uid}</span>
        </label>
      ))}
    </div>
  );
};
