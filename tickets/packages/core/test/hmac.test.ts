import { describe, it, expect } from 'vitest';
import { bridgeCanonical, signBridge, verifyBridge, sha256hex } from '../src/hmac.js';

describe('bridge HMAC acceptance tests', () => {
  it('(h1) canonical string for a known input equals a literal expected string', () => {
    const body = '{"action":"player.info"}';
    const bodyHash = sha256hex(body);
    const parts = {
      timestamp: 1700000000,
      nonce: 'fixed-nonce-123456',
      method: 'post',
      pathWithQuery: '/api/v1/bridge/actions?limit=50',
      body,
    };

    const canonical = bridgeCanonical(parts);
    const expected = `1700000000\nfixed-nonce-123456\nPOST\n/api/v1/bridge/actions?limit=50\n${bodyHash}`;
    expect(canonical).toBe(expected);

    // Also verify with empty body and literal SHA-256 hash
    const partsEmpty = {
      timestamp: 1700000000,
      nonce: 'nonce-abc',
      method: 'GET',
      pathWithQuery: '/healthz',
      body: '',
    };
    const expectedEmpty = '1700000000\nnonce-abc\nGET\n/healthz\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    expect(bridgeCanonical(partsEmpty)).toBe(expectedEmpty);
  });

  it('(h2) sign→verify ok', () => {
    const secret = 'test-secret-key-for-bridge-hmac-32b!';
    const nowSec = 1700000000;
    const parts = {
      timestamp: nowSec,
      nonce: 'nonce-1234567890abcdef',
      method: 'POST',
      pathWithQuery: '/api/v1/bridge/heartbeat',
      body: '{"players":[]}',
    };

    const sigHex = signBridge(secret, parts);
    const result = verifyBridge(secret, parts, sigHex, nowSec);
    expect(result).toEqual({ ok: true });
  });

  it('(h3) one changed char in path, body, nonce or timestamp → signature', () => {
    const secret = 'test-secret-key-for-bridge-hmac-32b!';
    const nowSec = 1700000000;
    const parts = {
      timestamp: nowSec,
      nonce: 'nonce-1234567890abcdef',
      method: 'POST',
      pathWithQuery: '/api/v1/bridge/heartbeat',
      body: '{"players":[]}',
    };
    const sigHex = signBridge(secret, parts);

    // Changed path
    const changedPath = { ...parts, pathWithQuery: '/api/v1/bridge/heartbeat2' };
    expect(verifyBridge(secret, changedPath, sigHex, nowSec)).toEqual({ ok: false, reason: 'signature' });

    // Changed body
    const changedBody = { ...parts, body: '{"players":[{"id":1}]}' };
    expect(verifyBridge(secret, changedBody, sigHex, nowSec)).toEqual({ ok: false, reason: 'signature' });

    // Changed nonce
    const changedNonce = { ...parts, nonce: 'nonce-1234567890abcdeg' };
    expect(verifyBridge(secret, changedNonce, sigHex, nowSec)).toEqual({ ok: false, reason: 'signature' });

    // Changed timestamp by 1s (within skew window of 60s)
    const changedTimestamp = { ...parts, timestamp: nowSec + 1 };
    expect(verifyBridge(secret, changedTimestamp, sigHex, nowSec)).toEqual({ ok: false, reason: 'signature' });
  });

  it('(h4) |now−ts| = 61 → skew, 60 → ok', () => {
    const secret = 'test-secret-key-for-bridge-hmac-32b!';
    const ts = 1700000000;
    const parts = {
      timestamp: ts,
      nonce: 'nonce-skew-test-12345',
      method: 'GET',
      pathWithQuery: '/api/v1/bridge/actions',
      body: '',
    };
    const sigHex = signBridge(secret, parts);

    // now - ts = 61 -> skew
    expect(verifyBridge(secret, parts, sigHex, ts + 61)).toEqual({ ok: false, reason: 'skew' });
    // ts - now = 61 (clock in future) -> skew
    expect(verifyBridge(secret, parts, sigHex, ts - 61)).toEqual({ ok: false, reason: 'skew' });

    // now - ts = 60 -> ok
    expect(verifyBridge(secret, parts, sigHex, ts + 60)).toEqual({ ok: true });
    // ts - now = 60 -> ok
    expect(verifyBridge(secret, parts, sigHex, ts - 60)).toEqual({ ok: true });
  });

  it('(h5) non-hex or wrong-length signature → malformed (no throw)', () => {
    const secret = 'test-secret-key-for-bridge-hmac-32b!';
    const nowSec = 1700000000;
    const parts = {
      timestamp: nowSec,
      nonce: 'nonce-malformed-test',
      method: 'POST',
      pathWithQuery: '/api/v1/bridge/actions/1/result',
      body: '{"ok":true,"code":"done"}',
    };

    // Non-hex
    expect(verifyBridge(secret, parts, 'not-a-valid-hex-signature-string', nowSec)).toEqual({
      ok: false,
      reason: 'malformed',
    });

    // 64 chars but non-hex characters (e.g. 'z')
    expect(verifyBridge(secret, parts, 'z'.repeat(64), nowSec)).toEqual({
      ok: false,
      reason: 'malformed',
    });

    // Wrong length: 63 hex chars
    expect(verifyBridge(secret, parts, 'a'.repeat(63), nowSec)).toEqual({
      ok: false,
      reason: 'malformed',
    });

    // Wrong length: 65 hex chars
    expect(verifyBridge(secret, parts, 'a'.repeat(65), nowSec)).toEqual({
      ok: false,
      reason: 'malformed',
    });

    // Empty signature
    expect(verifyBridge(secret, parts, '', nowSec)).toEqual({
      ok: false,
      reason: 'malformed',
    });
  });
});
