import { and, eq, inArray, isNotNull, lt, asc } from 'drizzle-orm';
import type { TicketsDb } from '../index.js';
import {
  guilds,
  guildSettings,
  categories,
  panels,
  tickets,
  ticketMembers,
  messages,
  attachments,
  ratings,
  tags,
  blocks,
  gameServers,
  dataRequests,
  auditLog,
} from '../schema.js';
import { openBytes } from '@nakara-tickets/core';

export interface DeleteCounts {
  messages: number;
  attachments: number;
  ratings: number;
  tickets: number;
}

export interface PurgeCounts {
  tickets: number;
  messages: number;
  attachments: number;
}

export interface StorageService {
  delete(key: string): Promise<void> | void;
}

export interface GuildExport {
  guild: any;
  settings: any;
  categories: any[];
  panels: any[];
  tags: any[];
  blocks: any[];
  ratings: any[];
  tickets: any[];
  game_servers?: any[];
}

export async function deleteUserData(
  db: TicketsDb,
  storageOrGuildId?: StorageService | string | null,
  guildIdOrUserId?: string | null,
  userIdOrStorage?: string | StorageService | null,
  maybeStorage?: StorageService | null,
): Promise<DeleteCounts> {
  let storage: StorageService | null = null;
  let guildId: string | null = null;
  let userId = '';

  // Determine signature:
  // Option A: (db, guildId, userId, storage?)
  // Option B: (db, storage, guildId, userId)
  if (
    typeof storageOrGuildId === 'string' ||
    (storageOrGuildId === null && typeof guildIdOrUserId === 'string' && typeof userIdOrStorage !== 'string')
  ) {
    guildId = storageOrGuildId as string | null;
    userId = guildIdOrUserId as string;
    storage = (userIdOrStorage as StorageService) ?? null;
  } else {
    storage = (storageOrGuildId as StorageService) ?? null;
    guildId = (guildIdOrUserId as string | null) ?? null;
    userId = (userIdOrStorage as string) ?? '';
    if (maybeStorage) {
      storage = maybeStorage;
    }
  }

  if (!userId) {
    throw new Error('userId is required for deleteUserData');
  }

  return await db.transaction(async (tx) => {
    // 1. Find user messages
    const messageConditions = [eq(messages.author_id, userId)];
    if (guildId) {
      messageConditions.push(eq(messages.guild_id, guildId));
    }

    const userMessages = await tx
      .select({ id: messages.id, guild_id: messages.guild_id })
      .from(messages)
      .where(and(...messageConditions));

    const messageIds = userMessages.map((m) => m.id);

    // 2. Find and delete attachments of user's messages
    let userAttachments: Array<{ id: string; storage_key: string | null }> = [];
    let deletedAttachmentsCount = 0;

    if (messageIds.length > 0) {
      const attachmentConditions = [inArray(attachments.message_id, messageIds)];
      if (guildId) {
        attachmentConditions.push(eq(attachments.guild_id, guildId));
      }

      userAttachments = await tx
        .select({ id: attachments.id, storage_key: attachments.storage_key })
        .from(attachments)
        .where(and(...attachmentConditions));

      if (userAttachments.length > 0) {
        const attIds = userAttachments.map((a) => a.id);
        const deletedAtt = await tx
          .delete(attachments)
          .where(inArray(attachments.id, attIds))
          .returning();
        deletedAttachmentsCount = deletedAtt.length;
      }
    }

    // Call storage deletion if storage service provided
    if (storage && typeof storage.delete === 'function') {
      for (const att of userAttachments) {
        if (att.storage_key) {
          try {
            await storage.delete(att.storage_key);
          } catch {
            // Storage delete failure should not block database deletion
          }
        }
      }
    }

    // 3. Delete user's messages
    let deletedMessagesCount = 0;
    if (userMessages.length > 0) {
      const deletedMsg = await tx
        .delete(messages)
        .where(and(...messageConditions))
        .returning();
      deletedMessagesCount = deletedMsg.length;
    }

    // 4. Delete user's ratings
    const ratingConditions = [eq(ratings.user_id, userId)];
    if (guildId) {
      ratingConditions.push(eq(ratings.guild_id, guildId));
    }
    const deletedRatings = await tx
      .delete(ratings)
      .where(and(...ratingConditions))
      .returning();
    const deletedRatingsCount = deletedRatings.length;

    // 5. Replace opener_id / claimer_id on tickets with 'deleted'
    const openerConditions = [eq(tickets.opener_id, userId)];
    if (guildId) {
      openerConditions.push(eq(tickets.guild_id, guildId));
    }
    const openerUpdated = await tx
      .update(tickets)
      .set({ opener_id: 'deleted' })
      .where(and(...openerConditions))
      .returning();

    const claimerConditions = [eq(tickets.claimer_id, userId)];
    if (guildId) {
      claimerConditions.push(eq(tickets.guild_id, guildId));
    }
    const claimerUpdated = await tx
      .update(tickets)
      .set({ claimer_id: 'deleted' })
      .where(and(...claimerConditions))
      .returning();

    const touchedTicketIds = new Set([
      ...openerUpdated.map((t) => t.id),
      ...claimerUpdated.map((t) => t.id),
    ]);
    const updatedTicketsCount = touchedTicketIds.size;

    // 6. Delete ticket_members rows for user
    const memberConditions = [eq(ticketMembers.user_id, userId)];
    if (guildId) {
      memberConditions.push(eq(ticketMembers.guild_id, guildId));
    }
    await tx.delete(ticketMembers).where(and(...memberConditions));

    // 7. Write data_requests row (kind='delete', status='done')
    const targetGuildId = guildId ?? '*';
    await tx.insert(dataRequests).values({
      guild_id: targetGuildId,
      user_id: userId,
      kind: 'delete',
      status: 'done',
    });

    // 8. Write audit_log row without user id in message / detail
    await tx.insert(auditLog).values({
      guild_id: targetGuildId,
      actor_id: 'system',
      kind: 'user.data_delete',
      target: null,
      detail: {
        action: 'user_data_deleted',
        counts: {
          messages: deletedMessagesCount,
          attachments: deletedAttachmentsCount,
          ratings: deletedRatingsCount,
          tickets: updatedTicketsCount,
        },
      },
    });

    return {
      messages: deletedMessagesCount,
      attachments: deletedAttachmentsCount,
      ratings: deletedRatingsCount,
      tickets: updatedTicketsCount,
    };
  });
}

