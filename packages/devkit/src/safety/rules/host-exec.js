import { literal, partsText } from './util.js';

const LUA = ['os.execute', 'io.popen', 'os.remove', 'os.rename', 'os.exit', 'os.tmpname'];
const JS_MODULES = ['module:child_process', 'module:vm', 'module:worker_threads'];
const JS_PATHS = ['process.binding', 'process._linkedBinding', 'process.dlopen', 'process.exit', 'process.kill', 'process.abort', 'process.reallyExit'];

const under = (path, list) => list.some((p) => path === p || path.startsWith(p + '.'));

export default {
  id: 'host-exec',
  severity: 'error',
  kind: 'hard-deny',
  description: 'host access: os.execute, io.popen, os.remove/rename/exit, io.open for writing, child_process, vm, worker_threads, process.binding',
  docs: 'FiveM has no sandbox: these run commands or touch files on the machine hosting the server, outside anything a capability can describe.',
  check(f, _r, emit) {
    for (const ref of f.refs) {
      const p = ref.path;
      if (!p) continue;
      if (f.lang === 'lua') {
        if (under(p, LUA)) { emit(ref.line, `${p} — runs or changes things on the host machine`); continue; }
        if (p === 'io.open') {
          if (!ref.call) { if (!ref.aliasSource) emit(ref.line, 'io.open referenced as a value — cannot verify the open mode'); continue; }
          const mode = ref.call.args[1];
          if (!mode) continue; // default mode 'r'
          const m = literal(mode.parts);
          if (m === null) emit(ref.line, `io.open with a mode computed at runtime (${partsText(mode.parts)})`);
          else if (/[wa+]/.test(m)) emit(ref.line, `io.open(…, '${m}') writes to the host filesystem — use SaveResourceFile and declare files.write`);
          continue;
        }
        if (p === 'io.output' && ref.call && ref.call.args.length) { emit(ref.line, 'io.output(file) opens a host file for writing'); continue; }
        if ((p === 'os' || p === 'io') && !ref.call && !ref.aliasSource && !ref.assigned) {
          emit(ref.line, `the ${p} library escapes as a value — calls through it cannot be checked`);
        }
        continue;
      }
      if (under(p, JS_MODULES)) emit(ref.line, `${p.replace('module:', '')} — runs code or processes on the host`);
      else if (under(p, JS_PATHS)) emit(ref.line, `${p} — native/process-level access to the host`);
    }
  },
};
