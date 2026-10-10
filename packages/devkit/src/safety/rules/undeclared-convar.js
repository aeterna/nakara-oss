import { capMatches } from '../capabilities.js';
import { CONVAR_GETTERS, isSecretConvar } from './secret-convar.js';
import { literal, partsText, valueRefs } from './util.js';

const SETTERS = new Set(['SetConvar', 'SetConvarReplicated', 'SetConvarServerInfo']);

export default {
  id: 'undeclared-convar',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'GetConvar*/SetConvar* on a name not in capabilities.convars.read / .write (prefix* globs allowed)',
  docs: 'Convars hold server configuration other resources trust. Reads are declared so a package cannot quietly harvest config; writes because they change other resources\' behaviour. A name built at runtime cannot be checked against the secret list, so it is reported.',
  check(f, rctx, emit) {
    for (const ref of f.refs) {
      if (!ref.call || !ref.call.args[0]) continue;
      const read = CONVAR_GETTERS.has(ref.path);
      const write = SETTERS.has(ref.path);
      if (!read && !write) continue;
      const parts = ref.call.args[0].parts;
      const name = literal(parts);
      if (read && isSecretConvar(parts)) continue; // secret-convar reports it
      if (name === null) { emit(ref.line, `${ref.path}('${partsText(parts)}') — convar name built at runtime; use a literal name`); continue; }
      const list = read ? rctx.caps.convars.read : rctx.caps.convars.write;
      const used = read ? rctx.used.convarsRead : rctx.used.convarsWrite;
      const hits = list.filter((p) => capMatches([p], name));
      hits.forEach((h) => used.add(h));
      if (!hits.length) emit(ref.line, `${ref.path}('${name}') — not declared in oss.json capabilities.convars.${read ? 'read' : 'write'}`);
    }
    for (const ref of valueRefs(f, new Set([...CONVAR_GETTERS, ...SETTERS]))) emit(ref.line, `${ref.path} referenced as a value — the convars it touches cannot be checked`);
  },
};
