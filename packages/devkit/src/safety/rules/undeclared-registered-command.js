import { capMatches } from '../capabilities.js';
import { literal, partsText } from './util.js';

const APIS = new Set(['RegisterCommand', 'lib.addCommand']);

export default {
  id: 'undeclared-registered-command',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'RegisterCommand / lib.addCommand name not in capabilities.registeredCommands',
  docs: 'A registered command is a new entry point players (or the console) can call. Declaring them keeps the attack surface visible in the package README and in capability diffs.',
  check(f, rctx, emit) {
    for (const ref of f.refs) {
      if (!ref.call || !APIS.has(ref.path) || !ref.call.args[0]) continue;
      const arg = ref.call.args[0];
      let names;
      if (arg.kind === 'table') names = f.tableStrings ? f.tableStrings(arg) : null;
      else names = literal(arg.parts) !== null ? [literal(arg.parts)] : null;
      if (!names || !names.length) { emit(ref.line, `${ref.path}(${partsText(arg.parts)}) — command name built at runtime; use a literal`); continue; }
      for (const name of names) {
        const hits = rctx.caps.registeredCommands.filter((c) => capMatches([c], name));
        hits.forEach((h) => rctx.used.registeredCommands.add(h));
        if (!hits.length) emit(ref.line, `${ref.path} '${name}' — not declared in oss.json capabilities.registeredCommands`);
      }
    }
  },
};