export async function exportGuild(
  db: TicketsDb,
  dataKey: Buffer,
  guildId: string,
): Promise<GuildExport> {
  const [guildRow] = await db
    .select()
    .from(guilds)
    .where(eq(guilds.guild_id, guildId))
    .limit(1);

  const [settingsRow] = await db
    .select()
    .from(guildSettings)
    .where(eq(guildSettings.guild_id, guildId))
    .limit(1);

  const categoryRows = await db
    .select()
    .from(categories)
    .where(eq(categories.guild_id, guildId))
    .orderBy(asc(categories.created_at));

  const panelRows = await db
    .select()
    .from(panels)
    .where(eq(panels.guild_id, guildId))
    .orderBy(asc(panels.created_at));

  const tagRows = await db
    .select()
    .from(tags)
    .where(eq(tags.guild_id, guildId))
    .orderBy(asc(tags.created_at));

  const blockRows = await db
    .select()
    .from(blocks)
    .where(eq(blocks.guild_id, guildId))
    .orderBy(asc(blocks.created_at));

  const ratingRows = await db
    .select()
    .from(ratings)
    .where(eq(ratings.guild_id, guildId))
    .orderBy(asc(ratings.created_at));

  const ticketRows = await db
    .select()
    .from(tickets)
    .where(eq(tickets.guild_id, guildId))
    .orderBy(asc(tickets.created_at));

  const messageRows = await db
    .select()
    .from(messages)
    .where(eq(messages.guild_id, guildId))
    .orderBy(asc(messages.created_at));

  // Decrypt messages
  const messagesByTicket = new Map<string, any[]>();
  for (const msg of messageRows) {
    let content = '';
    try {
      const decryptedBuffer = openBytes(dataKey, msg.content_enc);
      content = decryptedBuffer.toString('utf8');
    } catch {
      content = '[decryption_error]';
    }
    const { content_enc, ...msgWithoutEnc } = msg;
    const decryptedMsg = {
      ...msgWithoutEnc,
      content,
    };
    const list = messagesByTicket.get(msg.ticket_id) ?? [];
    list.push(decryptedMsg);
    messagesByTicket.set(msg.ticket_id, list);
  }

  const ticketsWithMessages = ticketRows.map((t) => ({
    ...t,
    messages: messagesByTicket.get(t.id) ?? [],
  }));

  // Game servers without secret_enc
  const serverRows = await db
    .select({
      id: gameServers.id,
      guild_id: gameServers.guild_id,
      name: gameServers.name,
      confirmed: gameServers.confirmed,
      edition: gameServers.edition,
      resource_version: gameServers.resource_version,
      protocol: gameServers.protocol,
      players_online: gameServers.players_online,
      last_seen_at: gameServers.last_seen_at,
      revoked: gameServers.revoked,
      created_at: gameServers.created_at,
    })
    .from(gameServers)
    .where(eq(gameServers.guild_id, guildId));

  return {
    guild: guildRow ?? null,
    settings: settingsRow ?? null,
    categories: categoryRows,
    panels: panelRows,
    tags: tagRows,
    blocks: blockRows,
    ratings: ratingRows,
    tickets: ticketsWithMessages,
    game_servers: serverRows,
  };
}

