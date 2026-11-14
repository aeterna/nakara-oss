import {
  Client,
  GatewayIntentBits,
  type Guild,
} from 'discord.js';
import { eq } from 'drizzle-orm';
import { tickets, getTicket, getCategory, getSettings } from '@nakara-tickets/db';
import { acquireGatewayLock, type GatewayLockHandle } from './lock.js';
import { createDiscordPort } from './adapter.js';
import {
  handleOpenButton,
  handleFormSubmit,
  handleClaim,
  handleClose,
  handleReopen,
  handlePanelSend,
  handleMessageCreate,
  handleRatingButton,
  handleRatingModal,
  handleTagCommand,
  handleTagAutocomplete,
  handleDeleteMyData,
  runCloseHooks,
} from './handlers/index.js';
import type {
  StartGatewayDeps,
  GatewayHandle,
  GatewayStatus,
  DiscordPort,
  CloseHookContext,
} from './types.js';

export async function handleInteraction(
  port: DiscordPort,
  deps: StartGatewayDeps,
  interaction: any
): Promise<void> {
  const customId: string =
    interaction.customId ?? interaction.custom_id ?? interaction.data?.custom_id ?? '';

  if (!interaction.guildId) {
    const isRating = customId.startsWith('nt:rate:') || customId.startsWith('nt:ratefb:');
    if (!isRating) {
      return;
    }
    const match = /^nt:rate(?:fb)?:([^:]+):([1-5])$/.exec(customId);
    if (!match) return;
    const ticketId = match[1];
    let ticket: any = null;
    try {
      const [row] = await deps.db
        .select({ guild_id: tickets.guild_id })
        .from(tickets)
        .where(eq(tickets.id, ticketId))
        .limit(1);
      ticket = row;
    } catch {
      return;
    }
    if (!ticket || !deps.allowedGuildIds.includes(ticket.guild_id)) {
      return;
    }
    interaction.guildId = ticket.guild_id;
  } else if (!deps.allowedGuildIds.includes(interaction.guildId)) {
    return;
  }

  try {
    if (interaction.isButton && interaction.isButton()) {
      if (customId.startsWith('nt:open:')) {
        const categoryId = customId.slice('nt:open:'.length);
        await handleOpenButton(port, deps.db, interaction, categoryId);
      } else if (customId.startsWith('nt:claim:')) {
        const ticketId = customId.slice('nt:claim:'.length);
        await handleClaim(port, deps.db, interaction, ticketId);
      } else if (customId.startsWith('nt:close:')) {
        const ticketId = customId.slice('nt:close:'.length);
        await handleClose(port, deps.db, interaction, ticketId, undefined, deps);
      } else if (customId.startsWith('nt:rate:')) {
        await handleRatingButton(port, deps.db, interaction, deps);
      } else if (customId === 'nt:delme:confirm' || customId.startsWith('nt:delme:confirm')) {
        await handleDeleteMyData(port, deps.db, interaction, deps);
      }
    } else if (
      (interaction.isStringSelectMenu && interaction.isStringSelectMenu()) ||
      (interaction.isSelectMenu && interaction.isSelectMenu()) ||
      (interaction.isAnySelectMenu && interaction.isAnySelectMenu()) ||
      (Array.isArray(interaction.values) && interaction.values.length > 0)
    ) {
      if (customId === 'nt:open-select' || customId.startsWith('nt:open-select')) {
        const categoryId = interaction.values?.[0];
        if (categoryId) {
          await handleOpenButton(port, deps.db, interaction, categoryId);
        }
      }
    } else if (interaction.isModalSubmit && interaction.isModalSubmit()) {
      if (customId.startsWith('nt:form:')) {
        const categoryId = customId.slice('nt:form:'.length);
        await handleFormSubmit(port, deps.db, interaction, categoryId);
      } else if (customId.startsWith('nt:ratefb:')) {
        await handleRatingModal(port, deps.db, interaction, deps);
      }
    } else if (interaction.isAutocomplete && interaction.isAutocomplete()) {
      const commandName = interaction.commandName;
      if (commandName === 'tag') {
        await handleTagAutocomplete(deps.db, interaction);
      }
    } else if (interaction.isChatInputCommand && interaction.isChatInputCommand()) {
      const commandName = interaction.commandName;
      const sub = interaction.options?.getSubcommand?.(false);

      if (commandName === 'tag') {
        await handleTagCommand(port, deps.db, interaction, deps);
      } else if (commandName === 'tickets') {
        if (sub === 'delete-my-data') {
          await handleDeleteMyData(port, deps.db, interaction, deps);
        }
      } else if (commandName === 'ticket') {
        if (sub === 'claim') {
          await handleClaim(port, deps.db, interaction);
        } else if (sub === 'close') {
          const reason = interaction.options?.getString?.('reason') ?? undefined;
          await handleClose(port, deps.db, interaction, undefined, reason, deps);
        } else if (sub === 'reopen') {
          await handleReopen(port, deps.db, interaction);
        } else if (sub === 'delete-my-data') {
          await handleDeleteMyData(port, deps.db, interaction, deps);
        }
      } else if (commandName === 'panel') {
        if (sub === 'send') {
          const categoryId = interaction.options?.getString?.('category');
          const targetChannel = interaction.options?.getChannel?.('channel');
          if (categoryId && targetChannel?.id) {
            await handlePanelSend(port, deps.db, interaction, [categoryId], targetChannel.id);
          }
        }
      }
    }
  } catch (err) {
    deps.log.error('Error handling interaction', err);
  }
}

