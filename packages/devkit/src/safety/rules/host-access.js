const JS_MODULES = ['module:fs', 'module:fs/promises', 'module:net', 'module:dgram', 'module:tls', 'module:cluster', 'module:module', 'module:inspector', 'module:v8'];

const under = (path, list) => list.some((p) => path === p || path.startsWith(p + '.'));

export default {
  id: 'host-access',
  severity: 'error',
  kind: 'hard-deny',
  description: 'raw filesystem, socket and environment access that bypasses declared capabilities (node fs/net/dgram/tls, process.env, os.getenv)',
  docs: 'fs writes bypass SaveResourceFile + files.write; raw sockets bypass the http declaration; environment variables are where hosts keep database passwords and API keys. Allow per file with a reason when a server-side tool genuinely needs it.',
  check(f, _r, emit) {
    for (const ref of f.refs) {
      const p = ref.path;
      if (!p) continue;
      if (f.lang === 'lua') {
        if (p === 'os.getenv' || p.startsWith('os.getenv.')) emit(ref.line, 'os.getenv reads host environment variables (where secrets live)');
        continue;
      }
      if (under(p, JS_MODULES)) emit(ref.line, `${p.replace('module:', '')} — direct host ${/fs/.test(p) ? 'filesystem' : 'network/runtime'} access`);
      else if (p === 'process.env' || p.startsWith('process.env.')) emit(ref.line, `${p} reads host environment variables (where secrets live)`);
    }
  },
};
