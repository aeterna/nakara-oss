import type { CloseHookContext, DiscordPort } from '../types.js';
import { tickets, ratings, guildSettings, inGuild, type TicketsDb } from '@nakara-tickets/db';
import { and, eq } from 'drizzle-orm';
import { t } from '../i18n.js';

export async function ratingOnClose(ctx: CloseHookContext): Promise<void> {
  const { port, db, ticket, log } = ctx;
  if (!ticket || !ticket.id) return;

  const guildId = ticket.guild_id;

  // Send only when no rating exists
  try {
    const existing = await db
      .select({ id: ratings.id })
      .from(ratings)
      .where(and(eq(ratings.ticket_id, ticket.id), inGuild(ratings, guildId)))
      .limit(1);

    if (existing.length > 0) {
      return;
    }
  } catch (err) {
    if (typeof log?.error === 'function') {
      log.error('Failed to check existing rating on close', err);
    }
    return;
  }

  let locale = ctx.guildSettings?.locale || 'th';
  if (!ctx.guildSettings) {
    try {
      const [settings] = await db
        .select()
        .from(guildSettings)
        .where(eq(guildSettings.guild_id, guildId))
        .limit(1);
      if (settings?.locale) {
        locale = settings.locale;
      }
    } catch {}
  }

  const buttons = [1, 2, 3, 4, 5].map((score) => ({
    type: 2,
    style: 1,
    customId: `nt:rate:${ticket.id}:${score}`,
    custom_id: `nt:rate:${ticket.id}:${score}`,
    label: `${score} ⭐`,
  }));

  const components = [
    {
      type: 1,
      components: buttons,
    },
  ];

  const content = t(locale, 'rating_prompt');
  const payload = { content, components };

  // Post message in ticket channel
  if (ticket.channel_id) {
    try {
      await port.sendMessage(ticket.channel_id, payload);
    } catch (err) {
      if (typeof log?.error === 'function') {
        log.error('Failed to post rating message to ticket channel', err);
      }
    }
  }

  // If guildSettings.rating_dm is true, DM the opener once
  if (ctx.guildSettings?.rating_dm && ticket.opener_id) {
    try {
      if (typeof (port as any).sendDM === 'function') {
        await (port as any).sendDM(ticket.opener_id, payload);
      } else if (typeof (port as any).sendDm === 'function') {
        await (port as any).sendDm(ticket.opener_id, payload);
      } else if (typeof (ctx as any).sendDM === 'function') {
        await (ctx as any).sendDM(ticket.opener_id, payload);
      } else if (typeof (ctx as any).discord?.createDM === 'function') {
        const dm = await (ctx as any).discord.createDM(ticket.opener_id);
        await (ctx as any).discord.sendMessage(dm.id, payload);
      } else if (typeof (ctx as any).client?.users?.fetch === 'function') {
        const user = await (ctx as any).client.users.fetch(ticket.opener_id);
        await user.send(payload);
      } else if (typeof (ctx as any).client?.users?.send === 'function') {
        await (ctx as any).client.users.send(ticket.opener_id, payload);
      }
    } catch (err: any) {
      const is50007 =
        err?.code === 50007 ||
        err?.code === '50007' ||
        err?.rawError?.code === 50007 ||
        String(err?.message).includes('50007');

      if (!is50007) {
        if (typeof log?.error === 'function') {
          log.error('Failed to send rating DM to opener', err);
        } else if (typeof log?.warn === 'function') {
          log.warn('Failed to send rating DM to opener', err);
        }
      }
    }
  }
}

