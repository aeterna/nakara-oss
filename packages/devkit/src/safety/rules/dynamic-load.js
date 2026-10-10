import { literal } from './util.js';

// Lua names that turn data into running code. Any reference counts, not only a call:
// `local l = load; l(body)` and `pcall(load, body)` are the same backdoor.
const LUA = new Set(['load', 'loadstring', 'dofile', 'loadfile', 'package.loadlib']);

export default {
  id: 'dynamic-load',
  severity: 'error',
  kind: 'hard-deny',
  description: 'runtime code loading: load/loadstring/dofile/loadfile, dynamic require/import, remote <script src>',
  docs: 'Nearly every FiveM backdoor seen in the wild is PerformHttpRequest + load(body)(): the code that runs is fetched at runtime and was never reviewed. Only a per-file allow entry with a reason can permit it.',
  check(f, _r, emit) {
    for (const ref of f.refs) {
      if (f.lang === 'lua') {
        if (ref.path && (LUA.has(ref.path) || ref.path.startsWith('package.loadlib.'))) {
          emit(ref.line, `${ref.path} ${ref.call ? 'called' : 'referenced'} — loads code at runtime that nobody reviewed`);
        }
        continue;
      }
      if (ref.path === 'require') {
        if (ref.call && !literal(ref.call.args[0]?.parts)) emit(ref.line, 'require() with a module name computed at runtime');
        else if (!ref.call && !ref.typeofOperand) emit(ref.line, 'require referenced as a value — cannot see which module it loads');
      }
      if (ref.path === 'import' && ref.call && !literal(ref.call.args[0]?.parts)) emit(ref.line, 'import() with a module specifier computed at runtime');
      if (ref.path && /^module:(?:https?:)?\/\//i.test(ref.path)) emit(ref.line, `imports remote code (${ref.path.slice(7)}) — vendor it`);
    }
    for (const s of f.remoteScripts ?? []) emit(s.line, `<script src="${s.src}"> loads remote code into NUI — vendor it and build from source`);
  },
};
