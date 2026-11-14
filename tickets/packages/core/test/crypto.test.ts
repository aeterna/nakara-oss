import { describe, it, expect } from 'vitest';
import { randomBytes } from 'node:crypto';
import { sealBytes, openBytes, parseDataKey } from '../src/crypto.js';

describe('core crypto acceptance tests', () => {
  it('(k1) round trip of empty, 1 byte and 64 KiB', () => {
    const key = randomBytes(32);

    const empty = Buffer.alloc(0);
    const sealedEmpty = sealBytes(key, empty);
    expect(openBytes(key, sealedEmpty)).toEqual(empty);

    const oneByte = Buffer.from([42]);
    const sealedOneByte = sealBytes(key, oneByte);
    expect(openBytes(key, sealedOneByte)).toEqual(oneByte);

    const big = randomBytes(64 * 1024);
    const sealedBig = sealBytes(key, big);
    expect(openBytes(key, sealedBig)).toEqual(big);
  });

  it('(k2) flipping any byte of the sealed output makes openBytes throw', () => {
    const key = randomBytes(32);
    const plain = Buffer.from('roundtrip payload for testing bitflips in sealed bytes');
    const sealed = sealBytes(key, plain);

    for (let i = 0; i < sealed.length; i++) {
      const tampered = Buffer.from(sealed);
      tampered[i] ^= 0x01;
      expect(() => openBytes(key, tampered)).toThrow();
    }
  });

  it('(k3) a different key throws', () => {
    const key1 = randomBytes(32);
    const key2 = randomBytes(32);
    const plain = Buffer.from('hello authenticated encryption');
    const sealed = sealBytes(key1, plain);

    expect(() => openBytes(key2, sealed)).toThrow();
  });

  it('(k4) two seals of the same input differ', () => {
    const key = randomBytes(32);
    const plain = Buffer.from('constant plaintext message');

    const sealed1 = sealBytes(key, plain);
    const sealed2 = sealBytes(key, plain);

    expect(sealed1.equals(sealed2)).toBe(false);
  });

  it('(k5) parseDataKey rejects 31 and 33 bytes and non-base64', () => {
    // 31 bytes base64 rejected
    const key31 = randomBytes(31).toString('base64');
    expect(() => parseDataKey(key31)).toThrow();

    // 33 bytes base64 rejected
    const key33 = randomBytes(33).toString('base64');
    expect(() => parseDataKey(key33)).toThrow();

    // non-base64 rejected
    expect(() => parseDataKey('!@#$%^&*()_+~`|}{[]:;?><,./')).toThrow();
    expect(() => parseDataKey('not-valid-base64-string-here!')).toThrow();
    expect(() => parseDataKey('this has spaces inside it and is not base64')).toThrow();

    // 32 bytes valid base64 accepted
    const raw32 = randomBytes(32);
    const key32Base64 = raw32.toString('base64');
    const parsedB64 = parseDataKey(key32Base64);
    expect(parsedB64).toEqual(raw32);

    // 32 bytes valid base64url accepted
    const key32Base64Url = raw32.toString('base64url');
    const parsedB64Url = parseDataKey(key32Base64Url);
    expect(parsedB64Url).toEqual(raw32);
  });
});
