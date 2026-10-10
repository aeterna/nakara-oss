import { capMatches } from '../capabilities.js';
import { RES_MARKER, literal, partsText, valueRefs } from './util.js';

export default {
  id: 'undeclared-file-write',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'SaveResourceFile to a path not in capabilities.files.write, or into another resource',
  docs: 'SaveResourceFile can overwrite any resource\'s files — including another resource\'s fxmanifest.lua or server scripts, which then run on next start. Writes are limited to this resource and to declared paths.',
  check(f, rctx, emit) {
    for (const ref of f.refs) {
      if (ref.path !== 'SaveResourceFile' || !ref.call) continue;
      const [res, file] = ref.call.args;
      const resName = res ? literal(res.parts) : null;
      const own = res && ((res.parts.length === 1 && res.parts[0] === RES_MARKER) || (resName !== null && rctx.names.has(resName)));
      if (!own) emit(ref.line, `SaveResourceFile into '${res ? partsText(res.parts) : '?'}' — only GetCurrentResourceName() (this resource) is allowed`);
      const name = file ? literal(file.parts) : null;
      if (name === null) { emit(ref.line, `SaveResourceFile path '${file ? partsText(file.parts) : '?'}' built at runtime — use a literal path`); continue; }
      const hits = rctx.caps.files.write.filter((p) => capMatches([p], name));
      hits.forEach((h) => rctx.used.filesWrite.add(h));
      if (!hits.length) emit(ref.line, `SaveResourceFile '${name}' — not declared in oss.json capabilities.files.write`);
    }
    for (const ref of valueRefs(f, new Set(['SaveResourceFile']))) emit(ref.line, 'SaveResourceFile referenced as a value — its targets cannot be checked');
  },
};
