#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { builtinChecks } from '../src/checks/index.js';
import { loadConfig, runChecks } from '../src/index.js';
import { format } from '../src/report.js';
import { runSafety } from '../src/safety/index.js';

const USAGE = `fivem-devkit <command> [options]

commands:
  check [ids...]     run static checks (all enabled checks by default)
  safety [paths...]  scan for dangerous code + capability violations (default: config roots)
  list               list built-in checks

options:
  --config <file>    config file (default: ./.fivem-devkit.json)
  --format <fmt>     text | json | github   (default: github when $GITHUB_ACTIONS, else text)
  --cwd <dir>        project root (default: current directory)
`;

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    config: { type: 'string' },
    format: { type: 'string' },
    cwd: { type: 'string' },
    help: { type: 'boolean', short: 'h' },
  },
});

const [cmd, ...rest] = positionals;
if (values.help || !cmd) {
  process.stdout.write(USAGE);
  process.exit(cmd ? 0 : 2);
}

const cwd = values.cwd ? new URL(values.cwd, `file://${process.cwd()}/`).pathname : process.cwd();
const fmt = values.format ?? (process.env.GITHUB_ACTIONS ? 'github' : 'text');

try {
  const config = loadConfig(cwd, values.config);
  let findings;
  if (cmd === 'list') {
    for (const c of builtinChecks) console.log(`${c.id.padEnd(24)} ${c.description}`);
    process.exit(0);
  } else if (cmd === 'check') {
    findings = await runChecks({ cwd, config, only: rest });
  } else if (cmd === 'safety') {
    findings = await runSafety({ cwd, config, paths: rest });
  } else {
    process.stderr.write(`unknown command: ${cmd}\n\n${USAGE}`);
    process.exit(2);
  }
  const errors = findings.filter((f) => f.severity !== 'warn');
  if (findings.length) console.log(format(findings, fmt, cwd));
  console.log(`\n${cmd}: ${errors.length} error(s), ${findings.length - errors.length} warning(s)`);
  process.exit(errors.length ? 1 : 0);
} catch (err) {
  console.error(`fivem-devkit: ${err.message}`);
  process.exit(2);
}
