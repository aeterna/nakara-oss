// Shared helpers for safety rules. A rule sees a file model (see ../model.js):
//   f.lang 'lua' | 'js' · f.side 'server' | 'client' | 'shared' | 'unlisted' | 'nui' | 'manifest'
//   f.isServer / f.isClient / f.isNui
//   f.refs: [{ path, line, call: { args: Arg[] } | null, aliasSource, viaPcall, dynamic, bareRoot, ... }]
//   Arg: { line, parts: (string|null)[], kind, name, fn: { calls: [{path,line}] } | null }
import { RES_MARKER } from '../luascan.js';

export { RES_MARKER };

// human-readable form of folded string parts
export function partsText(parts) {
  if (!parts) return '…';
  return parts
    .map((p) => (p === null ? '…' : p))
    .join('')
    .replaceAll(RES_MARKER, '<this resource>')
    .replaceAll('\u0004', '<number>')
    .replace(/\u0003([^\u0003]*)\u0003/g, '${$1}');
}

// does a string carry a runtime marker (resource name / convar value)?
export const hasMarker = (s) => /[\u0002-\u0004]/.test(s);

// the single literal value of parts, or null when anything is computed at runtime
export function literal(parts) {
  return parts && parts.length === 1 && typeof parts[0] === 'string' && !hasMarker(parts[0]) ? parts[0] : null;
}

export const isCallTo = (ref, names) => ref.call && ref.path !== null && names.has(ref.path);

export function calls(f, names) {
  return f.refs.filter((r) => isCallTo(r, names));
}

// references to an API that are not calls: the value escapes (passed around, stored in a table), so
// nothing downstream can be verified. Aliases (`local P = PerformHttpRequest`) are resolved at their
// call sites instead, and `typeof x` / `x instanceof X` are not uses.
export function valueRefs(f, names) {
  return f.refs.filter((r) => !r.call && r.path !== null && names.has(r.path) && !r.aliasSource && !r.typeofOperand && !r.instanceofRhs && !r.assigned);
}

// does a call path satisfy a configured function name? exact, a member of it, or a method named it
export function fnMatches(path, fn) {
  return path === fn || path.startsWith(fn + '.') || path.endsWith('.' + fn);
}

// ExecuteCommand helpers: split a folded command string into command segments (`;` / newline) and
// return each segment's first word; a word containing a runtime part is reported as null.
const DYN = '\u0001';
export function commandWords(parts) {
  const s = parts.map((p) => (p === null ? DYN : p)).join('').replace(/\u0002[^\u0002]*\u0002|\u0003[^\u0003]*\u0003/g, DYN);
  return s
    .split(/[;\n]/)
    .map((seg) => seg.replace(/^\s+/, ''))
    .filter((seg) => seg.length)
    .map((seg) => {
      const w = /^\S+/.exec(seg)[0];
      // numbers in arguments are fine; a number as (part of) the command name is not a name
      return { word: /[\u0001\u0004]/.test(w) ? null : w, text: seg.replaceAll(DYN, '…'), dynamicArgs: seg.includes(DYN) };
    });
}

// every word (for the always-denied permission words, which have no innocent use anywhere in a command)
export function allWords(parts) {
  return parts.filter((p) => typeof p === 'string').join(' ').split(/[\s;]+/).filter(Boolean);
}

// net event registrations in a file → [{ api, name: parts, line, handler: Arg | null }]
export const NET_REGISTER = new Set(['RegisterNetEvent', 'RegisterServerEvent', 'onNet', 'lib.callback.register']);
export const EVENT_HANDLER = new Set(['AddEventHandler', 'on']);

export function netRegistrations(f) {
  if (f.isNui) return [];
  const out = [];
  for (const r of f.refs) {
    if (!r.call || !NET_REGISTER.has(r.path)) continue;
    const [name, handler] = r.call.args;
    if (!name) continue;
    out.push({ api: r.path, name: name.parts, line: r.line, handler: handler ?? null });
  }
  return out;
}

export function eventHandlers(f) {
  if (f.isNui) return [];
  const out = [];
  for (const r of f.refs) {
    if (!r.call || !EVENT_HANDLER.has(r.path)) continue;
    if (r.path === 'on' && f.lang !== 'js') continue;
    const [name, handler] = r.call.args;
    if (!name) continue;
    out.push({ api: r.path, name: name.parts, line: r.line, handler: handler ?? null });
  }
  return out;
}
