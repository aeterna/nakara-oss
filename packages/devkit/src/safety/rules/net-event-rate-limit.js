import { eventHandlers, fnMatches, literal, netRegistrations } from './util.js';

export default {
  id: 'net-event-rate-limit',
  severity: 'warn',
  kind: 'quality',
  description: 'server net event handler without a rate-limit call (safety.rateLimitFns)',
  docs: 'Any client can fire a server net event thousands of times a second. A handler that does work (DB writes, item grants, HTTP) without a rate limit is a denial-of-service and an exploit amplifier. Configure the accepted function names with safety.rateLimitFns.',
  check(f, rctx, emit) {
    if (!f.isServer) return;
    const fns = rctx.opts.rateLimitFns;
    const handlers = netRegistrations(f).filter((r) => r.handler);
    for (const h of eventHandlers(f)) {
      const name = literal(h.name);
      if (name !== null && rctx.netServerNames.has(name)) handlers.push(h);
    }
    for (const h of handlers) {
      const label = `${h.api}('${literal(h.name) ?? '…'}')`;
      if (!h.handler.fn) {
        if (h.handler.kind === 'name' || h.handler.kind === 'function') emit(h.line, `${label} — handler not found in this file; cannot verify it is rate limited`);
        continue;
      }
      const calls = h.handler.fn.calls ?? [];
      if (!calls.some((c) => fns.some((fn) => fnMatches(c.path, fn)))) {
        emit(h.line, `${label} handler has no rate-limit call (${fns.join(', ')})`);
      }
    }
  },
};
