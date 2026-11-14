import { createHash } from 'node:crypto';
import { and, eq, inArray, isNotNull, lt, asc, or, sql } from 'drizzle-orm';
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

  // 1. Find user messages and attachments before transaction
  const messageConditions = [eq(messages.author_id, userId)];
  if (guildId) {
    messageConditions.push(eq(messages.guild_id, guildId));
  }

  const userMessages = await db
    .select({ id: messages.id, guild_id: messages.guild_id })
    .from(messages)
    .where(and(...messageConditions));

  const messageIds = userMessages.map((m) => m.id);

  let userAttachments: Array<{ id: string; storage_key: string | null }> = [];
  if (messageIds.length > 0) {
    const attachmentConditions = [inArray(attachments.message_id, messageIds)];
    if (guildId) {
      attachmentConditions.push(eq(attachments.guild_id, guildId));
    }

    userAttachments = await db
      .select({ id: attachments.id, storage_key: attachments.storage_key })
      .from(attachments)
      .where(and(...attachmentConditions));
  }

  // 2. Database deletions and updates inside transaction
  const txResult = await db.transaction(async (tx) => {
    // 2a. Delete user's messages
    let deletedMessagesCount = 0;
    if (userMessages.length > 0) {
      const deletedMsg = await tx
        .delete(messages)
        .where(and(...messageConditions))
        .returning();
      deletedMessagesCount = deletedMsg.length;
    }

    // 2b. Delete user's ratings
    const ratingConditions = [eq(ratings.user_id, userId)];
    if (guildId) {
      ratingConditions.push(eq(ratings.guild_id, guildId));
    }
    const deletedRatings = await tx
      .delete(ratings)
      .where(and(...ratingConditions))
      .returning();
    const deletedRatingsCount = deletedRatings.length;

    // 2c. Replace opener_id on tickets with 'deleted' AND null answers on that user's tickets
    const openerConditions = [eq(tickets.opener_id, userId)];
    if (guildId) {
      openerConditions.push(eq(tickets.guild_id, guildId));
    }
    const openerUpdated = await tx
      .update(tickets)
      .set({
        opener_id: 'deleted',
        answers: null,
      })
      .where(and(...openerConditions))
      .returning();

    // Replace claimer_id on tickets with 'deleted'
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

    // 2d. Delete ticket_members rows for user
    const memberConditions = [eq(ticketMembers.user_id, userId)];
    if (guildId) {
      memberConditions.push(eq(ticketMembers.guild_id, guildId));
    }
    await tx.delete(ticketMembers).where(and(...memberConditions));

    // 2e. Blocks: delete user's blocks rows (as target) and set created_by to 'deleted' where they blocked others
    const blockTargetConditions = [eq(blocks.user_id, userId)];
    if (guildId) {
      blockTargetConditions.push(eq(blocks.guild_id, guildId));
    }
    await tx.delete(blocks).where(and(...blockTargetConditions));

    const blockCreatorConditions = [eq(blocks.created_by, userId)];
    if (guildId) {
      blockCreatorConditions.push(eq(blocks.guild_id, guildId));
    }
    await tx
      .update(blocks)
      .set({ created_by: 'deleted' })
      .where(and(...blockCreatorConditions));

    // 2f. Anonymise audit_log rows naming them (actor/target -> 'deleted', detail scrubbed of the id)
    const auditConditions = [
      or(
        eq(auditLog.actor_id, userId),
        eq(auditLog.target, userId),
        sql`${auditLog.target} LIKE ${'%' + userId + '%'}`,
        sql`${auditLog.detail}::text LIKE ${'%' + userId + '%'}`
      ),
    ];
    if (guildId) {
      auditConditions.push(eq(auditLog.guild_id, guildId));
    }
    const namedAudits = await tx
      .select({
        id: auditLog.id,
        actor_id: auditLog.actor_id,
        target: auditLog.target,
        detail: auditLog.detail,
      })
      .from(auditLog)
      .where(and(...auditConditions));

    for (const row of namedAudits) {
      const newActor = row.actor_id === userId ? 'deleted' : row.actor_id;
      let newTarget = row.target;
      if (newTarget) {
        if (newTarget === userId) {
          newTarget = 'deleted';
        } else if (newTarget.includes(userId)) {
          newTarget = newTarget.replaceAll(userId, 'deleted');
        }
      }
      let newDetail = row.detail;
      if (newDetail) {
        try {
          const str = JSON.stringify(newDetail);
          if (str.includes(userId)) {
            newDetail = JSON.parse(str.replaceAll(userId, 'deleted'));
          }
        } catch {
          // ignore parsing error
        }
      }
      await tx
        .update(auditLog)
        .set({
          actor_id: newActor,
          target: newTarget,
          detail: newDetail,
        })
        .where(eq(auditLog.id, row.id));
    }

    // 2g. Store data_requests.user_id as sha256(userId)
    const targetGuildId = guildId ?? '*';
    const hashedUserId = createHash('sha256').update(userId).digest('hex');
    await tx.insert(dataRequests).values({
      guild_id: targetGuildId,
      user_id: hashedUserId,
      kind: 'delete',
      status: 'done',
    });

    // 2h. Write audit_log row without user id in message / detail
    await tx.insert(auditLog).values({
      guild_id: targetGuildId,
      actor_id: 'system',
      kind: 'user.data_delete',
      target: null,
      detail: {
        action: 'user_data_deleted',
        counts: {
          messages: deletedMessagesCount,
          ratings: deletedRatingsCount,
          tickets: updatedTicketsCount,
        },
      },
    });

    return {
      messages: deletedMessagesCount,
      ratings: deletedRatingsCount,
      tickets: updatedTicketsCount,
    };
  });

  // 3. Storage deletes happen AFTER the transaction commits!
  // If storage delete fails, keep the attachment row (never orphan files).
  let deletedAttachmentsCount = 0;
  if (storage && typeof storage.delete === 'function') {
    for (const att of userAttachments) {
      if (att.storage_key) {
        try {
          await storage.delete(att.storage_key);
          await db.delete(attachments).where(eq(attachments.id, att.id));
          deletedAttachmentsCount++;
        } catch {
          // Storage delete failed: leave the attachment row in DB, never orphan files!
        }
      } else {
        await db.delete(attachments).where(eq(attachments.id, att.id));
        deletedAttachmentsCount++;
      }
    }
  } else {
    // If no storage service is provided, delete the attachment rows
    if (userAttachments.length > 0) {
      const deletedAtt = await db
        .delete(attachments)
        .where(inArray(attachments.id, userAttachments.map((a) => a.id)))
        .returning();
      deletedAttachmentsCount = deletedAtt.length;
    }
  }

  return {
    messages: txResult.messages,
    attachments: deletedAttachmentsCount,
    ratings: txResult.ratings,
    tickets: txResult.tickets,
  };
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
      .select({
        id: attachments.id,
        ticket_id: attachments.ticket_id,
        storage_key: attachments.storage_key,
      })
      .from(attachments)
      .where(
        and(
          eq(attachments.guild_id, guildId),
          inArray(attachments.ticket_id, expiredTicketIds),
        ),
      );

    const successfulAttachmentIds: string[] = [];
    const failedTicketIds = new Set<string>();

    if (storage && typeof storage.delete === 'function') {
      for (const att of expiredAttachments) {
        if (att.storage_key) {
          try {
            await storage.delete(att.storage_key);
            successfulAttachmentIds.push(att.id);
          } catch {
            // File delete failed: keep the attachment row (mark for retry), never orphan files!
            failedTicketIds.add(att.ticket_id);
          }
        } else {
          successfulAttachmentIds.push(att.id);
        }
      }
    } else {
      for (const att of expiredAttachments) {
        successfulAttachmentIds.push(att.id);
      }
    }

    // Only tickets whose attachments were all successfully deleted (or had no attachments) can be deleted
    const ticketsToDelete = expiredTicketIds.filter((id) => !failedTicketIds.has(id));

    // Delete successfully purged attachments
    if (successfulAttachmentIds.length > 0) {
      const deletedAtt = await db
        .delete(attachments)
        .where(
          and(
            eq(attachments.guild_id, guildId),
            inArray(attachments.id, successfulAttachmentIds),
          ),
        )
        .returning();
      totalAttachments += deletedAtt.length;
    }

    // Delete messages and tickets for tickets that can be safely deleted
    if (ticketsToDelete.length > 0) {
      const deletedMsg = await db
        .delete(messages)
        .where(
          and(
            eq(messages.guild_id, guildId),
            inArray(messages.ticket_id, ticketsToDelete),
          ),
        )
        .returning();
      totalMessages += deletedMsg.length;

      const deletedTkt = await db
        .delete(tickets)
        .where(
          and(
            eq(tickets.guild_id, guildId),
            inArray(tickets.id, ticketsToDelete),
          ),
        )
        .returning();
      totalTickets += deletedTkt.length;
    }
  }

  return {
    tickets: totalTickets,
    messages: totalMessages,
    attachments: totalAttachments,
  };
}
