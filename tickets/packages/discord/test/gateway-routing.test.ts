import { describe, it, expect, vi } from 'vitest';
import { handleInteraction } from '../src/gateway.js';
import * as ratingHandler from '../src/handlers/rating.js';
import * as tagHandler from '../src/handlers/tag.js';
import * as dataHandler from '../src/handlers/data.js';

describe('gateway routing (x2)', () => {
  const mockPort: any = {
    deferReply: vi.fn().mockResolvedValue(undefined),
    editReply: vi.fn().mockResolvedValue(undefined),
  };

  const mockDeps: any = {
    allowedGuildIds: ['guild-1'],
    db: {} as any,
    log: {
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    },
  };

  it('routes button nt:rate:<ticketId>:<score> to handleRatingButton', async () => {
    const spy = vi.spyOn(ratingHandler, 'handleRatingButton').mockResolvedValue(undefined);
    const interaction: any = {
      guildId: 'guild-1',
      isButton: () => true,
      customId: 'nt:rate:ticket-123:5',
    };

    await handleInteraction(mockPort, mockDeps, interaction);
    expect(spy).toHaveBeenCalledWith(mockPort, mockDeps.db, interaction, mockDeps);
    spy.mockRestore();
  });

  it('routes modal nt:ratefb:<ticketId>:<score> to handleRatingModal', async () => {
    const spy = vi.spyOn(ratingHandler, 'handleRatingModal').mockResolvedValue(undefined);
    const interaction: any = {
      guildId: 'guild-1',
      isModalSubmit: () => true,
      customId: 'nt:ratefb:ticket-123:5',
    };

    await handleInteraction(mockPort, mockDeps, interaction);
    expect(spy).toHaveBeenCalledWith(mockPort, mockDeps.db, interaction, mockDeps);
    spy.mockRestore();
  });

  it('routes command tag to handleTagCommand', async () => {
    const spy = vi.spyOn(tagHandler, 'handleTagCommand').mockResolvedValue(undefined);
    const interaction: any = {
      guildId: 'guild-1',
      isChatInputCommand: () => true,
      commandName: 'tag',
      options: {
        getSubcommand: () => null,
        getString: vi.fn().mockReturnValue('help'),
      },
    };

    await handleInteraction(mockPort, mockDeps, interaction);
    expect(spy).toHaveBeenCalledWith(mockPort, mockDeps.db, interaction, mockDeps);
    spy.mockRestore();
  });

  it('routes autocomplete for tag to handleTagAutocomplete', async () => {
    const spy = vi.spyOn(tagHandler, 'handleTagAutocomplete').mockResolvedValue(undefined);
    const interaction: any = {
      guildId: 'guild-1',
      isAutocomplete: () => true,
      commandName: 'tag',
      options: {
        getFocused: vi.fn().mockReturnValue('he'),
      },
      respond: vi.fn().mockResolvedValue(undefined),
    };

    await handleInteraction(mockPort, mockDeps, interaction);
    expect(spy).toHaveBeenCalledWith(mockDeps.db, interaction);
    spy.mockRestore();
  });

  it('routes command tickets subcommand delete-my-data to handleDeleteMyData', async () => {
    const spy = vi.spyOn(dataHandler, 'handleDeleteMyData').mockResolvedValue(undefined);
    const interaction: any = {
      guildId: 'guild-1',
      isChatInputCommand: () => true,
      commandName: 'tickets',
      options: {
        getSubcommand: vi.fn().mockReturnValue('delete-my-data'),
      },
    };

    await handleInteraction(mockPort, mockDeps, interaction);
    expect(spy).toHaveBeenCalledWith(mockPort, mockDeps.db, interaction, mockDeps);
    spy.mockRestore();
  });
});
