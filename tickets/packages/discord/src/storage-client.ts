import { readFileSync, promises as fs } from 'node:fs';
import { join, dirname, resolve, isAbsolute, sep } from 'node:path';
import { AwsClient } from 'aws4fetch';
import { sealBytes } from '@nakara-tickets/core';

export interface StorageClient {
  put(key: string, bytes: Buffer | Uint8Array, contentType?: string | null): Promise<void>;
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

export function createStorageClient(dataKey: Buffer): StorageClient {
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
        const sealed = sealBytes(dataKey, buf);
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
    };
  }

  // Local storage
  const storageDir = getEnvValue('STORAGE_DIR') ?? './storage';

  return {
    async put(key: string, bytes: Buffer | Uint8Array, contentType?: string | null): Promise<void> {
      validateKey(key, storageDir);
      const filePath = join(storageDir, key);
      const metaPath = join(storageDir, `${key}.meta.json`);

      await fs.mkdir(dirname(filePath), { recursive: true });

      const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
      const sealed = sealBytes(dataKey, buf);
      await fs.writeFile(filePath, sealed);

      const ct = contentType || 'application/octet-stream';
      await fs.writeFile(metaPath, JSON.stringify({ contentType: ct }), 'utf8');
    },
  };
}