export async function purgeExpired(
  db: TicketsDb,
  now: Date = new Date(),
  storage?: StorageService | null,
): Promise<PurgeCounts> {
  const settingsList = await db.select().from(guildSettings);
  const retentionByGuild = new Map<string, number>();
  for (const s of settingsList) {
    retentionByGuild.set(s.guild_id, s.retention_days ?? 90);
  }

  const allGuilds = await db.select({ guild_id: guilds.guild_id }).from(guilds);
  for (const g of allGuilds) {
    if (!retentionByGuild.has(g.guild_id)) {
      retentionByGuild.set(g.guild_id, 90);
    }
  }

  let totalTickets = 0;
  let totalMessages = 0;
  let totalAttachments = 0;

  for (const [guildId, retentionDays] of retentionByGuild.entries()) {
    const thresholdMs = now.getTime() - retentionDays * 24 * 60 * 60 * 1000;
    const thresholdDate = new Date(thresholdMs);

    const expiredTickets = await db
      .select({ id: tickets.id })
      .from(tickets)
      .where(
        and(
          eq(tickets.guild_id, guildId),
          eq(tickets.status, 'closed'),
          isNotNull(tickets.closed_at),
          lt(tickets.closed_at, thresholdDate),
        ),
      );

    if (expiredTickets.length === 0) continue;

    const expiredTicketIds = expiredTickets.map((t) => t.id);

    // Find attachments for storage deletion
    const expiredAttachments = await db
      .select({ id: attachments.id, storage_key: attachments.storage_key })
      .from(attachments)
      .where(
        and(
          eq(attachments.guild_id, guildId),
          inArray(attachments.ticket_id, expiredTicketIds),
        ),
      );

    if (storage && typeof storage.delete === 'function') {
      for (const att of expiredAttachments) {
        if (att.storage_key) {
          try {
            await storage.delete(att.storage_key);
          } catch {}
        }
      }
    }

    // Delete attachments
    if (expiredAttachments.length > 0) {
      const deletedAtt = await db
        .delete(attachments)
        .where(
          and(
            eq(attachments.guild_id, guildId),
            inArray(attachments.ticket_id, expiredTicketIds),
          ),
        )
        .returning();
      totalAttachments += deletedAtt.length;
    }

    // Delete messages
    const deletedMsg = await db
      .delete(messages)
      .where(
        and(
          eq(messages.guild_id, guildId),
          inArray(messages.ticket_id, expiredTicketIds),
        ),
      )
      .returning();
    totalMessages += deletedMsg.length;

    // Delete expired tickets
    const deletedTkt = await db
      .delete(tickets)
      .where(
        and(
          eq(tickets.guild_id, guildId),
          inArray(tickets.id, expiredTicketIds),
        ),
      )
      .returning();
    totalTickets += deletedTkt.length;
  }

  return {
    tickets: totalTickets,
    messages: totalMessages,
    attachments: totalAttachments,
  };
}
