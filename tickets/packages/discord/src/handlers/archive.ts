import { createHash, randomUUID } from 'node:crypto';
import { and, eq, sql } from 'drizzle-orm';
import { tickets, attachments } from '@nakara-tickets/db';
import type { CloseHookContext } from '../types.js';
import { createStorageClient } from '../storage-client.js';

const MAX_FILE_SIZE = 25 * 1024 * 1024; // 25 MB
const ALLOWED_HOSTS = ['cdn.discordapp.com', 'media.discordapp.net'];

function isValidAttachmentUrl(urlString: string): boolean {
  try {
    const parsed = new URL(urlString);
    if (parsed.protocol !== 'https:') return false;
    return ALLOWED_HOSTS.includes(parsed.hostname);
  } catch {
    return false;
  }
}

interface DownloadResult {
  ok: boolean;
  bytes?: Buffer;
  contentType?: string | null;
  aborted?: boolean;
}

async function downloadAttachment(
  initialUrl: string,
  effectiveCap: number,
  timeoutMs = 30_000
): Promise<DownloadResult> {
  let currentUrl = initialUrl;
  let hops = 0;

  while (true) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error('Timeout')), timeoutMs);

    let res: Response;
    try {
      res = await fetch(currentUrl, {
        redirect: 'manual',
        signal: controller.signal,
      });
    } catch {
      clearTimeout(timer);
      return { ok: false };
    }
    clearTimeout(timer);

    // 3xx Redirect handling (SSRF prevention)
    if (res.status >= 300 && res.status < 400) {
      hops++;
      if (hops > 3) {
        // Exceeded max 3 hops -> skip as stored=false
        return { ok: false, aborted: true };
      }

      const location = res.headers?.get?.('location') ?? (res.headers as any)?.location;
      if (!location) {
        return { ok: false, aborted: true };
      }

      let targetUrl: URL;
      try {
        targetUrl = new URL(location, currentUrl);
      } catch {
        return { ok: false, aborted: true };
      }

      if (targetUrl.protocol !== 'https:' || !ALLOWED_HOSTS.includes(targetUrl.hostname)) {
        // Evil or unallowed host redirect -> skip as stored=false
        return { ok: false, aborted: true };
      }

      currentUrl = targetUrl.href;
      continue;
    }

    if (!res.ok) {
      return { ok: false };
    }

    // Check Content-Length header if present
    const clHeader = res.headers?.get?.('content-length') ?? (res.headers as any)?.['content-length'];
    if (clHeader) {
      const cl = parseInt(String(clHeader), 10);
      if (!Number.isNaN(cl) && cl > effectiveCap) {
        return { ok: false, aborted: true };
      }
    }

    const contentType =
      res.headers?.get?.('content-type') ?? (res.headers as any)?.['content-type'] ?? null;

    // Stream body to count bytes and prevent unbounded buffering
    if (res.body) {
      const chunks: Buffer[] = [];
      let totalBytes = 0;
      let capExceeded = false;

      if (typeof (res.body as any).getReader === 'function') {
        const reader = (res.body as any).getReader();
        try {
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            if (value) {
              totalBytes += value.length;
              if (totalBytes > effectiveCap) {
                capExceeded = true;
                try {
                  await reader.cancel('Size cap exceeded');
                } catch {}
                break;
              }
              chunks.push(Buffer.isBuffer(value) ? value : Buffer.from(value));
            }
          }
        } catch {
          if (capExceeded) {
            return { ok: false, aborted: true };
          }
          return { ok: false };
        }
      } else if (Symbol.asyncIterator in (res.body as any)) {
        try {
          for await (const chunk of res.body as any) {
            totalBytes += chunk.length;
            if (totalBytes > effectiveCap) {
              capExceeded = true;
              try {
                await (res.body as any).cancel?.('Size cap exceeded');
              } catch {}
              controller.abort();
              break;
            }
            chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
          }
        } catch {
          if (capExceeded) {
            return { ok: false, aborted: true };
          }
          return { ok: false };
        }
      }

      if (capExceeded) {
        return { ok: false, aborted: true };
      }

      return {
        ok: true,
        bytes: Buffer.concat(chunks),
        contentType,
      };
    }

    // Fallback for mock environments without res.body
    if (typeof (res as any).arrayBuffer === 'function') {
      try {
        const ab = await (res as any).arrayBuffer();
        const buf = Buffer.from(ab);
        if (buf.length > effectiveCap) {
          return { ok: false, aborted: true };
        }
        return {
          ok: true,
          bytes: buf,
          contentType,
        };
      } catch {
        return { ok: false };
      }
    }

    return {
      ok: true,
      bytes: Buffer.alloc(0),
      contentType,
    };
  }
}

export async function archiveOnClose(ctx: CloseHookContext): Promise<void> {
  try {
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

        const remainingQuota = quotaBytes - currentTotalBytes;
        const effectiveCap = Math.min(MAX_FILE_SIZE, Math.max(0, remainingQuota));

        // Check if reportedSize already exceeds cap or guild quota
        if (effectiveCap <= 0 || reportedSize > MAX_FILE_SIZE || currentTotalBytes + reportedSize > quotaBytes) {
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
          const download = await downloadAttachment(url, effectiveCap);
          if (!download.ok || !download.bytes) {
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

          const bytes = download.bytes;
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

          if (ctx.storage) {
            await ctx.storage.put(storageKey, bytes, contentType || 'application/octet-stream');
          } else {
            const fallbackStorage = createStorageClient(ctx.dataKey);
            await fallbackStorage.put(storageKey, bytes, contentType);
          }

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
