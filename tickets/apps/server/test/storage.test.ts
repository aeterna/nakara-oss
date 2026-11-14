import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createStorage } from '../src/storage.js';

describe('Storage driver (acceptance test t1)', () => {
  const testKey = Buffer.alloc(32, 7);
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'tickets-storage-test-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it('t1: local put/get round trip, stored bytes != plain, ../ key rejected', async () => {
    const storage = createStorage({
      STORAGE_DIR: tempDir,
      TICKETS_DATA_KEY: testKey,
    });

    const key = 'guild1/ticket1/file1';
    const plain = Buffer.from('hello attachment world 12345');
    const contentType = 'image/png';

    // 1. Put
    await storage.put(key, plain, contentType);

    // 2. Check stored bytes on disk != plain (encrypted/sealed)
    const diskPath = join(tempDir, key);
    expect(existsSync(diskPath)).toBe(true);
    const rawDiskBytes = readFileSync(diskPath);
    expect(rawDiskBytes.equals(plain)).toBe(false);

    // 3. Get round trip returns original plain bytes and content type
    const retrieved = await storage.get(key);
    expect(retrieved).not.toBeNull();
    expect(retrieved!.bytes.equals(plain)).toBe(true);
    expect(retrieved!.contentType).toBe(contentType);

    // 4. Reject ../ path traversal keys
    await expect(storage.put('../evil/file', plain, contentType)).rejects.toThrow();
    await expect(storage.get('../evil/file')).rejects.toThrow();
    await expect(storage.put('guild1/../../etc/passwd', plain, contentType)).rejects.toThrow();

    // 5. Delete removes the file
    await storage.delete(key);
    const afterDelete = await storage.get(key);
    expect(afterDelete).toBeNull();
  });

  it('t1: S3 driver signs a PUT with Authorization AWS4-HMAC-SHA256', async () => {
    const originalEnv = { ...process.env };
    process.env.S3_ENDPOINT = 'https://s3.us-east-1.amazonaws.com';
    process.env.S3_BUCKET = 'test-bucket';
    process.env.S3_REGION = 'us-east-1';
    process.env.S3_ACCESS_KEY_ID = 'test-access-key-id';
    process.env.S3_SECRET_ACCESS_KEY = 'test-secret-access-key-12345';

    let capturedHeaders: Headers | Record<string, string> | undefined;
    let capturedMethod: string | undefined;

    const mockFetch = vi.fn().mockImplementation(async (input: any, init?: any) => {
      if (typeof input === 'object' && input.headers) {
        capturedHeaders = input.headers;
        capturedMethod = input.method;
      } else if (init) {
        capturedHeaders = init.headers;
        capturedMethod = init.method;
      }
      return {
        ok: true,
        status: 200,
        statusText: 'OK',
        headers: new Headers({ 'Content-Type': 'application/octet-stream' }),
        arrayBuffer: async () => new ArrayBuffer(0),
      };
    });

    vi.stubGlobal('fetch', mockFetch);

    try {
      const storage = createStorage({
        TICKETS_DATA_KEY: testKey,
      });

      const key = 'guild1/ticket1/file-s3';
      const plain = Buffer.from('s3 file content');

      await storage.put(key, plain, 'text/plain');

      expect(mockFetch).toHaveBeenCalled();
      expect(capturedMethod).toBe('PUT');

      // Check Authorization header has AWS4-HMAC-SHA256
      let authHeader: string | null = null;
      if (capturedHeaders instanceof Headers) {
        authHeader = capturedHeaders.get('Authorization');
      } else if (capturedHeaders && typeof capturedHeaders === 'object') {
        authHeader = (capturedHeaders as any)['Authorization'] || (capturedHeaders as any)['authorization'];
      }

      expect(authHeader).toBeDefined();
      expect(authHeader).toMatch(/^AWS4-HMAC-SHA256/);
    } finally {
      process.env = originalEnv;
    }
  });
});
