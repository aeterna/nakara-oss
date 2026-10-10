// JS analysis → the same file model as luascan.js. acorn for the AST (module first, script as
// fallback), acorn-walk for traversal. Identifier visitors in acorn-walk only fire for identifiers in
// value position (not property names, object keys or declaration targets), which is exactly the set
// of "references" the rules need.
import * as acorn from 'acorn';
import * as walk from 'acorn-walk';
import { RES_MARKER, convarMarker, normalizeParts } from './luascan.js';

// the global object under its various names: `window.fetch` is `fetch`
const ROOTS = new Set(['globalThis', 'window', 'global', 'self']);

const PARSE_OPTS = {
  ecmaVersion: 'latest',
  locations: true,
  allowHashBang: true,
  allowReturnOutsideFunction: true,
  allowAwaitOutsideFunction: true,
  allowImportExportEverywhere: true,
};

export function parseJs(src) {
  try {
    return { ast: acorn.parse(src, { ...PARSE_OPTS, sourceType: 'module' }) };
  } catch (errModule) {
    try {
      return { ast: acorn.parse(src, { ...PARSE_OPTS, sourceType: 'script' }) };
    } catch {
      return { error: { line: errModule.loc?.line ?? 1, message: errModule.message } };
    }
  }
}

const isFn = (n) => n && (n.type === 'FunctionExpression' || n.type === 'ArrowFunctionExpression' || n.type === 'FunctionDeclaration');
const moduleName = (s) => String(s).replace(/^node:/, '');

