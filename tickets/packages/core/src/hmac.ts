import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

export interface BridgeParts {
  timestamp: number | string;
  nonce: string;
  method: string;
  pathWithQuery: string;
  body?: string | Buffer | null;
}

export type VerifyBridgeResult =
  | { ok: true }
  | { ok: false; reason: 'skew' | 'signature' | 'malformed' };

export function sha256hex(data: string | Buffer = ''): string {
  const buf = Buffer.isBuffer(data)
    ? data
    : Buffer.from(data ?? '', 'utf8');
  return createHash('sha256').update(buf).digest('hex');
}

export function bridgeCanonical(parts: BridgeParts): string {
  const method = parts.method.toUpperCase();
  const bodyHash = sha256hex(parts.body ?? '');
  return `${parts.timestamp}\n${parts.nonce}\n${method}\n${parts.pathWithQuery}\n${bodyHash}`;
}

export function signBridge(secret: string | Buffer, parts: BridgeParts): string {
  const canonical = bridgeCanonical(parts);
  return createHmac('sha256', secret).update(canonical, 'utf8').digest('hex');
}

export function verifyBridge(
  secret: string | Buffer,
  parts: BridgeParts,
  sigHex: string,
  nowSec: number,
  skewSec = 60,
): VerifyBridgeResult {
  try {
    if (
      typeof sigHex !== 'string' ||
      sigHex.length !== 64 ||
      !/^[0-9a-fA-F]{64}$/.test(sigHex)
    ) {
      return { ok: false, reason: 'malformed' };
    }

    const ts = typeof parts?.timestamp === 'number' ? parts.timestamp : Number(parts?.timestamp);
    if (!Number.isFinite(ts)) {
      return { ok: false, reason: 'malformed' };
    }

    if (Math.abs(nowSec - ts) > skewSec) {
      return { ok: false, reason: 'skew' };
    }

    const expectedHex = signBridge(secret, parts);
    const expectedBuf = Buffer.from(expectedHex, 'hex');
    const actualBuf = Buffer.from(sigHex.toLowerCase(), 'hex');

    if (expectedBuf.length !== actualBuf.length || !timingSafeEqual(expectedBuf, actualBuf)) {
      return { ok: false, reason: 'signature' };
    }

    return { ok: true };
  } catch {
    return { ok: false, reason: 'malformed' };
  }
}
