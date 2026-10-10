// Small helpers shared by the built-in checks. Not part of the public check interface.
import path from 'node:path';

export { lineOf } from '../../fs.js';

// Remove Lua comments (`--[[ ]]`, `--[==[ ]==]`, `-- line`) while keeping every newline and column,
// so line numbers reported against the stripped text match the real file.
export function stripLuaComments(src) {
  return src
    .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/--[^\n]*/g, (m) => ' '.repeat(m.length));
}

// Every file of the given extensions inside the configured resources, each attributed to the
// innermost resource that contains it (a resource nested inside another one owns its own files).
// Returns [{ file, resource, rel }] where `rel` is the path relative to the resource dir, '/'-separated.
export function resourceFiles(ctx, exts) {
  const resources = [...ctx.resources].sort((a, b) => b.dir.length - a.dir.length);
  const seen = new Map();
  for (const file of ctx.resourceFiles(exts)) {
    if (seen.has(file)) continue;
    const owner = resources.find((x) => file.startsWith(x.dir + path.sep));
    if (!owner) continue;
    seen.set(file, {
      file,
      resource: owner,
      rel: path.relative(owner.dir, file).split(path.sep).join('/'),
    });
  }
  return [...seen.values()].sort((a, b) => a.file.localeCompare(b.file));
}

// The finding every check returns when it scanned nothing: a gate that silently reads zero files
// goes green while broken (e.g. a glob that never matched a `[category]` folder).
export function noFiles(ctx, what) {
  const roots = (ctx.config.roots ?? []).join(', ') || '(none)';
  return [{
    file: ctx.config.file ?? ctx.cwd,
    message: `scanned 0 ${what} — check \`roots\` in the config (currently: ${roots}) and the --cwd you ran from`,
  }];
}
