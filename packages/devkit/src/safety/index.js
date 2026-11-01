// fivem-devkit safety — the automated gate between a pull request and a server that runs it.
//
// runSafety({ cwd, config, paths }) → Finding[] { file, line?, message, severity, check: 'safety/<rule-id>' }
//   paths empty → every resource under config.roots; otherwise each path is a resource directory or
//   a directory containing resources (FiveM [category] folders are fine).
//
// Rules: ./rules/*.js · threat model and rule rationale: docs/safety.md
import path from 'node:path';
import { createContext } from '../context.js';
import { walk } from '../fs.js';
import { findResources } from '../manifest.js';
import { loadOss } from './capabilities.js';
import { pathMatches } from './glob.js';
import { UNSUPPORTED_EXTS, buildEntry, buildModel, classifier } from './model.js';
import { literal, netRegistrations } from './rules/util.js';
import { invalidAllow, noResources, parseError, unscanned } from './rules/meta.js';
import { allRules, ruleById, safetyRules } from './rules/index.js';

export { capabilityDiff } from './capabilities.js';
export { allRules as safetyRules };

// Only VCS metadata and installed dependencies are skipped. `dist/` is scanned on purpose: committed
// build output is exactly where a payload would hide.
export const SAFETY_IGNORE = ['.git', 'node_modules'];
export const DEFAULT_RATE_LIMIT_FNS = ['NakaraCore.rateLimit', 'lib.callback', 'rateLimit'];

export function safetyOptions(config) {
  const s = config?.safety ?? {};
  return {
    allow: s.allow ?? {},
    allowAssets: s.allowAssets === true,
    requireManifest: s.requireManifest !== false,
    rateLimitFns: Array.isArray(s.rateLimitFns) && s.rateLimitFns.length ? s.rateLimitFns : DEFAULT_RATE_LIMIT_FNS,
  };
}

// → { entries: Map<ruleId, [{ path, reason }]>, findings }
export function validateAllow(allow, configFile) {
  const findings = [];
  const entries = new Map();
  const bad = (message) => findings.push({ file: configFile, message, severity: 'error', check: `safety/${invalidAllow.id}` });
  if (allow === null || typeof allow !== 'object' || Array.isArray(allow)) {
    bad('safety.allow must be an object of { "<rule-id>": [{ "path": "...", "reason": "..." }] }');
    return { entries, findings };
  }
  for (const [id, list] of Object.entries(allow)) {
    const rule = ruleById.get(id);
    if (!rule) { bad(`safety.allow["${id}"]: unknown rule id`); continue; }
    if (rule.suppressible === false) {
      bad(`safety.allow["${id}"]: this rule cannot be allowlisted${id === 'secret-convar' || id === 'ace-command' ? ' — it guards against takeover of the server that runs the code' : ''}`);
      continue;
    }
    if (!Array.isArray(list)) { bad(`safety.allow["${id}"] must be an array`); continue; }
    const ok = [];
    list.forEach((e, i) => {
      const where = `safety.allow["${id}"][${i}]`;
      if (typeof e === 'string') return bad(`${where}: "${e}" has no reason — use { "path": "${e}", "reason": "why this is safe" }`);
      if (!e || typeof e !== 'object' || typeof e.path !== 'string' || !e.path.trim() || e.path.trim() === '.' || e.path.trim() === '*' || e.path.trim() === '**') {
        return bad(`${where}: needs a "path" naming specific files (glob or prefix)`);
      }
      if (typeof e.reason !== 'string' || e.reason.trim().length < 3) return bad(`${where} (${e.path}): needs a "reason"`);
      ok.push({ path: e.path.trim(), reason: e.reason.trim() });
    });
    if (ok.length) entries.set(id, ok);
  }
  return { entries, findings };
}

function newUsed() {
  return {
    http: new Set(), commands: new Set(), registeredCommands: new Set(), httpHandlers: new Set(),
    convarsRead: new Set(), convarsWrite: new Set(),
    netServer: new Set(), netClient: new Set(), nui: false, tables: new Set(), ddl: false, filesWrite: new Set(),
  };
}

