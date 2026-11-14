import { describe, it, expect, vi, beforeAll, beforeEach, afterAll } from 'vitest';
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
});