export async function startGateway(deps: StartGatewayDeps): Promise<GatewayHandle> {
  if (!deps.dataKey || !Buffer.isBuffer(deps.dataKey) || deps.dataKey.length !== 32) {
    throw new Error('dataKey is required and must be a 32-byte Buffer');
  }

  let currentStatus: GatewayStatus = 'standby';
  let lockHandle: GatewayLockHandle | null = null;
  const abortController = new AbortController();
  let stopped = false;

  const client =
    deps.client ??
    new Client({
      intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.GuildMembers,
        GatewayIntentBits.MessageContent,
      ],
    });

  const port: DiscordPort = createDiscordPort(client);

  const slashCommands = [
    {
      name: 'ticket',
      description: 'Manage tickets',
      options: [
        {
          name: 'claim',
          description: 'Claim this ticket',
          type: 1, // Subcommand
        },
        {
          name: 'close',
          description: 'Close this ticket',
          type: 1, // Subcommand
          options: [
            {
              name: 'reason',
              description: 'Reason for closing',
              type: 3, // String
              required: false,
            },
          ],
        },
        {
          name: 'reopen',
          description: 'Reopen this ticket',
          type: 1, // Subcommand
        },
      ],
    },
    {
      name: 'panel',
      description: 'Manage ticket panels',
      options: [
        {
          name: 'send',
          description: 'Send a ticket panel to a channel',
          type: 1, // Subcommand
          options: [
            {
              name: 'category',
              description: 'Category ID',
              type: 3, // String
              required: true,
            },
            {
              name: 'channel',
              description: 'Channel to send to',
              type: 7, // Channel
              required: true,
            },
          ],
        },
      ],
    },
    {
      name: 'tag',
      description: 'Send a predefined snippet or tag',
      options: [
        {
          name: 'name',
          description: 'Tag name',
          type: 3, // String
          required: true,
          autocomplete: true,
        },
      ],
    },
    {
      name: 'tickets',
      description: 'Ticket management commands',
      options: [
        {
          name: 'delete-my-data',
          description: 'Request deletion of your ticket data',
          type: 1, // Subcommand
        },
      ],
    },
  ];

  // Guild unauthorized check helper
  const checkGuildAllowed = async (guild: Guild | { id: string; leave: () => Promise<any> }) => {
    if (!deps.allowedGuildIds.includes(guild.id)) {
      deps.log.warn(`Leaving unauthorized guild ${guild.id}`);
      try {
        await guild.leave();
      } catch (err) {
        deps.log.error(`Failed to leave unauthorized guild ${guild.id}`, err);
      }
    }
  };

  client.on('guildCreate', async (guild: any) => {
    await checkGuildAllowed(guild);
  });

  client.on('ready', async () => {
    currentStatus = 'connected';
    deps.log.info('Discord gateway connected and ready');

    // Register slash commands for allowed guilds and leave unauthorized guilds
    if (client.guilds?.cache) {
      for (const [id, guild] of client.guilds.cache) {
        if (!deps.allowedGuildIds.includes(id)) {
          await checkGuildAllowed(guild as any);
        } else {
          try {
            if ((guild as any).commands?.set) {
              await (guild as any).commands.set(slashCommands);
            }
          } catch (err) {
            deps.log.error(`Failed to register slash commands for guild ${id}`, err);
          }
        }
      }
    }
  });

  client.on('interactionCreate', async (interaction: any) => {
    await handleInteraction(port, deps, interaction);
  });

  client.on('messageCreate', async (message: any) => {
    try {
      await handleMessageCreate(deps.db, deps.dataKey, message);
    } catch (err) {
      deps.log.error('Error handling messageCreate', err);
    }
  });

  // Background loop to acquire lock and connect
  const initPromise = (async () => {
    try {
      lockHandle = await acquireGatewayLock(deps.pool, deps.appId, {
        signal: abortController.signal,
        intervalMs: deps.lockOpts?.intervalMs ?? 5000,
        onStandby: () => {
          currentStatus = 'standby';
          if (deps.lockOpts?.onStandby) {
            deps.lockOpts.onStandby();
          }
        },
      });

      if (stopped) {
        await lockHandle.release();
        return;
      }

      currentStatus = 'connecting';
      await client.login(deps.token);
    } catch (err: any) {
      if (stopped || abortController.signal.aborted) {
        return;
      }
      deps.log.error('Gateway failed to start or acquire lock', err);
    }
  })();

  // Let background process kick off
  // Wait a microtask so initial lock attempt executes
  await Promise.resolve();

  return {
    status() {
      return currentStatus;
    },
    async closeHooks(guildId: string, ticketId: string, actorId: string): Promise<void> {
      let ticket: any = null;
      try {
        ticket = await getTicket(deps.db, guildId, ticketId);
      } catch (err) {
        deps.log.warn(`Ticket ${ticketId} not found in closeHooks: ${err}`);
        return;
      }
      // Hooks only run for a closed ticket; a reopened or still-open ticket is left alone.
      if (!ticket || ticket.status !== 'closed') return;

      let category: any = null;
      try {
        category = await getCategory(deps.db, guildId, ticket.category_id);
      } catch (err) {
        deps.log.warn(`Category ${ticket.category_id} not found in closeHooks: ${err}`);
      }

      let settings: any = null;
      try {
        settings = await getSettings(deps.db, guildId);
      } catch (err) {
        deps.log.warn(`Settings for guild ${guildId} not found in closeHooks: ${err}`);
      }

      const hookCtx: CloseHookContext = {
        port,
        db: deps.db,
        dataKey: deps.dataKey,
        storage: deps.storage,
        ticket,
        category,
        guildSettings: settings,
        actorId,
        log: deps.log,
      };

      try {
        await runCloseHooks(hookCtx);
      } catch (err) {
        deps.log.error('Error running close hooks in GatewayHandle.closeHooks', err);
      }

      if (ticket.channel_id) {
        try {
          await port.lockAndArchiveThread(ticket.channel_id);
        } catch (err) {
          deps.log.error(`Failed to lock/archive thread ${ticket.channel_id}`, err);
        }
      }
    },
    async stop() {
      stopped = true;
      abortController.abort();
      try {
        if (typeof client.destroy === 'function') {
          await client.destroy();
        }
      } catch {
        // Ignore destroy error
      }
      if (lockHandle) {
        try {
          await lockHandle.release();
        } catch {
          // Ignore release error
        }
      }
      await initPromise.catch(() => {});
    },
  };
}
