// Registry of built-in checks. Each module default-exports:
//
//   {
//     id: 'export-calls',                 // kebab-case, used in config + CLI
//     description: 'one line',
//     defaults: { ... },                  // options; project overrides via checks.<id> in config
//     run(ctx, options) => Finding[]      // may be async; Finding = { file, line?, message, severity? }
//   }
//
// severity defaults to 'error'. A check that found ZERO input files must return an error finding
// saying so — a lint that silently scans nothing is how a gate goes green while broken.
import exportCalls from './export-calls.js';
import exportFuncref from './export-funcref.js';
import exportSelfParam from './export-self-param.js';
import loadtimeGlobals from './loadtime-globals.js';
import luaAndNilOr from './lua-and-nil-or.js';
import luaChunkLocals from './lua-chunk-locals.js';
import nuiCallbacks from './nui-callbacks.js';
import nuiEscape from './nui-escape.js';
import nulBytes from './nul-bytes.js';

export const builtinChecks = [
  exportCalls,
  exportSelfParam,
  exportFuncref,
  nuiCallbacks,
  nuiEscape,
  luaAndNilOr,
  luaChunkLocals,
  loadtimeGlobals,
  nulBytes,
];
