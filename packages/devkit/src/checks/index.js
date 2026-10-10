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
export const builtinChecks = [];
