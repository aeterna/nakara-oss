import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

const VERSION = 1;
const IV_LENGTH = 12;
const TAG_LENGTH = 16;
const HEADER_LENGTH = 1 + IV_LENGTH + TAG_LENGTH; // 29 bytes

export function sealBytes(key: Buffer, plain: Buffer): Buffer {
  if (!Buffer.isBuffer(key) || key.length !== 32) {
    throw new TypeError('Key must be a 32-byte Buffer');
  }
  if (!Buffer.isBuffer(plain)) {
    throw new TypeError('Plaintext must be a Buffer');
  }

  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(plain), cipher.final()]);
  const tag = cipher.getAuthTag();

  const out = Buffer.allocUnsafe(HEADER_LENGTH + ciphertext.length);
  out[0] = VERSION;
  iv.copy(out, 1);
  tag.copy(out, 1 + IV_LENGTH);
  ciphertext.copy(out, HEADER_LENGTH);

  return out;
}

export function openBytes(key: Buffer, sealed: Buffer): Buffer {
  if (!Buffer.isBuffer(key) || key.length !== 32) {
    throw new TypeError('Key must be a 32-byte Buffer');
  }
  if (!Buffer.isBuffer(sealed)) {
    throw new TypeError('Sealed data must be a Buffer');
  }
  if (sealed.length < HEADER_LENGTH) {
    throw new Error(`Sealed data too short: ${sealed.length} bytes (expected at least ${HEADER_LENGTH})`);
  }
  if (sealed[0] !== VERSION) {
    throw new Error(`Unsupported version: ${sealed[0]} (expected ${VERSION})`);
  }

  const iv = sealed.subarray(1, 1 + IV_LENGTH);
  const tag = sealed.subarray(1 + IV_LENGTH, HEADER_LENGTH);
  const ciphertext = sealed.subarray(HEADER_LENGTH);

  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

export function parseDataKey(b64: string): Buffer {
  if (typeof b64 !== 'string') {
    throw new TypeError('Key must be a string');
  }
  if (b64.length !== 43 && b64.length !== 44) {
    throw new Error('Key must be 43 or 44 characters of base64/base64url');
  }
  if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(b64)) {
    throw new Error('Key contains invalid base64 characters');
  }
  let std = b64.replace(/-/g, '+').replace(/_/g, '/');
  if (std.length === 43) {
    std += '=';
  }
  const buf = Buffer.from(std, 'base64');
  if (buf.length !== 32) {
    throw new Error(`Data key must be exactly 32 bytes, got ${buf.length}`);
  }
  return buf;
}