export async function handleRatingButton(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  deps?: any
): Promise<void> {
  const customId: string =
    interaction?.customId || interaction?.custom_id || interaction?.data?.custom_id || '';
  const match = /^nt:rate:([^:]+):([1-5])$/.exec(customId);
  if (!match) return;

  const ticketId = match[1];
  const score = parseInt(match[2], 10);

  const [ticket] = await db
    .select()
    .from(tickets)
    .where(eq(tickets.id, ticketId))
    .limit(1);

  let locale = 'th';
  if (ticket) {
    try {
      const [settings] = await db
        .select()
        .from(guildSettings)
        .where(eq(guildSettings.guild_id, ticket.guild_id))
        .limit(1);
      if (settings?.locale) {
        locale = settings.locale;
      }
    } catch {}
  }

  if (!ticket) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  const userId =
    interaction.user?.id ?? interaction.member?.user?.id ?? interaction.userId ?? '';

  // Only opener may rate
  if (userId !== ticket.opener_id) {
    await port.replyEphemeral(interaction, t(locale, 'rating_opener_only'));
    return;
  }

  // Once per ticket
  const existing = await db
    .select({ id: ratings.id })
    .from(ratings)
    .where(and(eq(ratings.ticket_id, ticket.id), inGuild(ratings, ticket.guild_id)))
    .limit(1);

  if (existing.length > 0) {
    await port.replyEphemeral(interaction, t(locale, 'rating_already_submitted'));
    return;
  }

  // Show modal nt:ratefb:<ticketId>:<score> with one optional paragraph input (<= 1000)
  const modal = {
    customId: `nt:ratefb:${ticket.id}:${score}`,
    custom_id: `nt:ratefb:${ticket.id}:${score}`,
    title: t(locale, 'rating_modal_title'),
    components: [
      {
        type: 1,
        components: [
          {
            type: 4,
            customId: 'feedback',
            custom_id: 'feedback',
            label: t(locale, 'rating_feedback_label'),
            style: 2,
            required: false,
            maxLength: 1000,
            max_length: 1000,
            placeholder: t(locale, 'rating_feedback_placeholder'),
          },
        ],
      },
    ],
  };

  if (typeof port.showModal === 'function') {
    await port.showModal(interaction, modal);
  } else if (typeof interaction.showModal === 'function') {
    await interaction.showModal(modal);
  }
}

export async function handleRatingModal(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  deps?: any
): Promise<void> {
  const customId: string =
    interaction?.customId || interaction?.custom_id || interaction?.data?.custom_id || '';
  const match = /^nt:ratefb:([^:]+):([1-5])$/.exec(customId);
  if (!match) return;

  const ticketId = match[1];
  const score = parseInt(match[2], 10);

  const [ticket] = await db
    .select()
    .from(tickets)
    .where(eq(tickets.id, ticketId))
    .limit(1);

  let locale = 'th';
  if (ticket) {
    try {
      const [settings] = await db
        .select()
        .from(guildSettings)
        .where(eq(guildSettings.guild_id, ticket.guild_id))
        .limit(1);
      if (settings?.locale) {
        locale = settings.locale;
      }
    } catch {}
  }

  if (!ticket) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  const userId =
    interaction.user?.id ?? interaction.member?.user?.id ?? interaction.userId ?? '';

  if (userId !== ticket.opener_id) {
    await port.replyEphemeral(interaction, t(locale, 'rating_opener_only'));
    return;
  }

  // Extract feedback text
  let feedback: string | null = null;
  if (typeof interaction.fields?.getTextInputValue === 'function') {
    feedback =
      interaction.fields.getTextInputValue('feedback') ||
      interaction.fields.getTextInputValue('nt:feedback') ||
      null;
  } else if (Array.isArray(interaction.data?.components)) {
    for (const row of interaction.data.components) {
      if (Array.isArray(row.components)) {
        for (const comp of row.components) {
          if (comp.custom_id === 'feedback' || comp.custom_id === 'nt:feedback') {
            feedback = comp.value;
          }
        }
      }
    }
  }

  if (typeof feedback === 'string') {
    feedback = feedback.trim();
    if (feedback.length > 1000) {
      feedback = feedback.slice(0, 1000);
    }
    if (feedback.length === 0) {
      feedback = null;
    }
  }

  // Insert rating if none exists
  const existing = await db
    .select({ id: ratings.id })
    .from(ratings)
    .where(and(eq(ratings.ticket_id, ticket.id), inGuild(ratings, ticket.guild_id)))
    .limit(1);

  if (existing.length === 0) {
    await db.insert(ratings).values({
      guild_id: ticket.guild_id,
      ticket_id: ticket.id,
      user_id: userId,
      staff_id: ticket.claimer_id ?? null,
      score,
      feedback: feedback ?? null,
    });
  }

  await port.replyEphemeral(interaction, t(locale, 'rating_thanks'));
}
