import { readFileSync, existsSync, promises as fs } from 'node:fs';
import { join, dirname, resolve, isAbsolute, sep } from 'node:path';
import { AwsClient } from 'aws4fetch';
import { sealBytes, openBytes, parseDataKey } from '@nakara-tickets/core';

export interface StorageItem {
  bytes: Buffer;
  contentType: string;
}

export interface Storage {
  put(key: string, bytes: Buffer | Uint8Array, contentType?: string | null): Promise<void>;
  get(key: string): Promise<StorageItem | null>;
  delete(key: string): Promise<void>;
  usedBytes?(prefix?: string): Promise<number>;
}

export interface StorageConfig {
  STORAGE_DIR?: string;
  TICKETS_DATA_KEY?: Buffer;
  [key: string]: any;
}

function getEnvValue(name: string, env: Record<string, string | undefined> = process.env): string | undefined {
  const direct = env[name];
  if (direct !== undefined && direct !== '') {
    return direct;
  }
  const fileKey = `${name}_FILE`;
  const filePath = env[fileKey];
  if (filePath !== undefined && filePath !== '') {
    try {
      return readFileSync(filePath, 'utf8').trim();
    } catch {
      return undefined;
    }
  }
  return undefined;
}

function validateKey(key: string, baseDir?: string): void {
  if (typeof key !== 'string' || key.trim() === '') {
    throw new Error('Key must be a non-empty string');
  }
  if (key.includes('..') || key.startsWith('/') || key.startsWith('\\') || isAbsolute(key)) {
    throw new Error('Invalid storage key: path traversal not allowed');
  }
  const parts = key.split('/');
  for (const part of parts) {
    if (!part || part === '.' || part === '..') {
      throw new Error(`Invalid storage key segment: ${part}`);
    }
  }
  if (baseDir) {
    const full = resolve(baseDir, key);
    const resolvedBase = resolve(baseDir);
    if (!full.startsWith(resolvedBase + sep) && full !== resolvedBase) {
      throw new Error('Invalid storage key: path resolves outside base directory');
    }
  }
}

