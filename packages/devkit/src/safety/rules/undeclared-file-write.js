import { capMatches } from '../capabilities.js';
import { RES_MARKER, hasMarker, literal, partsText, valueRefs } from './util.js';

// A runtime-built path is still checkable when it starts with a literal prefix: `'photos/' .. id`
// (Lua), `'photos/' + id` or `photos/${id}` (JS). The prefix must stay inside the resource, and a
// declared glob must cover it (`photos/*`). Anything after the prefix is unknown.
function literalPrefix(parts) {
  if (!parts || parts.length < 2 || typeof parts[0] !== 'string') return null;
  return parts[0] === '' || hasMarker(parts[0]) ? null : parts[0];
}

function prefixEscapes(parts, prefix) {
  return prefix.startsWith('/') || parts.some((p) => typeof p === 'string' && p.includes('..'));
}

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
      const prefix = name === null && file ? literalPrefix(file.parts) : null;
      if (name === null && prefix === null) {
        emit(ref.line, `SaveResourceFile path '${file ? partsText(file.parts) : '?'}' built at runtime — use a literal path or a literal prefix covered by capabilities.files.write`);
        continue;
      }
      if (prefix !== null && prefixEscapes(file.parts, prefix)) {
        emit(ref.line, `SaveResourceFile path '${partsText(file.parts)}' built at runtime from an unsafe literal prefix — use a relative prefix without '..' or a leading '/'`);
        continue;
      }
      const hits = rctx.caps.files.write.filter((p) => capMatches([p], name ?? (prefix + '*')));
      hits.forEach((h) => rctx.used.filesWrite.add(h));
      if (!hits.length) emit(ref.line, `SaveResourceFile '${name ?? partsText(file.parts)}' — not declared in oss.json capabilities.files.write`);
    }
    for (const ref of valueRefs(f, new Set(['SaveResourceFile']))) emit(ref.line, 'SaveResourceFile referenced as a value — its targets cannot be checked');
  },
};
