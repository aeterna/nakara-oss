import type { TicketsDb } from '../index.js';
import { guilds, guildSettings } from '../schema.js';
import { inGuild } from '../index.js';
import { TicketError } from './errors.js';

export async function ensureGuild(db: TicketsDb, guildId: string, name: string) {
  return await db.transaction(async (tx) => {
    const [guild] = await tx
      .insert(guilds)
      .values({ guild_id: guildId, name })
      .onConflictDoUpdate({
        target: guilds.guild_id,
        set: { name },
      })
      .returning();

    await tx
      .insert(guildSettings)
      .values({ guild_id: guildId })
      .onConflictDoNothing();

    return guild;
  });
}

export async function getSettings(db: TicketsDb, guildId: string) {
  const rows = await db
    .select()
    .from(guildSettings)
    .where(inGuild(guildSettings, guildId))
    .limit(1);

  if (rows.length === 0) {
    throw new TicketError('not_found', `Settings not found for guild ${guildId}`);
  }
  return rows[0];
}

export interface UpdateSettingsPatch {
  locale?: string;
  retention_days?: number;
  retentionDays?: number;
  log_channel_id?: string | null;
  logChannelId?: string | null;
  rating_dm?: boolean;
  ratingDm?: boolean;
  privacy_policy_url?: string | null;
  privacyPolicyUrl?: string | null;
}

export async function updateSettings(
  db: TicketsDb,
  guildId: string,
  patch: UpdateSettingsPatch,
) {
  const updateData: Partial<typeof guildSettings.$inferInsert> = {};

  if (patch.locale !== undefined) updateData.locale = patch.locale;
  if (patch.retention_days !== undefined) updateData.retention_days = patch.retention_days;
  else if (patch.retentionDays !== undefined) updateData.retention_days = patch.retentionDays;

  if (patch.log_channel_id !== undefined) updateData.log_channel_id = patch.log_channel_id;
  else if (patch.logChannelId !== undefined) updateData.log_channel_id = patch.logChannelId;

  if (patch.rating_dm !== undefined) updateData.rating_dm = patch.rating_dm;
  else if (patch.ratingDm !== undefined) updateData.rating_dm = patch.ratingDm;

  if (patch.privacy_policy_url !== undefined) updateData.privacy_policy_url = patch.privacy_policy_url;
  else if (patch.privacyPolicyUrl !== undefined) updateData.privacy_policy_url = patch.privacyPolicyUrl;

  if (Object.keys(updateData).length === 0) {
    return await getSettings(db, guildId);
  }

  const rows = await db
    .update(guildSettings)
    .set(updateData)
    .where(inGuild(guildSettings, guildId))
    .returning();

  if (rows.length === 0) {
    throw new TicketError('not_found', `Settings not found for guild ${guildId}`);
  }
  return rows[0];
}