export function analyzeJs(src) {
  const parsed = parseJs(src);
  if (parsed.error) return { lang: 'js', refs: [], strings: [], errors: [parsed.error], htmlSinks: [], evalSinks: [], numericTables: [] };
  const ast = parsed.ast;

  // ---- pass 1: aliases, constants, named functions ------------------------------------------
  const aliases = new Map(); // local name → path
  const aliasSourceNodes = new Set();
  const constDecls = new Map(); // name → [init nodes]
  const fnNodes = new Map();
  const constCache = new Map();

  walk.simple(ast, {
    VariableDeclarator(d) {
      if (d.id.type === 'Identifier' && d.init) {
        const list = constDecls.get(d.id.name) ?? [];
        list.push(d.init);
        constDecls.set(d.id.name, list);
        if (isFn(d.init)) fnNodes.set(d.id.name, d.init);
      }
    },
    FunctionDeclaration(f) {
      if (f.id) fnNodes.set(f.id.name, f);
    },
    ImportDeclaration(d) {
      const mod = 'module:' + moduleName(d.source.value);
      for (const s of d.specifiers) {
        if (s.type === 'ImportSpecifier') aliases.set(s.local.name, `${mod}.${s.imported.name ?? s.imported.value}`);
        else aliases.set(s.local.name, mod);
      }
    },
  });
  // assignments `x = ...` make a name non-constant
  walk.simple(ast, {
    AssignmentExpression(a) {
      if (a.left.type === 'Identifier') {
        const list = constDecls.get(a.left.name) ?? [];
        list.push(null);
        constDecls.set(a.left.name, list);
      }
    },
  });
  // aliases from declarators, resolved in source order so alias-of-alias works
  const declarators = [];
  walk.simple(ast, { VariableDeclarator(d) { declarators.push(d); } });
  declarators.sort((x, y) => x.start - y.start);
  for (const d of declarators) {
    if (!d.init) continue;
    const p = pathOf(d.init);
    if (p === null || p === undefined) continue;
    if (d.id.type === 'Identifier') {
      aliases.set(d.id.name, p === '' ? 'globalThis' : p);
      aliasSourceNodes.add(d.init);
    } else if (d.id.type === 'ObjectPattern') {
      for (const prop of d.id.properties) {
        if (prop.type !== 'Property' || prop.computed) continue;
        const key = prop.key.name ?? prop.key.value;
        const local = prop.value.type === 'Identifier' ? prop.value : prop.value.type === 'AssignmentPattern' ? prop.value.left : null;
        if (local?.type === 'Identifier') aliases.set(local.name, p ? `${p}.${key}` : key);
      }
      aliasSourceNodes.add(d.init);
    }
  }

  // ---- paths and folding ----------------------------------------------------------------------
  // path of an expression, '' for the global object, null if not a static path.
  // `require('x')` → 'module:x'
  function pathOf(node, depth = 0) {
    if (!node || depth > 20) return null;
    switch (node.type) {
      case 'Identifier': {
        if (aliases.has(node.name)) {
          const a = aliases.get(node.name);
          return ROOTS.has(a) ? '' : a;
        }
        return ROOTS.has(node.name) ? '' : node.name;
      }
      case 'ThisExpression':
        return null;
      case 'ChainExpression':
        return pathOf(node.expression, depth + 1);
      case 'ParenthesizedExpression':
        return pathOf(node.expression, depth + 1);
      case 'MemberExpression': {
        const obj = pathOf(node.object, depth + 1);
        if (obj === null) return null;
        const key = propName(node);
        if (key === null) return null;
        return obj === '' ? key : `${obj}.${key}`;
      }
      case 'CallExpression': {
        if (node.callee.type === 'Identifier' && node.callee.name === 'require' && node.arguments.length === 1) {
          const f = fold(node.arguments[0]);
          if (f.length === 1 && typeof f[0] === 'string') return 'module:' + moduleName(f[0]);
        }
        return null;
      }
      default:
        return null;
    }
  }

  function propName(m) {
    if (!m.computed) return m.property.name ?? null;
    const f = fold(m.property);
    return f.length === 1 && typeof f[0] === 'string' ? f[0] : null;
  }

  function fold(node, depth = 0) {
    if (!node || depth > 12) return [null];
    switch (node.type) {
      case 'Literal':
        if (typeof node.value === 'string') return [node.value];
        if (typeof node.value === 'number') return [String(node.value)];
        return [null];
      case 'TemplateLiteral': {
        const out = [];
        node.quasis.forEach((q, i) => {
          out.push(q.value.cooked ?? q.value.raw);
          if (i < node.expressions.length) out.push(...fold(node.expressions[i], depth + 1));
        });
        return normalizeParts(out);
      }
      case 'BinaryExpression':
        if (node.operator !== '+') return [null];
        return normalizeParts([...fold(node.left, depth + 1), ...fold(node.right, depth + 1)]);
      case 'ParenthesizedExpression':
        return fold(node.expression, depth + 1);
      case 'ConditionalExpression':
      case 'LogicalExpression': {
        // `inGame ? GetParentResourceName() : 'dev'` — the NUI resource name with a browser-dev
        // fallback. Only a fallback that cannot be a network host (no '.', ':' or '/', not
        // localhost) keeps the resource marker; anything else is unknown.
        const branches = node.type === 'ConditionalExpression' ? [node.consequent, node.alternate] : [node.left, node.right];
        const folded = branches.map((b) => fold(b, depth + 1));
        const isMarker = (f) => f.length === 1 && f[0] === RES_MARKER;
        const harmless = (f) => isMarker(f) || (f.length === 1 && typeof f[0] === 'string' && !/[.:/]/.test(f[0]) && f[0].toLowerCase() !== 'localhost');
        const markerBranch = node.type === 'LogicalExpression' && node.operator === '&&' ? folded[1] : null;
        if (markerBranch && isMarker(markerBranch)) return [RES_MARKER];
        if (folded.some(isMarker) && folded.every(harmless)) return [RES_MARKER];
        return [null];
      }
      case 'CallExpression':
        {
          const p = pathOf(node.callee);
          if (p === 'GetParentResourceName' || p === 'GetCurrentResourceName') return [RES_MARKER];
          if ((p === 'GetConvar' || p === 'GetConvarInt' || p === 'GetConvarFloat') && node.arguments[0]) {
            const name = fold(node.arguments[0], depth + 1);
            if (name.length === 1 && typeof name[0] === 'string' && !/[\u0001-\u0003]/.test(name[0])) return [convarMarker(name[0])];
          }
        }
        return [null];
      case 'Identifier': {
        const decls = constDecls.get(node.name);
        if (!decls || decls.length !== 1 || !decls[0]) return [null];
        if (constCache.has(node.name)) return constCache.get(node.name) ?? [null];
        constCache.set(node.name, null);
        const v = fold(decls[0], depth + 1);
        constCache.set(node.name, v);
        return v;
      }
      default:
        return [null];
    }
  }

  function argInfo(node) {
    const arg = { line: node.loc.start.line, parts: fold(node), kind: 'other', name: null, fn: null, node };
    if (node.type === 'Literal' && typeof node.value === 'number') arg.kind = 'number';
    else if (node.type === 'Literal' && typeof node.value === 'string') arg.kind = 'string';
    else if (node.type === 'TemplateLiteral') arg.kind = node.expressions.length ? 'template' : 'string';
    else if (node.type === 'SpreadElement') arg.kind = 'spread';
    else if (node.type === 'ObjectExpression') arg.kind = 'table';
    else if (isFn(node)) { arg.kind = 'function'; arg.fn = { node }; }
    else if (node.type === 'Identifier' || node.type === 'MemberExpression') {
      arg.kind = 'name';
      arg.name = node.type === 'Identifier' ? node.name : pathOf(node);
      const f = node.type === 'Identifier' && fnNodes.get(node.name);
      if (f) arg.fn = { node: f };
    }
    return arg;
  }

  function callsIn(fnNode) {
    const out = [];
    walk.simple(fnNode.body, {
      CallExpression(c) {
        const p = pathOf(c.callee);
        if (p) out.push({ path: p, line: c.loc.start.line });
      },
    });
    return out;
  }

  // ---- pass 2: references ---------------------------------------------------------------------
  const refs = [];
  const strings = [];
  const htmlSinks = [];
  const evalSinks = [];

  function addRef(top, ancestors, path, extra = {}) {
    const parent = ancestors[ancestors.length - 1];
    const ref = {
      path,
      line: top.loc.start.line,
      call: null,
      aliasSource: aliasSourceNodes.has(top),
      dynamic: false,
      ...extra,
    };
    if (parent && (parent.type === 'CallExpression' || parent.type === 'NewExpression') && parent.callee === top) {
      ref.call = { args: parent.arguments.map(argInfo), isNew: parent.type === 'NewExpression' };
      for (const a of ref.call.args) if (a.fn) a.fn.calls = callsIn(a.fn.node);
    }
    if (parent && parent.type === 'BinaryExpression' && parent.operator === 'instanceof') ref.instanceofRhs = parent.right === top;
    if (parent && parent.type === 'UnaryExpression' && parent.operator === 'typeof') ref.typeofOperand = true;
    refs.push(ref);
    return ref;
  }

  // climb from `node` through member accesses; returns [top, remaining ancestors]
  function climb(node, ancestors) {
    let cur = node;
    let k = ancestors.length - 2; // ancestors includes node itself as last element
    for (; k >= 0; k--) {
      const p = ancestors[k];
      if (p.type === 'MemberExpression' && p.object === cur) { cur = p; continue; }
      if (p.type === 'ChainExpression' || p.type === 'ParenthesizedExpression') { cur = p; continue; }
      if (p.type === 'CallExpression' && p.callee === cur && cur.type === 'Identifier' && cur.name === 'require') {
        // require('x').y — keep climbing from the call
        cur = p;
        continue;
      }
      break;
    }
    return [cur, ancestors.slice(0, k + 1)];
  }

  walk.ancestor(ast, {
    Identifier(node, _st, ancestors) {
      const [top, rest] = climb(node, ancestors);
      let recorded = false;
      if (node.name === 'require') {
        // the require call itself (for dynamic require) — and the module chain, if literal
        const call = ancestors[ancestors.length - 2];
        if (call && call.type === 'CallExpression' && call.callee === node) {
          refs.push({ path: 'require', line: node.loc.start.line, call: { args: call.arguments.map(argInfo) } });
          recorded = true;
        }
      }
      const p = pathOf(top);
      if (p === null) {
        // dynamic index on the global object: window[x], globalThis[a + b]
        let m = node;
        let k = ancestors.length - 2;
        while (k >= 0 && ancestors[k].type === 'MemberExpression' && ancestors[k].object === m) {
          const inner = pathOf(m);
          if (inner === '' && propName(ancestors[k]) === null) {
            addRef(ancestors[k], ancestors.slice(0, k), null, { dynamic: true, line: node.loc.start.line });
            break;
          }
          m = ancestors[k];
          k--;
        }
        return;
      }
      if (p === '') return; // bare `window` / `globalThis`
      if (recorded && p === 'require') return; // require(<dynamic>) — already recorded above
      addRef(top, rest, p);
    },
    ImportExpression(node) {
      refs.push({ path: 'import', line: node.loc.start.line, call: { args: [argInfo(node.source)] } });
      const f = fold(node.source);
      if (f.length === 1 && typeof f[0] === 'string') refs.push({ path: 'module:' + moduleName(f[0]), line: node.loc.start.line, call: null });
    },
    ImportDeclaration(node) {
      refs.push({ path: 'module:' + moduleName(node.source.value), line: node.loc.start.line, call: null, importDecl: true });
    },
    ExportAllDeclaration(node) {
      refs.push({ path: 'module:' + moduleName(node.source.value), line: node.loc.start.line, call: null, importDecl: true });
    },
    ExportNamedDeclaration(node) {
      if (node.source) refs.push({ path: 'module:' + moduleName(node.source.value), line: node.loc.start.line, call: null, importDecl: true });
    },
    Literal(node) {
      if (typeof node.value === 'string') strings.push({ value: node.value, raw: node.raw, line: node.loc.start.line, escRun: escRun(node.raw) });
    },
    TemplateElement(node) {
      strings.push({ value: node.value.cooked ?? node.value.raw, raw: node.value.raw, line: node.loc.start.line, escRun: escRun(node.value.raw) });
    },
    AssignmentExpression(node) {
      const l = node.left;
      if (l.type !== 'MemberExpression') return;
      const key = propName(l);
      if (key !== 'innerHTML' && key !== 'outerHTML') return;
      if (!isStaticString(node.right)) htmlSinks.push({ line: node.loc.start.line, sink: key });
    },
    CallExpression(node) {
      const c = node.callee;
      if (c.type === 'MemberExpression') {
        const key = propName(c);
        if (key === 'insertAdjacentHTML' && node.arguments[1] && !isStaticString(node.arguments[1])) {
          htmlSinks.push({ line: node.loc.start.line, sink: 'insertAdjacentHTML' });
        }
        if ((key === 'write' || key === 'writeln') && pathOf(c.object) === 'document' && node.arguments.some((a) => !isStaticString(a))) {
          htmlSinks.push({ line: node.loc.start.line, sink: `document.${key}` });
        }
        if (key === 'html' && node.arguments.length === 1 && !isStaticString(node.arguments[0]) &&
          c.object.type === 'CallExpression' && ['$', 'jQuery'].includes(c.object.callee.name)) {
          htmlSinks.push({ line: node.loc.start.line, sink: 'jQuery .html()' });
        }
        // ''.constructor.constructor('code')() — Function without saying Function
        if (key === 'constructor' && node.arguments.length) evalSinks.push({ line: node.loc.start.line, what: '.constructor(...) call' });
      }
    },
    NewExpression(node) {
      const c = node.callee;
      if (c.type === 'MemberExpression' && propName(c) === 'constructor' && node.arguments.length) {
        evalSinks.push({ line: node.loc.start.line, what: 'new ....constructor(...)' });
      }
    },
  });

  return { lang: 'js', refs, strings, errors: [], htmlSinks, evalSinks, numericTables: [], ast };
}

function isStaticString(n) {
  if (!n) return true;
  if (n.type === 'Literal') return typeof n.value === 'string' || n.value === null || typeof n.value === 'number';
  if (n.type === 'TemplateLiteral') return n.expressions.length === 0;
  if (n.type === 'BinaryExpression' && n.operator === '+') return isStaticString(n.left) && isStaticString(n.right);
  return false;
}

// longest run of consecutive \xNN, \uNNNN, \u{...} or octal escapes in a raw JS string
export function escRun(raw) {
  let max = 0;
  let run = 0;
  const re = /\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|u\{[0-9a-fA-F]+\}|[0-7]{1,3})|\\.|[^\\]/gs;
  let m;
  while ((m = re.exec(raw))) {
    if (m[1]) { run++; if (run > max) max = run; } else run = 0;
  }
  return max;
}
