// Findings the scanner raises about itself or its input rather than about a code pattern. They are
// rules so they have ids, docs and appear in the rule list; the engine (../index.js) emits them.
export const parseError = {
  id: 'parse-error',
  severity: 'error',
  kind: 'meta',
  description: 'a Lua or JS file could not be lexed/parsed',
  docs: 'A file the scanner cannot read is a file it cannot vouch for. Lua that fails to lex also fails to load in FXServer; JS that acorn cannot parse may use syntax the scanner does not understand.',
};
export const invalidAllow = {
  id: 'invalid-allow',
  severity: 'error',
  kind: 'meta',
  suppressible: false,
  description: 'a safety.allow entry is malformed, has no reason, names an unknown rule, or targets a rule that cannot be allowlisted',
  docs: 'Every exception is a decision someone has to be able to read later. An entry without a reason is rejected.',
};
export const noResources = {
  id: 'no-resources',
  severity: 'error',
  kind: 'meta',
  suppressible: false,
  description: 'no resource (fxmanifest.lua) found under the scanned paths',
  docs: 'A scan of nothing passes. That is how a gate goes green while broken, so it is an error.',
};
export const unscanned = {
  id: 'unscanned',
  severity: 'warn',
  kind: 'meta',
  description: 'source files in languages the scanner does not parse (.ts, .tsx, .jsx, .vue, .svelte)',
  docs: 'TypeScript/JSX/Vue sources are not analysed. Their built output is: build in CI and scan the result, or review these files by hand.',
};
