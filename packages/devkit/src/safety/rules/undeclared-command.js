import { capMatches } from '../capabilities.js';
import { commandWords, partsText } from './util.js';

export default {
  id: 'undeclared-command',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'ExecuteCommand with a command not in capabilities.commands',
  docs: 'Console commands reach other resources and the server itself. Each command name passed to ExecuteCommand is declared; the permission/config commands are denied outright by ace-command.',
  check(f, rctx, emit) {
    for (const ref of f.refs) {
      if (ref.path !== 'ExecuteCommand' || !ref.call || !ref.call.args[0]) continue;
      const parts = ref.call.args[0].parts;
      for (const w of commandWords(parts)) {
        if (w.word === null) {
          if (!f.isServer) emit(ref.line, `ExecuteCommand('${partsText(parts)}') — command name built at runtime; use a literal command name`);
          continue;
        }
        const hits = rctx.caps.commands.filter((c) => capMatches([c], w.word));
        hits.forEach((h) => rctx.used.commands.add(h));
        if (!hits.length) emit(ref.line, `ExecuteCommand runs '${w.word}' — not declared in oss.json capabilities.commands`);
      }
    }
  },
};
