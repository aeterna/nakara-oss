import type { DiscordPort } from '../types.js';
import type { TicketsDb } from '@nakara-tickets/db';
import { tickets, eq } from '@nakara-tickets/db';
import { getCategory, getSettings, openTicket, TicketError } from '../db-bridge.js';
import { t, type TranslationKey } from '../i18n.js';

export async function handleOpenButton(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  categoryId: string
): Promise<void> {
  const guildId = interaction.guildId;
  const settings = await getSettings(db, guildId);
  const locale = settings?.locale ?? 'th';

  const category = await getCategory(db, guildId, categoryId);
  if (!category) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  // If category has a form (<= 5 fields), show modal
  if (category.form && Array.isArray(category.form) && category.form.length > 0) {
    const fields = category.form.slice(0, 5);
    const modalComponents = fields.map((f: any) => ({
      type: 1, // ActionRow
      components: [
        {
          type: 4, // TextInput
          custom_id: f.id ?? f.customId ?? f.name,
          customId: f.id ?? f.customId ?? f.name,
          label: f.label ?? f.name ?? 'Input',
          style: f.paragraph ? 2 : 1, // Paragraph vs Short
          required: Boolean(f.required),
          placeholder: f.placeholder ?? undefined,
        },
      ],
    }));

    await port.showModal(interaction, {
      customId: `nt:form:${categoryId}`,
      title: category.name.slice(0, 45),
      components: modalComponents,
    });
    return;
  }

  // No form: acknowledge within 3s then open directly
  await port.deferReply(interaction, { ephemeral: true });
  await executeOpenTicket(port, db, interaction, category, undefined, locale);
}

export async function handleFormSubmit(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  categoryId: string
): Promise<void> {
  const guildId = interaction.guildId;
  const settings = await getSettings(db, guildId);
  const locale = settings?.locale ?? 'th';

  const category = await getCategory(db, guildId, categoryId);
  if (!category) {
    await port.replyEphemeral(interaction, t(locale, 'ticket_not_found'));
    return;
  }

  // Extract answers from fields
  const answers: Record<string, string> = {};
  if (interaction.fields?.fields) {
    for (const [key, field] of interaction.fields.fields) {
      answers[key] = field.value;
    }
  } else if (interaction.fields?.getTextInputValue) {
    if (category.form && Array.isArray(category.form)) {
      for (const f of category.form) {
        const id = f.id ?? f.customId ?? f.name;
        try {
          answers[id] = interaction.fields.getTextInputValue(id);
        } catch {
          // Field not found or optional
        }
      }
    }
  }

  await port.deferReply(interaction, { ephemeral: true });
  await executeOpenTicket(port, db, interaction, category, answers, locale);
}

async function executeOpenTicket(
  port: DiscordPort,
  db: TicketsDb,
  interaction: any,
  category: any,
  answers: any,
  locale: string
): Promise<void> {
  const guildId = interaction.guildId;
  const openerId = interaction.user?.id ?? interaction.member?.user?.id;

  try {
    const ticket = await openTicket(db, {
      guildId,
      categoryId: category.id,
      openerId,
      channelId: category.parent_channel_id,
      answers,
    });

    const padNum = String(ticket.number).padStart(4, '0');
    const username = interaction.user?.username ?? interaction.member?.user?.username ?? 'user';
    const template = category.name_template || 'ticket-{number}';
    const threadName = template.replaceAll('{number}', padNum).replaceAll('{user}', username);

    const thread = await port.createPrivateThread(category.parent_channel_id, threadName);

    // Update ticket with thread channel ID
    await db
      .update(tickets)
      .set({ channel_id: thread.id })
      .where(eq(tickets.id, ticket.id));

    await port.addMember(thread.id, openerId);

    const welcomeMsg = category.welcome_message || t(locale, 'ticket_welcome');
    const buttons = {
      type: 1, // ActionRow
      components: [
        {
          type: 2, // Button
          style: 1, // Primary
          custom_id: `nt:claim:${ticket.id}`,
          customId: `nt:claim:${ticket.id}`,
          label: t(locale, 'claim_button'),
        },
        {
          type: 2, // Button
          style: 4, // Danger
          custom_id: `nt:close:${ticket.id}`,
          customId: `nt:close:${ticket.id}`,
          label: t(locale, 'close_button'),
        },
      ],
    };

    await port.sendMessage(thread.id, {
      content: welcomeMsg,
      components: [buttons],
    });

    await port.editReply(interaction, {
      content: t(locale, 'ticket_created', { channel: `<#${thread.id}>` }),
    });
  } catch (err: any) {
    if (err instanceof TicketError || err?.code === 'limit' || err?.code === 'blocked') {
      const codeKey = `ticket_${err.code}` as TranslationKey;
      await port.editReply(interaction, { content: t(locale, codeKey) });
      return;
    }
    throw err;
  }
}
