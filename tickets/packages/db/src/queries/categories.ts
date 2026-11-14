import { and, eq, count, asc } from 'drizzle-orm';
import type { TicketsDb } from '../index.js';
import { categories, tickets } from '../schema.js';
import { inGuild } from '../index.js';
import { TicketError } from './errors.js';

export interface CreateCategoryInput {
  name: string;
  emoji?: string | null;
  staff_role_ids?: string[];
  staffRoleIds?: string[];
  mode?: string;
  parent_channel_id?: string;
  parentChannelId?: string;
  name_template?: string;
  nameTemplate?: string;
  welcome_message?: string | null;
  welcomeMessage?: string | null;
  form?: any[] | null;
  auto_close_hours?: number | null;
  autoCloseHours?: number | null;
  max_open_per_user?: number;
  maxOpenPerUser?: number;
  game_server_id?: string | null;
  gameServerId?: string | null;
}

export async function listCategories(db: TicketsDb, guildId: string) {
  return await db
    .select()
    .from(categories)
    .where(inGuild(categories, guildId))
    .orderBy(asc(categories.created_at));
}

export async function getCategory(db: TicketsDb, guildId: string, id: string) {
  const rows = await db
    .select()
    .from(categories)
    .where(and(eq(categories.id, id), inGuild(categories, guildId)))
    .limit(1);

  if (rows.length === 0) {
    throw new TicketError('not_found', `Category ${id} not found in guild ${guildId}`);
  }
  return rows[0];
}

export async function createCategory(
  db: TicketsDb,
  guildId: string,
  input: CreateCategoryInput,
) {
  const [created] = await db
    .insert(categories)
    .values({
      guild_id: guildId,
      name: input.name,
      emoji: input.emoji ?? null,
      staff_role_ids: input.staff_role_ids ?? input.staffRoleIds ?? [],
      mode: input.mode ?? 'thread',
      parent_channel_id: input.parent_channel_id ?? input.parentChannelId ?? '',
      name_template: input.name_template ?? input.nameTemplate ?? 'ticket-{number}',
      welcome_message: input.welcome_message ?? input.welcomeMessage ?? null,
      form: input.form ?? null,
      auto_close_hours: input.auto_close_hours ?? input.autoCloseHours ?? null,
      max_open_per_user: input.max_open_per_user ?? input.maxOpenPerUser ?? 1,
      game_server_id: input.game_server_id ?? input.gameServerId ?? null,
    })
    .returning();

  return created;
}

export type UpdateCategoryPatch = Partial<CreateCategoryInput>;

export async function updateCategory(
  db: TicketsDb,
  guildId: string,
  id: string,
  patch: UpdateCategoryPatch,
) {
  await getCategory(db, guildId, id);

  const updateData: Partial<typeof categories.$inferInsert> = {};
  if (patch.name !== undefined) updateData.name = patch.name;
  if (patch.emoji !== undefined) updateData.emoji = patch.emoji;
  if (patch.staff_role_ids !== undefined) updateData.staff_role_ids = patch.staff_role_ids;
  else if (patch.staffRoleIds !== undefined) updateData.staff_role_ids = patch.staffRoleIds;
  if (patch.mode !== undefined) updateData.mode = patch.mode;
  if (patch.parent_channel_id !== undefined) updateData.parent_channel_id = patch.parent_channel_id;
  else if (patch.parentChannelId !== undefined) updateData.parent_channel_id = patch.parentChannelId;
  if (patch.name_template !== undefined) updateData.name_template = patch.name_template;
  else if (patch.nameTemplate !== undefined) updateData.name_template = patch.nameTemplate;
  if (patch.welcome_message !== undefined) updateData.welcome_message = patch.welcome_message;
  else if (patch.welcomeMessage !== undefined) updateData.welcome_message = patch.welcomeMessage;
  if (patch.form !== undefined) updateData.form = patch.form;
  if (patch.auto_close_hours !== undefined) updateData.auto_close_hours = patch.auto_close_hours;
  else if (patch.autoCloseHours !== undefined) updateData.auto_close_hours = patch.autoCloseHours;
  if (patch.max_open_per_user !== undefined) updateData.max_open_per_user = patch.max_open_per_user;
  else if (patch.maxOpenPerUser !== undefined) updateData.max_open_per_user = patch.maxOpenPerUser;
  if (patch.game_server_id !== undefined) updateData.game_server_id = patch.game_server_id;
  else if (patch.gameServerId !== undefined) updateData.game_server_id = patch.gameServerId;

  if (Object.keys(updateData).length === 0) {
    return await getCategory(db, guildId, id);
  }

  const rows = await db
    .update(categories)
    .set(updateData)
    .where(and(eq(categories.id, id), inGuild(categories, guildId)))
    .returning();

  return rows[0];
}

export async function deleteCategory(db: TicketsDb, guildId: string, id: string) {
  // Throws TicketError('not_found') for another guild's id
  await getCategory(db, guildId, id);

  // Refuses delete while tickets reference it -> code limit
  const ticketCountRes = await db
    .select({ count: count() })
    .from(tickets)
    .where(and(eq(tickets.category_id, id), inGuild(tickets, guildId)));

  if (Number(ticketCountRes[0]?.count ?? 0) > 0) {
    throw new TicketError('limit', `Cannot delete category ${id} while tickets reference it`);
  }

  try {
    await db
      .delete(categories)
      .where(and(eq(categories.id, id), inGuild(categories, guildId)));
  } catch (err: any) {
    if (err?.code === '23503') {
      throw new TicketError('limit', `Cannot delete category ${id} while tickets reference it`);
    }
    throw err;
  }
}
