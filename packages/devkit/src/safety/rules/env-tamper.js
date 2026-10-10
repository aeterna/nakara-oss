// The global table is how name-based rules get dodged: _G['lo' .. 'ad'] is load, and a function that
// receives _G can call anything. Literal access (_G.Config, _G['Config']) resolves to the named global
// and is checked like a plain reference; everything else is reported here.
const LUA = new Set(['getfenv', 'setfenv', 'string.dump', 'newproxy']);

export default {
  id: 'env-tamper',
  severity: 'error',
  kind: 'hard-deny',
  description: 'environment tampering: debug.* (except debug.traceback), getfenv/setfenv, string.dump, _G/_ENV passed around or indexed dynamically',
  docs: 'debug.* rewrites other code\'s upvalues and hooks; getfenv/setfenv and dynamic _G/_ENV access reach any global by a computed name, which defeats every name-based rule in this scanner.',
  check(f, _r, emit) {
    if (f.lang === 'lua') {
      const ownsDebug = f.refs.some((r) => r.path === 'debug' && r.assigned);
      for (const ref of f.refs) {
        if (ref.dynamic) { emit(ref.line, '_G/_ENV indexed with a computed key — reaches any global by name'); continue; }
        if (ref.indirect) emit(ref.line, `_G/_ENV indexed through a built or stored name (resolves to ${ref.path}) — write the global directly`);
        if (ref.bareRoot) { if (!ref.assigned) emit(ref.line, '_G/_ENV used as a value (rawget/rawset/setmetatable/aliasing) — reaches any global by name'); continue; }
        const p = ref.path;
        if (!p) continue;
        // debug.traceback only formats a stack string (the standard xpcall handler) — it reads, never rewrites.
        if (p.startsWith('debug.') && p !== 'debug.traceback') emit(ref.line, `${p} — debug library`);
        else if (p === 'debug' && !ref.assigned && !ownsDebug) emit(ref.line, 'debug library referenced as a value');
        else if (LUA.has(p) || [...LUA].some((x) => p.startsWith(x + '.'))) emit(ref.line, `${p}`);
      }
      for (const d of f.decls ?? []) if (d.name === '_ENV') emit(d.line, 'declares _ENV — replaces the global environment for the code below');
      return;
    }
    for (const ref of f.refs) if (ref.dynamic) emit(ref.line, 'global object indexed with a computed key (window[x] / globalThis[x]) — reaches any global by name');
  },
};
