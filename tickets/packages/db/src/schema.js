import { pgTable, pgEnum, text, integer, boolean, timestamp, uuid, jsonb, customType, primaryKey, index, uniqueIndex, } from 'drizzle-orm/pg-core';
export const bytea = customType({
    dataType() {
        return 'bytea';
    },
    fromDriver: (v) => Buffer.from(v),
    toDriver: (v) => v,
});
export const ticketStatusEnum = pgEnum('ticket_status', ['open', 'claimed', 'closed']);
export const gameActionStatusEnum = pgEnum('game_action_status', [
    'queued',
    'leased',
    'done',
    'failed',
    'expired',
]);
export const guilds = pgTable('guilds', {
    guild_id: text('guild_id').primaryKey(),
    name: text('name').notNull(),
    icon: text('icon'),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const guildSettings = pgTable('guild_settings', {
    guild_id: text('guild_id').primaryKey().references(() => guilds.guild_id, { onDelete: 'cascade' }),
    locale: text('locale').notNull().default('th'),
    retention_days: integer('retention_days').notNull().default(90),
    log_channel_id: text('log_channel_id'),
    rating_dm: boolean('rating_dm').notNull().default(false),
    privacy_policy_url: text('privacy_policy_url'),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const gameServers = pgTable('game_servers', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    name: text('name').notNull(),
    secret_enc: bytea('secret_enc').notNull(),
    confirmed: boolean('confirmed').notNull().default(false),
    edition: text('edition'),
    resource_version: text('resource_version'),
    protocol: integer('protocol').notNull().default(1),
    players_online: integer('players_online').default(0),
    last_seen_at: timestamp('last_seen_at', { withTimezone: true }),
    revoked: boolean('revoked').notNull().default(false),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const categories = pgTable('categories', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    name: text('name').notNull(),
    emoji: text('emoji'),
    staff_role_ids: jsonb('staff_role_ids').$type().notNull().default([]),
    mode: text('mode').notNull().default('thread'),
    parent_channel_id: text('parent_channel_id').notNull(),
    name_template: text('name_template').notNull().default('ticket-{number}'),
    welcome_message: text('welcome_message'),
    form: jsonb('form').$type(),
    auto_close_hours: integer('auto_close_hours'),
    max_open_per_user: integer('max_open_per_user').notNull().default(1),
    game_server_id: uuid('game_server_id').references(() => gameServers.id, { onDelete: 'set null' }),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const panels = pgTable('panels', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    channel_id: text('channel_id').notNull(),
    message_id: text('message_id'),
    embed: jsonb('embed').notNull(),
    kind: text('kind').notNull(),
    buttons: jsonb('buttons').notNull(),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const tickets = pgTable('tickets', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    number: integer('number').notNull(),
    category_id: uuid('category_id').notNull().references(() => categories.id, { onDelete: 'restrict' }),
    status: ticketStatusEnum('status').notNull().default('open'),
    opener_id: text('opener_id').notNull(),
    claimer_id: text('claimer_id'),
    channel_id: text('channel_id').notNull(),
    answers: jsonb('answers'),
    first_response_at: timestamp('first_response_at', { withTimezone: true }),
    last_activity_at: timestamp('last_activity_at', { withTimezone: true }),
    closed_at: timestamp('closed_at', { withTimezone: true }),
    close_reason: text('close_reason'),
    reopened_count: integer('reopened_count').notNull().default(0),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    uniqueIndex('tickets_guild_id_number_idx').on(t.guild_id, t.number),
    index('tickets_guild_id_status_idx').on(t.guild_id, t.status),
]);
export const ticketMembers = pgTable('ticket_members', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    ticket_id: uuid('ticket_id').notNull().references(() => tickets.id, { onDelete: 'cascade' }),
    user_id: text('user_id').notNull(),
    role: text('role').notNull().default('member'),
    joined_at: timestamp('joined_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    uniqueIndex('ticket_members_ticket_id_user_id_idx').on(t.ticket_id, t.user_id),
]);
export const messages = pgTable('messages', {
    id: text('id').primaryKey(),
    guild_id: text('guild_id').notNull(),
    ticket_id: uuid('ticket_id').notNull().references(() => tickets.id, { onDelete: 'cascade' }),
    author_id: text('author_id').notNull(),
    author_name: text('author_name').notNull(),
    is_staff: boolean('is_staff').notNull().default(false),
    is_system: boolean('is_system').notNull().default(false),
    content_enc: bytea('content_enc').notNull(),
    edited_at: timestamp('edited_at', { withTimezone: true }),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    index('messages_ticket_id_idx').on(t.ticket_id),
]);
export const attachments = pgTable('attachments', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    ticket_id: uuid('ticket_id').notNull().references(() => tickets.id, { onDelete: 'cascade' }),
    message_id: text('message_id'),
    filename: text('filename').notNull(),
    content_type: text('content_type'),
    size: integer('size').notNull(),
    sha256: text('sha256').notNull(),
    stored: boolean('stored').notNull().default(false),
    storage_key: text('storage_key'),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const ratings = pgTable('ratings', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    ticket_id: uuid('ticket_id').notNull().references(() => tickets.id, { onDelete: 'cascade' }),
    user_id: text('user_id').notNull(),
    staff_id: text('staff_id'),
    score: integer('score').notNull(),
    feedback: text('feedback'),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    uniqueIndex('ratings_ticket_id_user_id_idx').on(t.ticket_id, t.user_id),
]);
export const tags = pgTable('tags', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    name: text('name').notNull(),
    body: text('body').notNull(),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    uniqueIndex('tags_guild_id_name_idx').on(t.guild_id, t.name),
]);
export const blocks = pgTable('blocks', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    user_id: text('user_id').notNull(),
    reason: text('reason'),
    created_by: text('created_by').notNull(),
    expires_at: timestamp('expires_at', { withTimezone: true }),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    uniqueIndex('blocks_guild_id_user_id_idx').on(t.guild_id, t.user_id),
]);
export const pairCodes = pgTable('pair_codes', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    code_hash: text('code_hash').notNull(),
    server_name: text('server_name'),
    expires_at: timestamp('expires_at', { withTimezone: true }).notNull(),
    used_at: timestamp('used_at', { withTimezone: true }),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    uniqueIndex('pair_codes_code_hash_idx').on(t.code_hash),
]);
export const bridgeNonces = pgTable('bridge_nonces', {
    server_id: uuid('server_id').notNull().references(() => gameServers.id, { onDelete: 'cascade' }),
    nonce: text('nonce').notNull(),
    expires_at: timestamp('expires_at', { withTimezone: true }).notNull(),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    primaryKey({ columns: [t.server_id, t.nonce] }),
    index('bridge_nonces_expires_at_idx').on(t.expires_at),
]);
export const gameActions = pgTable('game_actions', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    ticket_id: uuid('ticket_id').notNull().references(() => tickets.id, { onDelete: 'cascade' }),
    server_id: uuid('server_id').notNull().references(() => gameServers.id, { onDelete: 'cascade' }),
    action: text('action').notNull(),
    params: jsonb('params'),
    status: gameActionStatusEnum('status').notNull().default('queued'),
    requested_by: text('requested_by').notNull(),
    lease_until: timestamp('lease_until', { withTimezone: true }),
    expires_at: timestamp('expires_at', { withTimezone: true }).notNull(),
    result: jsonb('result'),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    index('game_actions_server_id_status_idx').on(t.server_id, t.status),
]);
export const dataRequests = pgTable('data_requests', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    user_id: text('user_id'),
    kind: text('kind').notNull(),
    status: text('status').notNull().default('pending'),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const auditLog = pgTable('audit_log', {
    id: uuid('id').defaultRandom().primaryKey(),
    guild_id: text('guild_id').notNull(),
    actor_id: text('actor_id').notNull(),
    kind: text('kind').notNull(),
    target: text('target'),
    detail: jsonb('detail'),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});
export const sessions = pgTable('sessions', {
    id: uuid('id').defaultRandom().primaryKey(),
    user_id: text('user_id').notNull(),
    token_hash: text('token_hash').notNull(),
    csrf_hash: text('csrf_hash').notNull(),
    expires_at: timestamp('expires_at', { withTimezone: true }).notNull(),
    created_at: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (t) => [
    uniqueIndex('sessions_token_hash_idx').on(t.token_hash),
]);
//# sourceMappingURL=schema.js.map