export function scanResource(res, opts, resourceDirs = new Set([res.dir])) {
  const oss = loadOss(res.dir);
  const enforce = oss.exists || opts.requireManifest;
  const rctx = {
    res, oss, caps: oss.caps, opts,
    names: new Set([res.name, oss.data?.resource].filter((x) => typeof x === 'string' && x)),
    used: newUsed(),
    netServerNames: new Set(),
  };
  const findings = [];
  const emitter = (rule, defaultFile) => (line, message, extra = {}) => {
    findings.push({
      file: extra.file ?? defaultFile,
      ...(line ? { line } : {}),
      message,
      severity: extra.severity ?? rule.severity,
      check: `safety/${rule.id}`,
      resourceDir: res.dir,
    });
  };
  const active = safetyRules.filter((r) => enforce || !r.needsManifest);
  const classify = classifier(res);

  // files of this resource only (not of a resource nested inside it)
  const owner = (f) => {
    let d = path.dirname(f);
    while (!resourceDirs.has(d)) {
      const up = path.dirname(d);
      if (up === d) return null;
      d = up;
    }
    return d;
  };
  const files = walk(res.dir, { ignore: SAFETY_IGNORE }).filter((f) => owner(f) === res.dir).sort();

  const models = [];
  let unsupported = [];
  for (const file of files) {
    let entry;
    try {
      entry = buildEntry(file, res.dir);
    } catch (err) {
      emitter(parseError, file)(null, `cannot read file: ${err.message}`);
      continue;
    }
    for (const rule of active) if (rule.checkFile) rule.checkFile(entry, rctx, emitter(rule, file));
    if (entry.binary || entry.bytecode || entry.minified) continue;
    if (UNSUPPORTED_EXTS.includes(entry.ext)) { unsupported.push(entry.rel); continue; }
    const model = buildModel(entry, classify);
    if (!model) continue;
    for (const e of model.errors ?? []) emitter(parseError, file)(e.line, `${model.lang === 'lua' ? 'Lua lexer' : 'JS parser'}: ${e.message}`);
    models.push(model);
  }

  // resource-wide constants (Config.url assigned once in config.lua, used in server/main.lua)
  const totals = new Map();
  const providers = new Map();
  for (const m of models) {
    if (m.lang !== 'lua' || !m.exportConsts) continue;
    for (const [key, c] of m.exportConsts()) {
      totals.set(key, (totals.get(key) ?? 0) + c.count);
      providers.set(key, c.get);
    }
  }
  const consts = new Map([...providers].filter(([k]) => totals.get(k) === 1));
  for (const m of models) if (m.ext) Object.assign(m.ext, { consts, totals });

  for (const m of models) {
    if (!m.isServer) continue;
    for (const reg of netRegistrations(m)) {
      const name = literal(reg.name);
      if (name !== null) rctx.netServerNames.add(name);
    }
  }
  for (const m of models) for (const rule of active) if (rule.check) rule.check(m, rctx, emitter(rule, m.file));
  for (const rule of active) if (rule.checkResource) rule.checkResource(rctx, emitter(rule, res.manifestPath));

  if (unsupported.length) {
    emitter(unscanned, res.manifestPath)(null, `${unsupported.length} file(s) in languages the scanner does not parse were not scanned (e.g. ${unsupported.slice(0, 3).join(', ')})`);
  }
  return findings;
}

export async function runSafety({ cwd, config = {}, paths = [] }) {
  const opts = safetyOptions(config);
  const configFile = config.file ?? path.join(cwd, '.fivem-devkit.json');
  const { entries: allow, findings } = validateAllow(opts.allow, configFile);

  let resources = [];
  const nothing = (where) => findings.push({ file: where, message: `no resource (fxmanifest.lua) found under ${where}`, severity: 'error', check: `safety/${noResources.id}` });
  if (paths.length) {
    for (const p of paths) {
      const found = findResources(cwd, [p], SAFETY_IGNORE);
      if (!found.length) nothing(path.resolve(cwd, p));
      resources.push(...found);
    }
  } else {
    resources = createContext({ cwd, config }).resources;
    if (!resources.length) nothing((config.roots ?? ['resources']).map((r) => path.resolve(cwd, r)).join(', '));
  }
  const seen = new Set();
  resources = resources.filter((r) => !seen.has(r.dir) && seen.add(r.dir));
  const dirs = new Set(resources.map((r) => r.dir));

  for (const res of resources) findings.push(...scanResource(res, opts, dirs));

  const allowed = (f) => {
    const id = f.check.replace(/^safety\//, '');
    const list = allow.get(id);
    if (!list || !f.file || ruleById.get(id)?.suppressible === false) return false;
    const fromCwd = path.relative(cwd, f.file).split(path.sep).join('/');
    const fromRes = f.resourceDir ? path.relative(f.resourceDir, f.file).split(path.sep).join('/') : null;
    return list.some((e) => pathMatches(e.path, fromCwd) || (fromRes !== null && pathMatches(e.path, fromRes)));
  };

  const dedupe = new Set();
  return findings
    .filter((f) => !allowed(f))
    .filter((f) => {
      const k = `${f.file}\0${f.line}\0${f.check}\0${f.message}`;
      return !dedupe.has(k) && dedupe.add(k);
    })
    .map(({ resourceDir, ...f }) => f)
    .sort((a, b) => (a.file ?? '').localeCompare(b.file ?? '') || (a.line ?? 0) - (b.line ?? 0) || a.check.localeCompare(b.check));
}
