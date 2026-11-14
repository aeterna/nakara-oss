import { describe, it, expect, vi, beforeAll, beforeEach, afterEach, afterAll } from 'vitest';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq, and } from 'drizzle-orm';
import { openTestDb } from '@nakara-tickets/db/test-support';
import { guilds, guildSettings, categories, tickets, attachments } from '@nakara-tickets/db';
import { archiveOnClose } from '../src/handlers/archive.js';
import type { CloseHookContext } from '../src/types.js';

describe('Archive on close (acceptance test t2)', () => {
  const GUILD_ID = '123456789012345678';
  const testKey = Buffer.alloc(32, 5);
  let testEnv: Awaited<ReturnType<typeof openTestDb>>;
  let testDb: any;
  let tempDir: string;

  beforeAll(async () => {
    testEnv = await openTestDb();
    testDb = testEnv.db;
  });

  afterAll(async () => {
    await testEnv.close();
  });

  beforeEach(async () => {
    await testEnv.reset();
    tempDir = mkdtempSync(join(tmpdir(), 'tickets-archive-test-'));
    process.env.STORAGE_DIR = tempDir;
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it('t2: allowed host stored, evil.example skipped, 26 MB stored=false, quota reached stored=false, archived_at set', async () => {
    // 1. Seed guild & guildSettings (with quota of 1 MB = 1048576 bytes)
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'Test Guild',
    });

    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'en',
      retention_days: 90,
      attachment_quota_mb: 1, // 1 MB quota
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'General',
      staff_role_ids: [],
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 1,
      status: 'closed',
      opener_id: '111111111111111111',
      channel_id: '888888888888888888',
    }).returning();

    // 2. Prepare mock Discord messages
    const validFile100Bytes = Buffer.alloc(100, 'A');
    const large26MB = 26 * 1024 * 1024; // 26 MB
    const quotaExceedingBytes = 1024 * 1024; // 1 MB (since quota is 1 MB and we already have 100 bytes, this exceeds 1 MB)

    const mockMessages = [
      {
        id: 'msg_1',
        attachments: [
          {
            id: 'att_valid',
            name: 'allowed.png',
            size: 100,
            url: 'https://cdn.discordapp.com/attachments/888/att_valid/allowed.png',
            contentType: 'image/png',
          },
          {
            id: 'att_evil',
            name: 'evil.exe',
            size: 50,
            url: 'https://evil.example.com/malware.exe',
            contentType: 'application/x-msdownload',
          },
        ],
      },
      {
        id: 'msg_2',
        attachments: [
          {
            id: 'att_too_large',
            name: 'big_video.mp4',
            size: large26MB,
            url: 'https://media.discordapp.net/attachments/888/att_too_large/big_video.mp4',
            contentType: 'video/mp4',
          },
          {
            id: 'att_quota_exceeded',
            name: 'medium_file.zip',
            size: quotaExceedingBytes,
            url: 'https://cdn.discordapp.com/attachments/888/att_quota/medium_file.zip',
            contentType: 'application/zip',
          },
        ],
      },
    ];

    // Mock global fetch for downloading attachments
    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
      const urlStr = String(url);
      if (urlStr.includes('allowed.png')) {
        return {
          ok: true,
          status: 200,
          headers: new Headers({ 'Content-Type': 'image/png' }),
          arrayBuffer: async () => validFile100Bytes.buffer.slice(validFile100Bytes.byteOffset, validFile100Bytes.byteOffset + validFile100Bytes.byteLength),
        };
      }
      return {
        ok: false,
        status: 404,
        arrayBuffer: async () => new ArrayBuffer(0),
      };
    }));

    // Mock CloseHookContext
    const ctx: CloseHookContext = {
      port: {
        createPrivateThread: vi.fn(),
        addMember: vi.fn(),
        sendMessage: vi.fn(),
        editMessage: vi.fn(),
        showModal: vi.fn(),
        replyEphemeral: vi.fn(),
        deferReply: vi.fn(),
        editReply: vi.fn(),
        lockAndArchiveThread: vi.fn(),
        fetchMessages: vi.fn().mockResolvedValue(mockMessages),
      } as any,
      db: testDb,
      dataKey: testKey,
      storage: { put: vi.fn().mockResolvedValue(undefined), delete: vi.fn().mockResolvedValue(undefined) },
      ticket,
      category: cat,
      guildSettings: { attachment_quota_mb: 1 },
      actorId: '111111111111111111',
      log: {
        info: vi.fn(),
        warn: vi.fn(),
        error: vi.fn(),
      },
    };

    // 3. Execute archiveOnClose
    await archiveOnClose(ctx);

    // 4. Verify tickets.archived_at is set
    const [updatedTicket] = await testDb
      .select()
      .from(tickets)
      .where(and(eq(tickets.id, ticket.id), eq(tickets.guild_id, GUILD_ID)));
    expect(updatedTicket.archived_at).not.toBeNull();

    // 5. Query attachments from DB
    const attRows = await testDb
      .select()
      .from(attachments)
      .where(eq(attachments.ticket_id, ticket.id));

    // Assert: evil.example was skipped completely (not in DB rows)
    const evilRow = attRows.find((a: any) => a.filename === 'evil.exe');
    expect(evilRow).toBeUndefined();

    // Assert: allowed.png was stored=true
    const allowedRow = attRows.find((a: any) => a.filename === 'allowed.png');
    expect(allowedRow).toBeDefined();
    expect(allowedRow.stored).toBe(true);
    expect(allowedRow.storage_key).toBeTruthy();
    expect(allowedRow.size).toBe(100);

    // Assert: big_video.mp4 (26 MB) was stored=false
    const bigRow = attRows.find((a: any) => a.filename === 'big_video.mp4');
    expect(bigRow).toBeDefined();
    expect(bigRow.stored).toBe(false);

    // Assert: medium_file.zip (quota exceeded) was stored=false
    const quotaRow = attRows.find((a: any) => a.filename === 'medium_file.zip');
    expect(quotaRow).toBeDefined();
    expect(quotaRow.stored).toBe(false);
  });

  it('SSRF blocker: redirect to evil host skipped as stored=false; valid redirect followed and stored=true', async () => {
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'SSRF Test Guild',
    });

    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'en',
      attachment_quota_mb: 50,
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 2,
      status: 'closed',
      opener_id: '111111111111111111',
      channel_id: '777777777777777777',
    }).returning();

    const validPayload = Buffer.from('hello from valid redirect target');

    const mockMessages = [
      {
        id: 'msg_ssrf',
        attachments: [
          {
            id: 'att_redir_evil',
            name: 'evil_redirect.png',
            size: 100,
            url: 'https://cdn.discordapp.com/attachments/888/att_redir/evil_redirect.png',
            contentType: 'image/png',
          },
          {
            id: 'att_redir_valid',
            name: 'valid_redirect.png',
            size: 100,
            url: 'https://cdn.discordapp.com/attachments/888/att_redir/valid_redirect.png',
            contentType: 'image/png',
          },
        ],
      },
    ];

    vi.stubGlobal('fetch', vi.fn().mockImplementation(async (url: string) => {
      const urlStr = String(url);
      if (urlStr.includes('evil_redirect.png')) {
        return {
          status: 302,
          ok: false,
          headers: new Headers({ location: 'https://evil.example.com/malware.exe' }),
        };
      }
      if (urlStr.includes('valid_redirect.png')) {
        return {
          status: 302,
          ok: false,
          headers: new Headers({ location: 'https://media.discordapp.net/attachments/888/att_redir/final.png' }),
        };
      }
      if (urlStr.includes('final.png')) {
        return {
          status: 200,
          ok: true,
          headers: new Headers({ 'content-type': 'image/png' }),
          body: new ReadableStream({
            start(controller) {
              controller.enqueue(validPayload);
              controller.close();
            },
          }),
        };
      }
      return { status: 404, ok: false };
    }));

    const ctx: CloseHookContext = {
      port: {
        createPrivateThread: vi.fn(),
        addMember: vi.fn(),
        sendMessage: vi.fn(),
        editMessage: vi.fn(),
        showModal: vi.fn(),
        replyEphemeral: vi.fn(),
        deferReply: vi.fn(),
        editReply: vi.fn(),
        lockAndArchiveThread: vi.fn(),
        fetchMessages: vi.fn().mockResolvedValue(mockMessages),
        createDM: vi.fn(),
        sendDM: vi.fn(),
      },
      db: testDb,
      dataKey: testKey,
      storage: { put: vi.fn().mockResolvedValue(undefined), delete: vi.fn().mockResolvedValue(undefined) },
      ticket,
      category: cat,
      guildSettings: { attachment_quota_mb: 50 },
      actorId: '111111111111111111',
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await archiveOnClose(ctx);

    const attRows = await testDb
      .select()
      .from(attachments)
      .where(eq(attachments.ticket_id, ticket.id));

    // Evil redirect should be skipped from storage -> stored=false
    const evilRow = attRows.find((a: any) => a.filename === 'evil_redirect.png');
    expect(evilRow).toBeDefined();
    expect(evilRow.stored).toBe(false);

    // Valid redirect to media.discordapp.net should succeed -> stored=true
    const validRow = attRows.find((a: any) => a.filename === 'valid_redirect.png');
    expect(validRow).toBeDefined();
    expect(validRow.stored).toBe(true);
    expect(validRow.size).toBe(validPayload.length);
  });

  it('Size blocker: lying size aborted at the 25 MB cap and marked stored=false', async () => {
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'Lying Size Test Guild',
    });

    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'en',
      attachment_quota_mb: 100,
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 3,
      status: 'closed',
      opener_id: '111111111111111111',
      channel_id: '666666666666666666',
    }).returning();

    const mockMessages = [
      {
        id: 'msg_lying',
        attachments: [
          {
            id: 'att_lying',
            name: 'lying.dat',
            size: 50, // Lies about size (claims 50 bytes)
            url: 'https://cdn.discordapp.com/attachments/888/att_lying/lying.dat',
            contentType: 'application/octet-stream',
          },
        ],
      },
    ];

    // Stream generates 40 MB (exceeds 25 MB cap while the stream is still open)
    const chunkSize = 1024 * 1024; // 1 MB
    const chunkCount = 40;
    let chunksSent = 0;
    let streamCancelled = false;

    vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
      return {
        status: 200,
        ok: true,
        headers: new Headers({
          'content-type': 'application/octet-stream',
          'content-length': '50', // Headers also lie
        }),
        body: new ReadableStream({
          pull(controller) {
            if (chunksSent < chunkCount) {
              chunksSent++;
              controller.enqueue(Buffer.alloc(chunkSize, 'X'));
            } else {
              controller.close();
            }
          },
          cancel() {
            streamCancelled = true;
          },
        }),
      };
    }));

    const ctx: CloseHookContext = {
      port: {
        createPrivateThread: vi.fn(),
        addMember: vi.fn(),
        sendMessage: vi.fn(),
        editMessage: vi.fn(),
        showModal: vi.fn(),
        replyEphemeral: vi.fn(),
        deferReply: vi.fn(),
        editReply: vi.fn(),
        lockAndArchiveThread: vi.fn(),
        fetchMessages: vi.fn().mockResolvedValue(mockMessages),
        createDM: vi.fn(),
        sendDM: vi.fn(),
      },
      db: testDb,
      dataKey: testKey,
      storage: { put: vi.fn().mockResolvedValue(undefined), delete: vi.fn().mockResolvedValue(undefined) },
      ticket,
      category: cat,
      guildSettings: { attachment_quota_mb: 100 },
      actorId: '111111111111111111',
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await archiveOnClose(ctx);

    const attRows = await testDb
      .select()
      .from(attachments)
      .where(eq(attachments.ticket_id, ticket.id));

    const lyingRow = attRows.find((a: any) => a.filename === 'lying.dat');
    expect(lyingRow).toBeDefined();
    expect(lyingRow.stored).toBe(false);
    expect(lyingRow.storage_key).toBeNull();
    // Reader should have been cancelled when cap was exceeded
    expect(streamCancelled).toBe(true);
  });

  it('StoragePort: uses ctx.storage when provided instead of storage-client', async () => {
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'StoragePort Test Guild',
    });

    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'en',
      attachment_quota_mb: 50,
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 4,
      status: 'closed',
      opener_id: '111111111111111111',
      channel_id: '555555555555555555',
    }).returning();

    const mockMessages = [
      {
        id: 'msg_storage_port',
        attachments: [
          {
            id: 'att_sp',
            name: 'note.txt',
            size: 15,
            url: 'https://cdn.discordapp.com/attachments/888/att_sp/note.txt',
            contentType: 'text/plain',
          },
        ],
      },
    ];

    const noteBytes = Buffer.from('hello storage port');

    vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
      return {
        status: 200,
        ok: true,
        headers: new Headers({ 'content-type': 'text/plain' }),
        body: new ReadableStream({
          start(controller) {
            controller.enqueue(noteBytes);
            controller.close();
          },
        }),
      };
    }));

    const mockStorage = {
      put: vi.fn().mockResolvedValue(undefined),
      delete: vi.fn().mockResolvedValue(undefined),
    };

    const ctx: CloseHookContext = {
      port: {
        createPrivateThread: vi.fn(),
        addMember: vi.fn(),
        sendMessage: vi.fn(),
        editMessage: vi.fn(),
        showModal: vi.fn(),
        replyEphemeral: vi.fn(),
        deferReply: vi.fn(),
        editReply: vi.fn(),
        lockAndArchiveThread: vi.fn(),
        fetchMessages: vi.fn().mockResolvedValue(mockMessages),
        createDM: vi.fn(),
        sendDM: vi.fn(),
      },
      db: testDb,
      dataKey: testKey,
      storage: mockStorage,
      ticket,
      category: cat,
      guildSettings: { attachment_quota_mb: 50 },
      actorId: '111111111111111111',
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await archiveOnClose(ctx);

    expect(mockStorage.put).toHaveBeenCalledTimes(1);
    const [key, bytes, ct] = mockStorage.put.mock.calls[0];
    expect(key).toBe(`${GUILD_ID}/${ticket.id}/` + (mockStorage.put.mock.calls[0][0].split('/')[2]));
    expect(Buffer.isBuffer(bytes)).toBe(true);
    expect(bytes.toString()).toBe('hello storage port');
    expect(ct).toBe('text/plain');

    const attRows = await testDb
      .select()
      .from(attachments)
      .where(eq(attachments.ticket_id, ticket.id));

    const spRow = attRows.find((a: any) => a.filename === 'note.txt');
    expect(spRow).toBeDefined();
    expect(spRow.stored).toBe(true);
  });

  it('N2: an already-archived ticket (reopen + close) writes no attachment rows and fetches nothing', async () => {
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'Reopen Test Guild',
    });

    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'en',
      attachment_quota_mb: 50,
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 5,
      status: 'closed',
      opener_id: '111111111111111111',
      channel_id: '444444444444444444',
      archived_at: new Date(),
    }).returning();

    const fetchMessages = vi.fn().mockResolvedValue([
      {
        id: 'msg_reopen',
        attachments: [
          {
            id: 'att_reopen',
            name: 'again.txt',
            size: 10,
            url: 'https://cdn.discordapp.com/attachments/888/att_reopen/again.txt',
            contentType: 'text/plain',
          },
        ],
      },
    ]);
    const fetchMock = vi.fn().mockResolvedValue({
      status: 200,
      ok: true,
      headers: new Headers({ 'content-type': 'text/plain' }),
      body: new ReadableStream({
        start(controller) {
          controller.enqueue(Buffer.from('0123456789'));
          controller.close();
        },
      }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const storage = { put: vi.fn().mockResolvedValue(undefined), delete: vi.fn().mockResolvedValue(undefined) };

    const ctx: CloseHookContext = {
      port: {
        createPrivateThread: vi.fn(),
        addMember: vi.fn(),
        sendMessage: vi.fn(),
        editMessage: vi.fn(),
        showModal: vi.fn(),
        replyEphemeral: vi.fn(),
        deferReply: vi.fn(),
        editReply: vi.fn(),
        lockAndArchiveThread: vi.fn(),
        fetchMessages,
        createDM: vi.fn(),
        sendDM: vi.fn(),
      } as any,
      db: testDb,
      dataKey: testKey,
      storage,
      ticket,
      category: cat,
      guildSettings: { attachment_quota_mb: 50 },
      actorId: '111111111111111111',
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await archiveOnClose(ctx);

    expect(fetchMessages).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
    expect(storage.put).not.toHaveBeenCalled();

    const attRows = await testDb
      .select()
      .from(attachments)
      .where(eq(attachments.ticket_id, ticket.id));
    expect(attRows).toHaveLength(0);
  });

  it('item 4: without ctx.storage, attachments are recorded stored=false, a warning is logged, and nothing is written to disk', async () => {
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'No Storage Guild',
    });

    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'en',
      attachment_quota_mb: 50,
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 6,
      status: 'closed',
      opener_id: '111111111111111111',
      channel_id: '333333333333333333',
    }).returning();

    const mockMessages = [
      {
        id: 'msg_nostore',
        attachments: [
          {
            id: 'att_nostore',
            name: 'kept.txt',
            size: 100,
            url: 'https://cdn.discordapp.com/attachments/888/att_nostore/kept.txt',
            contentType: 'text/plain',
          },
        ],
      },
    ];

    const fetchMock = vi.fn().mockResolvedValue({
      status: 200,
      ok: true,
      headers: new Headers({ 'content-type': 'text/plain' }),
      body: new ReadableStream({
        start(controller) {
          controller.enqueue(Buffer.alloc(100, 'B'));
          controller.close();
        },
      }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

    const ctx: CloseHookContext = {
      port: {
        createPrivateThread: vi.fn(),
        addMember: vi.fn(),
        sendMessage: vi.fn(),
        editMessage: vi.fn(),
        showModal: vi.fn(),
        replyEphemeral: vi.fn(),
        deferReply: vi.fn(),
        editReply: vi.fn(),
        lockAndArchiveThread: vi.fn(),
        fetchMessages: vi.fn().mockResolvedValue(mockMessages),
        createDM: vi.fn(),
        sendDM: vi.fn(),
      } as any,
      db: testDb,
      dataKey: testKey,
      ticket,
      category: cat,
      guildSettings: { attachment_quota_mb: 50 },
      actorId: '111111111111111111',
      log,
    };

    await archiveOnClose(ctx);

    expect(log.warn).toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();

    const attRows = await testDb
      .select()
      .from(attachments)
      .where(eq(attachments.ticket_id, ticket.id));
    const keptRow = attRows.find((a: any) => a.filename === 'kept.txt');
    expect(keptRow).toBeDefined();
    expect(keptRow.stored).toBe(false);
    expect(keptRow.storage_key).toBeNull();

    // The archive still completes: the ticket is marked archived
    const [updatedTicket] = await testDb
      .select()
      .from(tickets)
      .where(and(eq(tickets.id, ticket.id), eq(tickets.guild_id, GUILD_ID)));
    expect(updatedTicket.archived_at).not.toBeNull();
  });

  it('N3: when the attachment row insert fails after storage.put, the stored object is deleted and no stored=true row remains', async () => {
    await testDb.insert(guilds).values({
      guild_id: GUILD_ID,
      name: 'Orphan Test Guild',
    });

    await testDb.insert(guildSettings).values({
      guild_id: GUILD_ID,
      locale: 'en',
      attachment_quota_mb: 50,
    });

    const [cat] = await testDb.insert(categories).values({
      guild_id: GUILD_ID,
      name: 'Support',
      mode: 'thread',
      parent_channel_id: '999999999999999999',
    }).returning();

    const [ticket] = await testDb.insert(tickets).values({
      guild_id: GUILD_ID,
      category_id: cat.id,
      number: 7,
      status: 'closed',
      opener_id: '111111111111111111',
      channel_id: '222222222222222222',
    }).returning();

    const mockMessages = [
      {
        id: 'msg_orphan',
        attachments: [
          {
            id: 'att_orphan',
            name: 'orphan.txt',
            size: 12,
            url: 'https://cdn.discordapp.com/attachments/888/att_orphan/orphan.txt',
            contentType: 'text/plain',
          },
        ],
      },
    ];

    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      status: 200,
      ok: true,
      headers: new Headers({ 'content-type': 'text/plain' }),
      body: new ReadableStream({
        start(controller) {
          controller.enqueue(Buffer.from('orphan bytes'));
          controller.close();
        },
      }),
    }));

    // Database wrapper: the stored=true attachment insert fails, everything else passes through
    const failingDb = new Proxy(testDb, {
      get(target, prop, receiver) {
        if (prop === 'insert') {
          return (table: unknown) => {
            if (table !== attachments) return target.insert(table as any);
            return {
              values: (row: any) =>
                row.stored
                  ? Promise.reject(new Error('simulated insert failure'))
                  : target.insert(table as any).values(row),
            };
          };
        }
        const value = Reflect.get(target, prop, receiver);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });

    const storage = {
      put: vi.fn().mockResolvedValue(undefined),
      delete: vi.fn().mockResolvedValue(undefined),
    };

    const ctx: CloseHookContext = {
      port: {
        createPrivateThread: vi.fn(),
        addMember: vi.fn(),
        sendMessage: vi.fn(),
        editMessage: vi.fn(),
        showModal: vi.fn(),
        replyEphemeral: vi.fn(),
        deferReply: vi.fn(),
        editReply: vi.fn(),
        lockAndArchiveThread: vi.fn(),
        fetchMessages: vi.fn().mockResolvedValue(mockMessages),
        createDM: vi.fn(),
        sendDM: vi.fn(),
      } as any,
      db: failingDb as any,
      dataKey: testKey,
      storage,
      ticket,
      category: cat,
      guildSettings: { attachment_quota_mb: 50 },
      actorId: '111111111111111111',
      log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    };

    await archiveOnClose(ctx);

    expect(storage.put).toHaveBeenCalledTimes(1);
    const putKey = storage.put.mock.calls[0][0];
    expect(storage.delete).toHaveBeenCalledTimes(1);
    expect(storage.delete).toHaveBeenCalledWith(putKey);

    const attRows = await testDb
      .select()
      .from(attachments)
      .where(eq(attachments.ticket_id, ticket.id));
    expect(attRows.find((a: any) => a.stored === true)).toBeUndefined();
    const orphanRow = attRows.find((a: any) => a.filename === 'orphan.txt');
    expect(orphanRow).toBeDefined();
    expect(orphanRow.stored).toBe(false);
  });
});
