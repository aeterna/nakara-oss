const API = 'SetHttpHandler';

export default {
  id: 'undeclared-http-handler',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'SetHttpHandler without capabilities.httpHandlers',
  docs: 'An HTTP handler is an unauthenticated entry point: anyone who can reach the server port can call it, with no player session. Declaring the paths it answers keeps that surface visible in the package README and in capability diffs. The scanner sees that a handler exists, not what it does with a body.',
  check(f, rctx, emit) {
    const uses = f.refs.filter((r) => r.call && r.path === API);
    if (!uses.length) return;
    if (!rctx.caps.httpHandlers.length) {
      const extra = uses.length > 1 ? ` (and ${uses.length - 1} more)` : '';
      emit(uses[0].line, `${API}${extra} — oss.json capabilities.httpHandlers is empty or missing`);
      return;
    }
    // The call exposes no path to compare; one handler makes the declared entries used.
    for (const h of rctx.caps.httpHandlers) rctx.used.httpHandlers.add(h);
  },
};
