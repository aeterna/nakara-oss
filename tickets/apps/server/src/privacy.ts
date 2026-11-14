import type { TicketsDb } from '@nakara-tickets/db';
import {
  deleteUserData as deleteUserDataDb,
  exportGuild as exportGuildDb,
  purgeExpired as purgeExpiredDb,
  type DeleteCounts,
  type PurgeCounts,
  type StorageService,
  type GuildExport,
} from '@nakara-tickets/db';

export type { DeleteCounts, PurgeCounts, StorageService, GuildExport };

export async function deleteUserData(
  db: TicketsDb,
  storageOrGuildId?: StorageService | string | null,
  guildIdOrUserId?: string | null,
  userIdOrStorage?: string | StorageService | null,
  maybeStorage?: StorageService | null,
): Promise<DeleteCounts> {
  return await deleteUserDataDb(
    db,
    storageOrGuildId,
    guildIdOrUserId,
    userIdOrStorage,
    maybeStorage,
  );
}

export async function exportGuild(
  db: TicketsDb,
  dataKey: Buffer,
  guildId: string,
): Promise<GuildExport> {
  return await exportGuildDb(db, dataKey, guildId);
}

export async function purgeExpired(
  db: TicketsDb,
  now: Date = new Date(),
  storage?: StorageService | null,
): Promise<PurgeCounts> {
  return await purgeExpiredDb(db, now, storage);
}
