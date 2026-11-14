export interface User {
  id: string;
  username: string;
  avatar: string | null;
}

export interface Guild {
  id: string;
  name: string;
  icon: string | null;
  canManage: boolean;
}

export interface Me {
  user: User;
  guilds: Guild[];
  csrfToken: string;
}

export interface GuildSettings {
  locale: 'th' | 'en';
  retentionDays: number;
  logChannelId: string | null;
  ratingDm: boolean;
  privacyPolicyUrl: string | null;
}

export interface FormField {
  id: string;
  label: string;
  style: 'short' | 'paragraph';
  required: boolean;
  placeholder?: string;
  maxLength?: number;
}

export interface CategoryInput {
  name: string;
  emoji?: string | null;
  staffRoleIds: string[];
  mode: 'thread' | 'channel';
  parentChannelId: string;
  nameTemplate?: string;
  welcomeMessage?: string;
  form?: FormField[];
  autoCloseHours?: number | null;
  maxOpenPerUser?: number;
  gameServerId?: string | null;
}

export interface Category extends CategoryInput {
  id: string;
  createdAt: string;
}

export interface ApiErrorPayload {
  code: string;
  message: string;
  details?: Record<string, unknown>;
}
