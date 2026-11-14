import { createHash } from 'node:crypto';

export function normalizePairCode(raw: string): string {
  return raw
    .trim()
    .toUpperCase()
    .replace(/[IL]/g, '1')
    .replace(/O/g, '0');
}

export function sha256hex(str: string): string {
  return createHash('sha256').update(str).digest('hex');
}
