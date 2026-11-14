import { createHash, randomUUID } from 'node:crypto';
import { and, eq, sql } from 'drizzle-orm';
import { tickets, attachments } from '@nakara-tickets/db';
import type { CloseHookContext } from '../types.js';
import { createStorageClient } from '../storage-client.js';

const MAX_FILE_SIZE = 25 * 1024 * 1024; // 25 MB

function isValidAttachmentUrl(urlString: string): boolean {
  try {
    const parsed = new URL(urlString);
    if (parsed.protocol !== 'https:') return false;
    const allowedHosts = ['cdn.discordapp.com', 'media.discordapp.net'];
    return allowedHosts.includes(parsed.hostname);
  } catch {
    return false;
  }
}

export async function archiveOnClose(ctx: CloseHookContext): Promise<void> {
  try {
    const storage = createStorageClient(ctx.dataKey);

    // Fetch messages from thread
    const allMessages: any[] = [];
    if (typeof ctx.port.fetchMessages === 'function') {
      let before: string | undefined = undefined;
      while (true) {
        const batch: any[] = await ctx.port.fetchMessages(ctx.ticket.channel_id, before);
        if (!batch || batch.length === 0) break;
        allMessages.push(...batch);
        if (batch.length < 100) break;
        before = batch[batch.length - 1].id;
      }
    }

    const quotaMb = ctx.guildSettings?.attachment_quota_mb ?? 500;
    const quotaBytes = quotaMb * 1024 * 1024;

    const sumRes = await ctx.db
      .select({ total: sql<number>`coalesce(sum(${attachments.size}), 0)` })
      .from(attachments)
      .where(and(eq(attachments.guild_id, ctx.ticket.guild_id), eq(attachments.stored, true)));

    let currentTotalBytes = Number(sumRes[0]?.total ?? 0);

    for (const msg of allMessages) {
      const attList = Array.isArray(msg.attachments)
        ? msg.attachments
        : typeof msg.attachments?.values === 'function'
          ? Array.from(msg.attachments.values())
          : [];

      for (const att of attList) {
        const url = att.url;
        if (!url || typeof url !== 'string' || !isValidAttachmentUrl(url)) {
          // Evil or unallowed host skipped
          continue;
        }

        const filename = att.name || att.filename || 'attachment';
        const reportedSize = typeof att.size === 'number' ? att.size : 0;
        const contentType = att.contentType || null;
        const attachmentId = randomUUID();

        // Check if over 25 MB cap or over guild quota
        if (reportedSize > MAX_FILE_SIZE || currentTotalBytes + reportedSize > quotaBytes) {
          await ctx.db.insert(attachments).values({
            id: attachmentId,
            guild_id: ctx.ticket.guild_id,
            ticket_id: ctx.ticket.id,
            message_id: msg.id,
            filename,
            content_type: contentType,
            size: reportedSize,
            sha256: createHash('sha256').update('').digest('hex'),
            stored: false,
            storage_key: null,
          });
          continue;
        }

        try {
          const res = await fetch(url, { signal: AbortSignal.timeout(30_000) });
          if (!res.ok) {
            await ctx.db.insert(attachments).values({
              id: attachmentId,
              guild_id: ctx.ticket.guild_id,
              ticket_id: ctx.ticket.id,
              message_id: msg.id,
              filename,
              content_type: contentType,
              size: reportedSize,
              sha256: createHash('sha256').update('').digest('hex'),
              stored: false,
              storage_key: null,
            });
            continue;
          }

          const bytes = Buffer.from(await res.arrayBuffer());
          const actualSize = bytes.length;

          if (actualSize > MAX_FILE_SIZE || currentTotalBytes + actualSize > quotaBytes) {
            await ctx.db.insert(attachments).values({
              id: attachmentId,
              guild_id: ctx.ticket.guild_id,
              ticket_id: ctx.ticket.id,
              message_id: msg.id,
              filename,
              content_type: contentType,
              size: actualSize,
              sha256: createHash('sha256').update('').digest('hex'),
              stored: false,
              storage_key: null,
            });
            continue;
          }

          const sha256 = createHash('sha256').update(bytes).digest('hex');
          const storageKey = `${ctx.ticket.guild_id}/${ctx.ticket.id}/${attachmentId}`;

          await storage.put(storageKey, bytes, contentType);

          await ctx.db.insert(attachments).values({
            id: attachmentId,
            guild_id: ctx.ticket.guild_id,
            ticket_id: ctx.ticket.id,
            message_id: msg.id,
            filename,
            content_type: contentType,
            size: actualSize,
            sha256,
            stored: true,
            storage_key: storageKey,
          });

          currentTotalBytes += actualSize;
        } catch (downloadErr) {
          if (typeof ctx.log?.warn === 'function') {
            ctx.log.warn(`Failed to download attachment ${url}`, downloadErr);
          }
          await ctx.db.insert(attachments).values({
            id: attachmentId,
            guild_id: ctx.ticket.guild_id,
            ticket_id: ctx.ticket.id,
            message_id: msg.id,
            filename,
            content_type: contentType,
            size: reportedSize,
            sha256: createHash('sha256').update('').digest('hex'),
            stored: false,
            storage_key: null,
          });
        }
      }
    }

    // Set tickets.archived_at
    await ctx.db
      .update(tickets)
      .set({ archived_at: new Date() })
      .where(and(eq(tickets.id, ctx.ticket.id), eq(tickets.guild_id, ctx.ticket.guild_id)));
  } catch (err) {
    if (typeof ctx.log?.error === 'function') {
      ctx.log.error('Archive on close failed', err);
    } else {
      console.error('Archive on close failed', err);
    }
  }
}
