// oss.json — the capability manifest each package ships next to fxmanifest.lua (schema:
// oss.schema.json at the repo root). Everything here is pure so CI scripts and the vendoring script
// can import it without running a scan.
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { nameMatches } from './glob.js';

export const OSS_FILE = 'oss.json';

// list-valued capabilities, as dotted paths into `capabilities`
export const LIST_CAPS = [
  'http', 'commands', 'registeredCommands', 'httpHandlers', 'convars.read', 'convars.write',
  'netEvents.server', 'netEvents.client', 'db.tables', 'files.write',
];
export const BOOL_CAPS = ['nui', 'db.ddl'];

const get = (obj, dotted) => dotted.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);

// Full capability object with every key present (missing = nothing declared).
export function normalizeCaps(caps = {}) {
  const c = caps ?? {};
  const list = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []);
  return {
    http: list(c.http),
    commands: list(c.commands),
    registeredCommands: list(c.registeredCommands),
    httpHandlers: list(c.httpHandlers),
    convars: { read: list(c.convars?.read), write: list(c.convars?.write) },
    netEvents: { server: list(c.netEvents?.server), client: list(c.netEvents?.client) },
    nui: c.nui === true,
    db: { tables: list(c.db?.tables), ddl: c.db?.ddl === true },
    files: { write: list(c.files?.write) },
  };
}

// Light structural validation (the JSON schema is the full contract; this catches what would make
// the scan itself meaningless — wrong types, unknown keys that look like typos of real ones).
export function validateOss(data) {
  const problems = [];
  if (!data || typeof data !== 'object' || Array.isArray(data)) return ['oss.json must be a JSON object'];
  for (const k of ['name', 'resource', 'capabilities']) if (!(k in data)) problems.push(`missing "${k}"`);
  const caps = data.capabilities;
  if (caps && typeof caps === 'object') {
    const known = new Set(['http', 'commands', 'registeredCommands', 'httpHandlers', 'convars', 'netEvents', 'nui', 'db', 'files']);
    for (const k of Object.keys(caps)) if (!known.has(k)) problems.push(`unknown capability "${k}"`);
    for (const k of ['http', 'commands', 'convars', 'netEvents', 'nui', 'db', 'files']) if (!(k in caps)) problems.push(`missing capabilities.${k}`);
    for (const p of LIST_CAPS) {
      const v = get(caps, p);
      if (v !== undefined && (!Array.isArray(v) || v.some((x) => typeof x !== 'string'))) problems.push(`capabilities.${p} must be an array of strings`);
    }
    for (const p of BOOL_CAPS) {
      const v = get(caps, p);
      if (v !== undefined && typeof v !== 'boolean') problems.push(`capabilities.${p} must be a boolean`);
    }
  } else if ('capabilities' in data) problems.push('capabilities must be an object');
  return problems;
}

// → { exists, file, data, caps, problems }
export function loadOss(resourceDir) {
  const file = path.join(resourceDir, OSS_FILE);
  if (!existsSync(file)) return { exists: false, file, data: null, caps: normalizeCaps({}), problems: [] };
  let data;
  try {
    data = JSON.parse(readFileSync(file, 'utf8'));
  } catch (err) {
    return { exists: true, file, data: null, caps: normalizeCaps({}), problems: [`invalid JSON (${err.message})`] };
  }
  return { exists: true, file, data, caps: normalizeCaps(data?.capabilities), problems: validateOss(data) };
}

// ---- URL matching -----------------------------------------------------------------------------
// A URL found in code is a list of parts: literal strings and null for anything computed at runtime.
// A declared entry is a prefix with optional ${convar} placeholders.
//   - scheme (http://, https://, ws://, wss://) is ignored on both sides
//   - a placeholder matches the value of THAT convar read in the same expression
//     ('https://' .. GetConvar('api_host', '') .. '/v1'), or literal text without '.', '/', ':',
//     '?' or '#' (a port number, a path segment) — never a hard-coded host
//   - outside the host (port, path) a placeholder also accepts any runtime value; in the host
//     position it does not, so `${api_host}/v1` rejects 'https://' .. someVariable .. '/v1'
const DYN = '\u0001';
const stripScheme = (s) => s.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');

export function urlPattern(parts) {
  return stripScheme(parts.map((p) => (p === null ? DYN : p)).join(''));
}

const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export function httpEntryMatches(entry, parts) {
  const actual = urlPattern(parts);
  const decl = stripScheme(entry);
  const authorityEnd = decl.search(/[/?#]/) < 0 ? decl.length : decl.search(/[/?#]/);
  let re = '';
  for (let i = 0; i < decl.length; i++) {
    if (decl[i] === '$' && decl[i + 1] === '{') {
      const close = decl.indexOf('}', i);
      if (close > 0) {
        const name = decl.slice(i + 2, close);
        const hostPos = i < authorityEnd && !decl.slice(0, i).includes(':');
        const alts = [reEsc(`\u0003${name}\u0003`), `[^./?#:${DYN}\u0002\u0003]+`]; // incl. a %d number
        if (!hostPos) alts.push(DYN);
        re += `(?:${alts.join('|')})`;
        i = close;
        continue;
      }
    }
    re += reEsc(decl[i]);
  }
  // an entry that is only a host ('api.example.com') must not match 'api.example.com.evil.invalid'
  if (authorityEnd === decl.length) re += `(?=$|[/:?#])`;
  return new RegExp(`^${re}`).test(actual);
}

// Does the URL start with a dynamic part (nothing proves where it goes)?
export function urlIsDynamic(parts) {
  const actual = urlPattern(parts);
  return actual === '' || actual.startsWith(DYN);
}

export const capMatches = (patterns, name) => patterns.some((p) => nameMatches(p, name));

// ---- capability diff --------------------------------------------------------------------------
// capabilityDiff(oldJson, newJson) → { added: string[], removed: string[] }
// Accepts the oss.json objects (or their JSON text, or null for "package did not exist").
// `added` is every widening (new list entry, boolean false → true); `removed` every narrowing.
// CI labels a PR `capability-change` when `added` is non-empty.
export function capabilityDiff(oldJson, newJson) {
  const parse = (j) => (typeof j === 'string' ? JSON.parse(j) : j);
  const a = normalizeCaps(parse(oldJson)?.capabilities);
  const b = normalizeCaps(parse(newJson)?.capabilities);
  const added = [];
  const removed = [];
  for (const p of LIST_CAPS) {
    const before = new Set(get(a, p));
    const after = new Set(get(b, p));
    for (const v of after) if (!before.has(v)) added.push(`${p}: ${v}`);
    for (const v of before) if (!after.has(v)) removed.push(`${p}: ${v}`);
  }
  for (const p of BOOL_CAPS) {
    const before = get(a, p);
    const after = get(b, p);
    if (!before && after) added.push(`${p}: true (was false)`);
    if (before && !after) removed.push(`${p}: false (was true)`);
  }
  return { added, removed };
}
