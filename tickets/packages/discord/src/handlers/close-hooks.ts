import type { CloseHookContext } from '../types.js';
import { archiveOnClose } from './archive.js';
import { ratingOnClose } from './rating.js';

export type CloseHook = (ctx: CloseHookContext) => Promise<void>;

export const defaultCloseHooks: CloseHook[] = [
  archiveOnClose,
  ratingOnClose,
];

export async function runCloseHooks(
  ctx: CloseHookContext,
  hooks: CloseHook[] = defaultCloseHooks
): Promise<PromiseSettledResult<void>[]> {
  const results = await Promise.allSettled(hooks.map((fn) => fn(ctx)));

  for (const res of results) {
    if (res.status === 'rejected') {
      const err = res.reason;
      if (typeof ctx.log?.error === 'function') {
        ctx.log.error('Close hook failed', err);
      } else {
        console.error('Close hook failed', err);
      }
    }
  }

  return results;
}
