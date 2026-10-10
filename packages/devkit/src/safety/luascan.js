// Lua token analysis → the language-neutral file model the safety rules read (see model.js).
//
// What it resolves, without a full parser:
//   - block structure (function/do/if/repeat ... end/until) and lexical scopes, so a local named `load`
//     or `debug` is not mistaken for the global, while `do local debug = 1 end debug.sethook()` still is
//   - local aliases:  `local l = load` / `local o = os` → later `l(x)` resolves to `load`, `o.execute`
//     to `os.execute`
//   - member chains:  `os.execute`, `exports['ox' .. 'mysql']:query`, `_G['lo' .. 'ad']` → `load`
//   - call arguments, folded to string parts:  'ensure ' .. name  →  ['ensure ', null]
//   - function bodies, so a net-event handler can be checked for a rate-limit call
import { lex } from './lualex.js';

export const RES_MARKER = '\u0002resource\u0002';
// GetConvar('name', ...) inside a folded string: matches a ${name} placeholder in capabilities.http
export const convarMarker = (name) => `\u0003${name}\u0003`;
// a %d / %f / %x ... format directive: unknown, but a number (cannot carry ';' or a host name)
export const NUM_MARKER = '\u0004';
const CONVAR_GETTERS = new Set(['GetConvar', 'GetConvarInt', 'GetConvarFloat']);

const BLOCK_OPEN = new Set(['function', 'do', 'if', 'repeat']);
const STMT_KEYWORDS = new Set([
  'local', 'return', 'break', 'goto', 'do', 'while', 'for', 'if', 'repeat', 'end', 'else', 'elseif', 'until', 'function',
]);
const ROOTS = new Set(['_G', '_ENV']);

const isOp = (t, v) => t && t.type === 'op' && t.value === v;
const isKw = (t, v) => t && t.type === 'keyword' && t.value === v;

function isExprEnd(t) {
  if (!t) return false;
  if (t.type === 'name' || t.type === 'string' || t.type === 'number' || t.type === 'hash') return true;
  if (t.type === 'op') return t.value === ')' || t.value === ']' || t.value === '}' || t.value === '...';
  if (t.type === 'keyword') return t.value === 'end' || t.value === 'nil' || t.value === 'true' || t.value === 'false';
  return false;
}