export function createStorage(config?: StorageConfig | null): Storage {
  let dataKey: Buffer | undefined = config?.TICKETS_DATA_KEY ?? (config as any)?.dataKey;
  if (!dataKey) {
    const rawKey = getEnvValue('TICKETS_DATA_KEY');
    if (rawKey) {
      dataKey = parseDataKey(rawKey);
    }
  }
  if (!dataKey) {
    throw new Error('TICKETS_DATA_KEY is required for storage encryption');
  }

  const s3Bucket = getEnvValue('S3_BUCKET');
  const s3AccessKeyId = getEnvValue('S3_ACCESS_KEY_ID');
  const s3SecretAccessKey = getEnvValue('S3_SECRET_ACCESS_KEY');
  const s3Endpoint = getEnvValue('S3_ENDPOINT');
  const s3Region = getEnvValue('S3_REGION') || 'us-east-1';

  const isS3 = Boolean(s3Bucket && s3AccessKeyId && s3SecretAccessKey);

  if (isS3) {
    const aws = new AwsClient({
      accessKeyId: s3AccessKeyId!,
      secretAccessKey: s3SecretAccessKey!,
      region: s3Region,
      service: 's3',
    });

    const getS3Url = (key: string): string => {
      if (s3Endpoint) {
        const base = s3Endpoint.replace(/\/+$/, '');
        return `${base}/${s3Bucket}/${key}`;
      }
      return `https://${s3Bucket}.s3.${s3Region}.amazonaws.com/${key}`;
    };

    return {
      async put(key: string, bytes: Buffer | Uint8Array, contentType?: string | null): Promise<void> {
        validateKey(key);
        const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
        const sealed = sealBytes(dataKey!, buf);
        const ct = contentType || 'application/octet-stream';
        const url = getS3Url(key);

        const res = await aws.fetch(url, {
          method: 'PUT',
          headers: {
            'Content-Type': ct,
            'x-amz-meta-content-type': ct,
          },
          body: sealed,
        });

        if (!res.ok) {
          throw new Error(`S3 PUT failed with status ${res.status}: ${res.statusText}`);
        }
      },

      async get(key: string): Promise<StorageItem | null> {
        validateKey(key);
        const url = getS3Url(key);
        const res = await aws.fetch(url, { method: 'GET' });

        if (res.status === 404) {
          return null;
        }
        if (!res.ok) {
          throw new Error(`S3 GET failed with status ${res.status}: ${res.statusText}`);
        }

        const sealed = Buffer.from(await res.arrayBuffer());
        const plain = openBytes(dataKey!, sealed);
        const ct =
          res.headers.get('x-amz-meta-content-type') ||
          res.headers.get('content-type') ||
          'application/octet-stream';

        return {
          bytes: plain,
          contentType: ct,
        };
      },

      async delete(key: string): Promise<void> {
        validateKey(key);
        const url = getS3Url(key);
        const res = await aws.fetch(url, { method: 'DELETE' });
        if (!res.ok && res.status !== 404) {
          throw new Error(`S3 DELETE failed with status ${res.status}: ${res.statusText}`);
        }
      },

      async usedBytes(): Promise<number> {
        return 0;
      },
    };
  }

  // Local storage driver
  const storageDir = config?.STORAGE_DIR ?? getEnvValue('STORAGE_DIR') ?? './storage';

  return {
    async put(key: string, bytes: Buffer | Uint8Array, contentType?: string | null): Promise<void> {
      validateKey(key, storageDir);
      const filePath = join(storageDir, key);
      const metaPath = join(storageDir, `${key}.meta.json`);

      await fs.mkdir(dirname(filePath), { recursive: true });

      const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
      const sealed = sealBytes(dataKey!, buf);
      await fs.writeFile(filePath, sealed);

      const ct = contentType || 'application/octet-stream';
      await fs.writeFile(metaPath, JSON.stringify({ contentType: ct }), 'utf8');
    },

    async get(key: string): Promise<StorageItem | null> {
      validateKey(key, storageDir);
      const filePath = join(storageDir, key);
      const metaPath = join(storageDir, `${key}.meta.json`);

      if (!existsSync(filePath)) {
        return null;
      }

      const sealed = await fs.readFile(filePath);
      const plain = openBytes(dataKey!, sealed);

      let ct = 'application/octet-stream';
      if (existsSync(metaPath)) {
        try {
          const metaJson = JSON.parse(await fs.readFile(metaPath, 'utf8'));
          if (metaJson.contentType) {
            ct = metaJson.contentType;
          }
        } catch {
          // ignore corrupted metadata
        }
      }

      return {
        bytes: plain,
        contentType: ct,
      };
    },

    async delete(key: string): Promise<void> {
      validateKey(key, storageDir);
      const filePath = join(storageDir, key);
      const metaPath = join(storageDir, `${key}.meta.json`);

      if (existsSync(filePath)) {
        await fs.unlink(filePath);
      }
      if (existsSync(metaPath)) {
        await fs.unlink(metaPath);
      }
    },

    async usedBytes(prefix?: string): Promise<number> {
      const targetDir = prefix ? join(storageDir, prefix) : storageDir;
      if (!existsSync(targetDir)) {
        return 0;
      }

      let total = 0;
      async function walk(dir: string) {
        const entries = await fs.readdir(dir, { withFileTypes: true });
        for (const entry of entries) {
          const fullPath = join(dir, entry.name);
          if (entry.isDirectory()) {
            await walk(fullPath);
          } else if (entry.isFile() && !entry.name.endsWith('.meta.json')) {
            const stat = await fs.stat(fullPath);
            total += stat.size;
          }
        }
      }

      await walk(targetDir);
      return total;
    },
  };
}
