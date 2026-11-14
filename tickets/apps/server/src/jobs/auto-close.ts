import { and, or, eq, isNotNull, gt, asc } from 'drizzle-orm';
import { tickets, categories, guildSettings, transitionTicket } from '@nakara-tickets/db';
import type { Job, JobContext } from '../worker.js';

const MESSAGES = {
  th: {
    warn: 'ตั๋วนี้ไม่มีการเคลื่อนไหวเป็นเวลานาน และจะถูกปิดโดยอัตโนมัติหากไม่มีการตอบกลับ',
    close: 'ตั๋วนี้ถูกปิดโดยอัตโนมัติเนื่องจากไม่มีการเคลื่อนไหว',
  },
  en: {
    warn: 'This ticket has been inactive and will be closed automatically if there is no response.',
    close: 'This ticket was closed automatically due to inactivity.',
  },
};

export const autoCloseJob: Job = {
  name: 'auto-close',
  intervalMs: 5 * 60 * 1000, // 5 minutes
  async run(ctx: JobContext): Promise<void> {
    const rows = await ctx.db
      .select({
        ticket: tickets,
        category: categories,
        guildSettings: guildSettings,
      })
      .from(tickets)
      .innerJoin(categories, eq(tickets.category_id, categories.id))
      .leftJoin(guildSettings, eq(tickets.guild_id, guildSettings.guild_id))
      .where(
        and(
          or(eq(tickets.status, 'open'), eq(tickets.status, 'claimed')),
          isNotNull(categories.auto_close_hours),
          gt(categories.auto_close_hours, 0)
        )
      )
      .orderBy(asc(tickets.last_activity_at), asc(tickets.created_at))
      .limit(200);

    for (const row of rows) {
      try {
        const { ticket, category, guildSettings: settings } = row;
        const now = Date.now();

        // Activity after the warning (a newer last_activity_at) clears the warning
        if (
          ticket.auto_close_warned_at &&
          ticket.last_activity_at &&
          new Date(ticket.last_activity_at).getTime() > new Date(ticket.auto_close_warned_at).getTime()
        ) {
          await ctx.db
            .update(tickets)
            .set({ auto_close_warned_at: null })
            .where(eq(tickets.id, ticket.id));
          ticket.auto_close_warned_at = null;
        }

        const lastActivityTime = ticket.last_activity_at
          ? new Date(ticket.last_activity_at).getTime()
          : new Date(ticket.created_at).getTime();
        const inactiveHours = (now - lastActivityTime) / (3600 * 1000);
        const autoCloseHours = category.auto_close_hours!;
        const warnHours = settings?.auto_close_warn_hours ?? 12;
        const warnThresholdHours = autoCloseHours - warnHours;

        const locale = settings?.locale === 'en' ? 'en' : 'th';

        if (inactiveHours >= autoCloseHours) {
          await transitionTicket(
            ctx.db,
            ticket.guild_id,
            ticket.id,
            'close',
            'system',
            undefined,
            'auto-close'
          );

          if (ctx.discord) {
            const closeMsg = MESSAGES[locale].close;
            try {
              await ctx.discord.sendMessage(ticket.channel_id, { content: closeMsg });
            } catch (err) {
              ctx.log.error(`Failed to post auto-close message for ticket ${ticket.id}:`, err);
            }

            if (category.mode === 'thread') {
              try {
                await ctx.discord.patchChannel(ticket.channel_id, {
                  archived: true,
                  locked: true,
                });
              } catch (err) {
                ctx.log.error(`Failed to patch channel for ticket ${ticket.id}:`, err);
              }
            }
          }
        } else if (inactiveHours >= warnThresholdHours && !ticket.auto_close_warned_at) {
          if (ctx.discord) {
            const warnMsg = MESSAGES[locale].warn;
            await ctx.discord.sendMessage(ticket.channel_id, { content: warnMsg });
            await ctx.db
              .update(tickets)
              .set({ auto_close_warned_at: new Date() })
              .where(eq(tickets.id, ticket.id));
          }
        }
      } catch (err) {
        ctx.log.error(`Error processing auto-close for ticket ${row.ticket.id}:`, err);
      }
    }
  },
};

export default autoCloseJob;