export function analyzeLua(src) {
  const { tokens: toks, errors } = lex(src);
  const n = toks.length;

  // ---- matching brackets and block ends -------------------------------------------------------
  const match = new Int32Array(n).fill(-1);
  {
    const br = [];
    const blk = [];
    for (let i = 0; i < n; i++) {
      const t = toks[i];
      if (t.type === 'op' && (t.value === '(' || t.value === '[' || t.value === '{')) br.push(i);
      else if (t.type === 'op' && (t.value === ')' || t.value === ']' || t.value === '}')) {
        const o = br.pop();
        if (o !== undefined) { match[o] = i; match[i] = o; }
      } else if (t.type === 'keyword' && BLOCK_OPEN.has(t.value)) {
        // `while x do` / `for ... do`: the `do` is the opener, the loop keyword is not
        blk.push(i);
      } else if (t.type === 'keyword' && (t.value === 'end' || t.value === 'until')) {
        const o = blk.pop();
        if (o !== undefined) { match[o] = i; match[i] = o; }
      }
    }
  }

  // end (exclusive) of an expression list starting at `start`
  function exprListEnd(start) {
    let depth = 0;
    let prev = null;
    for (let j = start; j < n; j++) {
      const t = toks[j];
      if (t.type === 'eof') return j;
      if (depth === 0) {
        if (isOp(t, ';')) return j;
        if (t.type === 'op' && (t.value === ')' || t.value === ']' || t.value === '}')) return j;
        if (prev && isExprEnd(prev) && (t.type === 'name' || (t.type === 'keyword' && STMT_KEYWORDS.has(t.value)) || isOp(t, '::'))) return j;
        if (t.type === 'keyword' && STMT_KEYWORDS.has(t.value) && t.value !== 'function') return j;
      }
      if (t.type === 'op' && (t.value === '(' || t.value === '[' || t.value === '{')) {
        if (match[j] < 0) return n - 1;
        j = match[j];
        prev = toks[j];
        continue;
      }
      if (isKw(t, 'function')) {
        if (match[j] < 0) return n - 1;
        j = match[j];
        prev = toks[j];
        continue;
      }
      prev = t;
    }
    return n - 1;
  }

  // split [a, b) at depth-0 commas
  function splitCommas(a, b) {
    const out = [];
    let s = a;
    for (let j = a; j < b; j++) {
      const t = toks[j];
      if (t.type === 'op' && (t.value === '(' || t.value === '[' || t.value === '{') && match[j] > 0) { j = match[j]; continue; }
      if (isKw(t, 'function') && match[j] > 0) { j = match[j]; continue; }
      if (isOp(t, ',')) { out.push([s, j]); s = j + 1; }
    }
    if (b > s || out.length) out.push([s, b]);
    return out.filter(([x, y]) => y > x);
  }

  // ---- scopes, declarations, aliases ----------------------------------------------------------
  // role[i] for name tokens: 'decl' | 'field' | 'key' | 'ref'
  const role = new Array(n);
  const binding = new Array(n); // for 'ref' names: the local binding, or null (global)
  const aliasSource = new Set(); // token index of a reference that is the RHS of an alias
  const scopes = [new Map()];
  const pending = []; // { at, scope, names: [{name, idx, rhs: [a,b] | null}] }
  let forNames = null;
  const brStack = [];

  const lookup = (name) => {
    for (let s = scopes.length - 1; s >= 0; s--) if (scopes[s].has(name)) return scopes[s].get(name);
    return null;
  };
  const declObj = new Map(); // declaration token index → binding object (shared by every ref to it)
  const declare = (scope, name, idx, alias = null) => {
    const b = { name, idx, alias };
    scope.set(name, b);
    declObj.set(idx, b);
  };

  // is [a, b) a pure path expression (Name {. Name | [string]}); returns its resolved path or undefined
  const pathRanges = new Map(); // a → { path, end }
  function purePath(a, b) {
    const r = chainAt(a);
    if (r && r.end === b && !r.call && !r.dynamic) return r;
    return undefined;
  }

  function activatePending(i) {
    for (let k = pending.length - 1; k >= 0; k--) {
      if (pending[k].at <= i) {
        const p = pending.splice(k, 1)[0];
        for (const d of p.names) declare(p.scope, d.name, d.idx, d.alias ?? null);
      }
    }
  }

  // Pass 1: walk tokens, maintaining scopes. Aliases need chain resolution of the RHS *at the time
  // of declaration*, so chainAt (below) uses `binding`, which is filled in this same pass.
  for (let i = 0; i < n; i++) {
    if (pending.length) activatePending(i);
    const t = toks[i];
    if (t.type === 'op') {
      if (t.value === '(' || t.value === '[' || t.value === '{') brStack.push(t.value);
      else if (t.value === ')' || t.value === ']' || t.value === '}') brStack.pop();
      continue;
    }
    if (t.type === 'keyword') {
      switch (t.value) {
        case 'local': {
          const nx = toks[i + 1];
          if (isKw(nx, 'function')) {
            const nm = toks[i + 2];
            if (nm && nm.type === 'name') {
              role[i + 2] = 'decl';
              declare(scopes[scopes.length - 1], nm.value, i + 2);
            }
            break;
          }
          const names = [];
          let j = i + 1;
          while (toks[j] && toks[j].type === 'name') {
            role[j] = 'decl';
            names.push({ name: toks[j].value, idx: j });
            j++;
            if (isOp(toks[j], '<') && toks[j + 1]?.type === 'name' && isOp(toks[j + 2], '>')) {
              role[j + 1] = 'field'; // attribute name (const / close)
              j += 3;
            }
            if (isOp(toks[j], ',')) { j++; continue; }
            break;
          }
          if (isOp(toks[j], '=')) {
            const end = exprListEnd(j + 1);
            const items = splitCommas(j + 1, end);
            pending.push({ at: end, scope: scopes[scopes.length - 1], names });
          } else {
            pending.push({ at: j, scope: scopes[scopes.length - 1], names });
          }
          break;
        }
        case 'function': {
          // header: [funcname] ( params )
          let j = i + 1;
          let method = false;
          if (toks[j]?.type === 'name') {
            if (role[j] !== 'decl') {
              // `function a.b:c()` — `a` is read (indexed); bare `function f()` assigns a global
              role[j] = isOp(toks[j + 1], '.') || isOp(toks[j + 1], ':') ? 'ref' : 'assign';
              if (role[j] === 'ref') binding[j] = lookup(toks[j].value);
            }
            j++;
            while ((isOp(toks[j], '.') || isOp(toks[j], ':')) && toks[j + 1]?.type === 'name') {
              if (toks[j].value === ':') method = true;
              role[j + 1] = 'field';
              j += 2;
            }
          }
          const scope = new Map();
          if (method) declare(scope, 'self', i);
          if (isOp(toks[j], '(') && match[j] > 0) {
            for (let k = j + 1; k < match[j]; k++) {
              if (toks[k].type === 'name') { role[k] = 'decl'; declare(scope, toks[k].value, k); }
            }
            i = match[j]; // skip the header so params are not visited as references
          }
          scopes.push(scope);
          break;
        }
        case 'for': {
          forNames = [];
          let j = i + 1;
          while (toks[j]?.type === 'name') {
            role[j] = 'decl';
            forNames.push({ name: toks[j].value, idx: j });
            j++;
            if (isOp(toks[j], ',')) j++;
            else break;
          }
          i = j - 1;
          break;
        }
        case 'do': {
          const s = new Map();
          if (forNames) { for (const d of forNames) declare(s, d.name, d.idx); forNames = null; }
          scopes.push(s);
          break;
        }
        case 'if':
        case 'repeat':
          scopes.push(new Map());
          break;
        case 'elseif':
        case 'else':
          if (scopes.length > 1) scopes.pop();
          scopes.push(new Map());
          break;
        case 'end':
        case 'until':
          if (scopes.length > 1) scopes.pop();
          break;
        default:
          break;
      }
      continue;
    }
    if (t.type !== 'name' || role[i]) continue;
    const prev = toks[i - 1];
    if (prev && prev.type === 'op' && (prev.value === '.' || prev.value === ':' || prev.value === '?.')) {
      role[i] = 'field';
      continue;
    }
    const next = toks[i + 1];
    if (brStack[brStack.length - 1] === '{' && isOp(next, '=') && prev && prev.type === 'op' && (prev.value === '{' || prev.value === ',' || prev.value === ';')) {
      role[i] = 'key';
      continue;
    }
    if (prev && prev.type === 'op' && prev.value === '::') { role[i] = 'field'; continue; } // label
    if (isKw(prev, 'goto')) { role[i] = 'field'; continue; }
    role[i] = 'ref';
    binding[i] = lookup(t.value);
  }

  // ---- constants ------------------------------------------------------------------------------
  // name or dotted path assigned exactly once, from a foldable expression. Table constructors
  // contribute their literal fields: `Config = { url = 'x', nested = { cmd = 'y' } }` defines
  // Config.url and Config.nested.cmd. Keys assigned once across the whole resource are shared with
  // the other files through `ext.consts` (set by the engine once every file is analysed).
  const assignCount = new Map();
  const assignRhs = new Map();
  const localKeys = new Set();
  const addAssign = (key, rng) => {
    assignCount.set(key, (assignCount.get(key) ?? 0) + 1);
    if (rng) assignRhs.set(key, rng);
    if (rng && isOp(toks[rng[0]], '{') && match[rng[0]] === rng[1] - 1) addFields(key, rng[0], 0);
  };
  function addFields(prefix, open, depth) {
    if (depth > 4) return;
    const close = match[open];
    let s = open + 1;
    const fields = [];
    for (let j = open + 1; j <= close; j++) {
      const t = toks[j];
      if (j < close && t.type === 'op' && (t.value === '(' || t.value === '[' || t.value === '{') && match[j] > 0) { j = match[j]; continue; }
      if (j < close && isKw(t, 'function') && match[j] > 0) { j = match[j]; continue; }
      if (j === close || isOp(t, ',') || isOp(t, ';')) { if (j > s) fields.push([s, j]); s = j + 1; }
    }
    for (const [a, b] of fields) {
      let key = null;
      let v = -1;
      if (toks[a].type === 'name' && isOp(toks[a + 1], '=')) { key = toks[a].value; v = a + 2; }
      else if (isOp(toks[a], '[') && toks[a + 1]?.type === 'string' && isOp(toks[a + 2], ']') && isOp(toks[a + 3], '=')) { key = toks[a + 1].value; v = a + 4; }
      if (key !== null && v < b) addAssign(`${prefix}.${key}`, [v, b]);
    }
  }
  for (let i = 0; i < n; i++) {
    const t = toks[i];
    if (t.type !== 'name') continue;
    if (role[i] === 'decl' && isKw(toks[i - 1], 'local') && isOp(toks[i + 1], '=')) {
      const items = splitCommas(i + 2, exprListEnd(i + 2));
      localKeys.add(t.value);
      if (items.length === 1) addAssign(t.value, items[0]);
      continue;
    }
    if (role[i] !== 'ref' && role[i] !== 'assign') continue;
    // Name {. Name} = expr  at statement level
    let j = i + 1;
    let key = t.value;
    while (isOp(toks[j], '.') && toks[j + 1]?.type === 'name') { key += '.' + toks[j + 1].value; j += 2; }
    if (isOp(toks[j], '=') && !isOp(toks[i - 1], ',') && !isOp(toks[j + 1], '=')) {
      const items = splitCommas(j + 1, exprListEnd(j + 1));
      addAssign(key, items.length === 1 ? items[0] : null);
    }
  }
  const ext = { consts: null, totals: null };
  const constCache = new Map();
  function constParts(key, depth) {
    if (depth > 6) return null;
    const local = assignCount.get(key) ?? 0;
    if (!localKeys.has(key.split('.')[0]) && (ext.totals?.get(key) ?? local) > 1) return null; // assigned elsewhere too
    if (local === 0) {
      const shared = ext.consts?.get(key);
      return shared ? shared(depth + 1) : null;
    }
    if (local !== 1 || !assignRhs.has(key)) return null;
    if (constCache.has(key)) return constCache.get(key);
    constCache.set(key, null);
    const [a, b] = assignRhs.get(key);
    const parts = fold(a, b, depth + 1);
    const val = parts.some((p) => p !== null) ? parts : null;
    constCache.set(key, val);
    return val;
  }
  // keys this file assigns, for the resource-wide constant table: key → { count, get(depth) }
  function exportConsts() {
    const out = new Map();
    for (const [key, count] of assignCount) {
      if (localKeys.has(key.split('.')[0])) continue; // file-local: not visible to other files
      out.set(key, { count, get: (depth) => (count === 1 ? constParts(key, depth) : null) });
    }
    return out;
  }

  // Resolve a member chain starting at name token `a` (role 'ref').
  // → { path, end, base, dynamic, bareRoot, call: [argStart, argEnd] | null, callKind }
  function chainAt(a) {
    if (pathRanges.has(a)) return pathRanges.get(a);
    const t = toks[a];
    const b = binding[a];
    let base;
    if (b) base = b.alias ?? null; // a local: only meaningful when it aliases a global path
    else base = t.value;
    let parts = base === null ? null : ROOTS.has(base) ? [] : base.split('.');
    let root = base !== null && ROOTS.has(base);
    let j = a + 1;
    let dynamic = false;
    let dynamicAt = -1;
    let indirect = false;
    for (;;) {
      const x = toks[j];
      if ((isOp(x, '.') || isOp(x, '?.')) && toks[j + 1]?.type === 'name') {
        if (parts) parts.push(toks[j + 1].value);
        j += 2;
        continue;
      }
      if (isOp(x, ':') && toks[j + 1]?.type === 'name') {
        const after = toks[j + 2];
        if (isOp(after, '(') || after?.type === 'string' || isOp(after, '{')) {
          if (parts) parts.push(toks[j + 1].value);
          j += 2;
        }
        break;
      }
      if (isOp(x, '[') && match[j] > 0) {
        const f = fold(j + 1, match[j], 0);
        if (f.length === 1 && typeof f[0] === 'string') {
          // _G['lo' .. 'ad'] / _G[NAME]: resolved, but anything but one plain string is an evasion signal
          if (parts && parts.length === 0 && root && !(match[j] === j + 2 && toks[j + 1].type === 'string')) indirect = true;
          if (parts) parts.push(f[0]);
          j = match[j] + 1;
          continue;
        }
        if (parts && parts.length === 0 && root) { dynamic = true; dynamicAt = j; }
        else if (parts) { dynamicAt = j; }
        break;
      }
      break;
    }
    const path = parts ? parts.join('.') : null;
    let call = null;
    let callKind = null;
    const c = toks[j];
    if (!dynamic && path !== null) {
      if (isOp(c, '(') && match[j] > 0) { call = [j + 1, match[j]]; callKind = 'paren'; }
      else if (c?.type === 'string') { call = [j, j + 1]; callKind = 'string'; }
      else if (isOp(c, '{') && match[j] > 0) { call = [j, match[j] + 1]; callKind = 'table'; }
    }
    const r = {
      path, end: j, root, dynamic, dynamicAt, call, callKind, indirect,
      bareRoot: root && parts && parts.length === 0 && !dynamic,
    };
    pathRanges.set(a, r);
    return r;
  }

  // fold [a, b) into string parts; unknown spans become null
  function fold(a, b, depth = 0) {
    if (b <= a) return [null];
    // split at depth-0 `..`
    const pieces = [];
    let s = a;
    for (let j = a; j < b; j++) {
      const t = toks[j];
      if (t.type === 'op' && (t.value === '(' || t.value === '[' || t.value === '{') && match[j] > 0) { j = match[j]; continue; }
      if (isKw(t, 'function') && match[j] > 0) { j = match[j]; continue; }
      if (isOp(t, '..')) { pieces.push([s, j]); s = j + 1; }
    }
    pieces.push([s, b]);
    const out = [];
    for (const [x, y] of pieces) out.push(...foldPiece(x, y, depth));
    return normalizeParts(out);
  }

  function foldPiece(a, b, depth) {
    const t = toks[a];
    if (b - a === 1) {
      if (t.type === 'string') return [t.value];
      if (t.type === 'number') return [String(t.num)];
    }
    if (isOp(t, '(') && match[a] === b - 1) return fold(a + 1, b - 1, depth);
    // ('fmt' .. x):format(...)  — format directives become unknown parts
    if (isOp(t, '(') && match[a] > a) {
      const c = match[a];
      if (isOp(toks[c + 1], ':') && toks[c + 2]?.value === 'format' && isOp(toks[c + 3], '(') && match[c + 3] === b - 1) {
        return normalizeParts(fold(a + 1, c, depth).flatMap((p) => (typeof p === 'string' ? formatParts(p) : [null])));
      }
    }
    if (t.type === 'name' && role[a] === 'ref' && depth < 6) {
      const r = chainAt(a);
      if (r.path === 'string.format' && r.call && r.callKind === 'paren' && r.call[1] === b - 1) {
        const first = splitCommas(r.call[0], r.call[1])[0];
        if (first) return normalizeParts(fold(first[0], first[1], depth + 1).flatMap((p) => (typeof p === 'string' ? formatParts(p) : [null])));
      }
      if (r.path === 'GetCurrentResourceName' && r.call && r.call[1] === b - 1) return [RES_MARKER];
      if (CONVAR_GETTERS.has(r.path) && r.call && r.callKind === 'paren' && r.call[1] === b - 1) {
        const first = splitCommas(r.call[0], r.call[1])[0];
        const name = first && fold(first[0], first[1], depth + 1);
        if (name && name.length === 1 && typeof name[0] === 'string' && !/[\u0001-\u0003]/.test(name[0])) return [convarMarker(name[0])];
        return [null];
      }
      if (r.end === b && !r.call && !r.dynamic) {
        const key = binding[a] ? (r.end === a + 1 ? t.value : null) : r.path;
        const c = key && constParts(key, depth);
        if (c) return c;
      }
    }
    return [null];
  }

  // ---- pass 2: references ---------------------------------------------------------------------
  // Aliases: `local x = <pure path>`. RHS tokens were bound during pass 1 against the scope as it
  // was at that point, so resolving them now (in source order) gives the Lua semantics, including
  // alias-of-alias (`local o = os; local e = o.execute`).
  {
    // collect local declarations again with their RHS ranges
    for (let i = 0; i < n; i++) {
      if (!isKw(toks[i], 'local') || isKw(toks[i + 1], 'function')) continue;
      const names = [];
      let j = i + 1;
      while (toks[j]?.type === 'name') {
        names.push(j);
        j++;
        if (isOp(toks[j], '<') && toks[j + 1]?.type === 'name' && isOp(toks[j + 2], '>')) j += 3;
        if (isOp(toks[j], ',')) { j++; continue; }
        break;
      }
      if (!isOp(toks[j], '=')) continue;
      const items = splitCommas(j + 1, exprListEnd(j + 1));
      names.forEach((idx, k) => {
        const rng = items[k];
        if (!rng || toks[rng[0]].type !== 'name' || role[rng[0]] !== 'ref') return;
        const r = purePath(rng[0], rng[1]);
        if (r && r.path !== null) {
          aliasSource.add(rng[0]);
          const b = declObj.get(idx);
          if (b) b.alias = r.root && r.path === '' ? '_G' : r.path;
          pathRanges.clear(); // later chains may go through this alias
        }
      });
    }
  }
  pathRanges.clear();
  constCache.clear();

  // functions: name → [bodyStart, bodyEnd]
  const fnRanges = new Map();
  for (let i = 0; i < n; i++) {
    if (!isKw(toks[i], 'function')) continue;
    const end = match[i];
    if (end < 0) continue;
    if (toks[i + 1]?.type === 'name') {
      let j = i + 1;
      let name = toks[j].value;
      j++;
      while ((isOp(toks[j], '.') || isOp(toks[j], ':')) && toks[j + 1]?.type === 'name') { name += '.' + toks[j + 1].value; j += 2; }
      fnRanges.set(name, [i, end]);
    } else if (isOp(toks[i - 1], '=') && toks[i - 2]?.type === 'name') {
      fnRanges.set(toks[i - 2].value, [i, end]);
    }
  }

  const refs = [];
  const refAt = new Map();
  for (let i = 0; i < n; i++) {
    if (role[i] !== 'ref') continue;
    const r = chainAt(i);
    const ref = {
      path: r.path,
      line: toks[i].line,
      idx: i,
      end: r.end,
      call: null,
      dynamic: r.dynamic,
      indirect: r.indirect,
      bareRoot: r.bareRoot,
      root: r.root,
      aliasSource: aliasSource.has(i),
      assigned: isOp(toks[r.end], '=') && !isOp(toks[r.end + 1], '='),
      viaAlias: !!(binding[i] && binding[i].alias),
    };
    if (r.path === null && !r.dynamic) { refAt.set(i, ref); continue; } // a plain local
    if (r.call) ref.call = { args: buildArgs(r.call[0], r.call[1], r.callKind) };
    refs.push(ref);
    refAt.set(i, ref);
  }

  function buildArgs(a, b, kind) {
    const ranges = kind === 'paren' ? splitCommas(a, b) : [[a, b]];
    return ranges.map(([x, y]) => argInfo(x, y));
  }

  function argInfo(a, b) {
    const t = toks[a];
    const arg = { line: t.line, kind: 'other', range: [a, b], name: null, fn: null };
    // folded lazily: resource-wide constants (ext.consts) arrive after every file is analysed
    let parts;
    Object.defineProperty(arg, 'parts', { enumerable: true, get: () => (parts ??= fold(a, b)) });
    if (b - a === 1 && t.type === 'number') arg.kind = 'number';
    else if (b - a === 1 && t.type === 'string') arg.kind = 'string';
    else if (isOp(t, '{') && match[a] === b - 1) arg.kind = 'table';
    else if (isKw(t, 'function') && match[a] === b - 1) { arg.kind = 'function'; arg.fn = { range: [a, b] }; }
    else if (t.type === 'name') {
      const r = chainAt(a);
      if (r.end === b && !r.call) {
        arg.kind = 'name';
        arg.name = binding[a] ? t.value : r.path;
        const fr = fnRanges.get(arg.name);
        if (fr) arg.fn = { range: fr };
      }
    } else if (isOp(t, '-') && b - a === 2 && toks[a + 1].type === 'number') arg.kind = 'number';
    return arg;
  }

  // calls inside a token range (for handler bodies)
  function callsIn([a, b]) {
    const out = [];
    for (const r of refs) if (r.idx > a && r.idx < b && r.call) out.push({ path: r.path, line: r.line });
    return out;
  }
  for (const r of refs) {
    if (!r.call) continue;
    for (const arg of r.call.args) if (arg.fn) arg.fn.calls = callsIn(arg.fn.range);
  }

  // pcall(F, ...) / xpcall(F, handler, ...) → F is called with the remaining args
  for (const r of refs) {
    if (!r.call || (r.path !== 'pcall' && r.path !== 'xpcall')) continue;
    const [f, ...rest] = r.call.args;
    if (!f || f.kind !== 'name') continue;
    const inner = refAt.get(f.range[0]);
    if (!inner || inner.call) continue;
    inner.call = { args: r.path === 'xpcall' ? rest.slice(1) : rest };
    inner.viaPcall = true;
  }

  // strings (for obfuscation / SQL)
  const strings = toks
    .filter((t) => t.type === 'string')
    .map((t) => ({ value: t.value, raw: t.raw, line: t.line, escRun: t.escRun, long: t.long }));

  // numeric table constructors: { 108, 111, 97, ... } — char tables
  const numericTables = [];
  for (let i = 0; i < n; i++) {
    if (!isOp(toks[i], '{') || match[i] < 0) continue;
    let count = 0;
    let other = false;
    for (let j = i + 1; j < match[i]; j++) {
      const t = toks[j];
      if (t.type === 'number') count++;
      else if (isOp(t, ',') || isOp(t, ';')) continue;
      else { other = true; break; }
    }
    if (!other && count > 0) numericTables.push({ line: toks[i].line, count });
  }

  const decls = [];
  for (let i = 0; i < n; i++) if (role[i] === 'decl') decls.push({ name: toks[i].value, line: toks[i].line });

  return {
    lang: 'lua',
    ext,
    exportConsts,
    decls,
    refs,
    strings,
    numericTables,
    errors,
    tokens: toks,
    functions: fnRanges,
    callsIn,
  };
}

// split a format string into literal parts with null for each %-directive
export function formatParts(fmt) {
  const out = [];
  let buf = '';
  for (let i = 0; i < fmt.length; i++) {
    if (fmt[i] !== '%') { buf += fmt[i]; continue; }
    if (fmt[i + 1] === '%') { buf += '%'; i++; continue; }
    const m = /^%[-+ #0-9.]*[a-zA-Z]/.exec(fmt.slice(i));
    if (!m) { buf += '%'; continue; }
    if (/[diuoxXfFeEgGaA]$/.test(m[0])) buf += NUM_MARKER;
    else { out.push(buf, null); buf = ''; }
    i += m[0].length - 1;
  }
  out.push(buf);
  return normalizeParts(out);
}

export function normalizeParts(parts) {
  const out = [];
  for (const p of parts) {
    if (p === '') continue;
    const last = out[out.length - 1];
    if (typeof p === 'string' && typeof last === 'string') out[out.length - 1] = last + p;
    else if (p === null && last === null && out.length) continue;
    else out.push(p);
  }
  return out.length ? out : [''];
}
