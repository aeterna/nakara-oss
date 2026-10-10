#!/usr/bin/env node
// Build one package's release assets into <outDir>:
//   resource package → <resource>-<version>.zip   (folder <resource>/ ready to drop into resources/)
//   devkit           → npm pack tarball
// plus SHA256SUMS and RELEASE_NOTES.md. Deterministic: sorted entries, fixed mtimes, no extra attrs.
// Refuses when: oss.json invalid · resource name ≠ fxmanifest name · version missing from CHANGELOG.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { appendFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { ROOT, fxVersion, validate } from './oss-manifest.mjs';

const [pkg, outArg = 'out'] = process.argv.slice(2);
if (!pkg || !/^[a-z0-9-]+$/.test(pkg)) die('usage: build-release.mjs <package> [outDir]');
const dir = path.join(ROOT, 'packages', pkg);
if (!existsSync(dir)) die(`no such package: packages/${pkg}`);
const out = path.resolve(outArg);
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

function die(msg) {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

function changelogSection(version) {
  const file = path.join(dir, 'CHANGELOG.md');
  if (!existsSync(file)) die(`packages/${pkg}/CHANGELOG.md missing`);
  const text = readFileSync(file, 'utf8');
  const m = text.match(new RegExp(`^##\\s*\\[?${version.replace(/\./g, '\\.')}\\]?[^\\n]*\\n([\\s\\S]*?)(?=^##\\s|$(?![\\s\\S]))`, 'm'));
  if (!m) die(`CHANGELOG.md has no "## ${version}" section — write the notes before releasing`);
  return m[1].trim();
}

function walk(d, base = d) {
  return readdirSync(d, { withFileTypes: true })
    .flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name), base) : [path.relative(base, path.join(d, e.name))]))
    .sort();
}

let kind, tag, version, notes;
const pj = path.join(dir, 'package.json');
if (existsSync(pj)) {
  kind = 'npm';
  version = JSON.parse(readFileSync(pj, 'utf8')).version;
  tag = `fivem-${pkg}@${version}`;
  notes = changelogSection(version);
  cpSync(path.join(ROOT, 'LICENSE'), path.join(dir, 'LICENSE'));
  const tgz = execFileSync('npm', ['pack', '--pack-destination', out, '--ignore-scripts'], { cwd: dir, encoding: 'utf8' }).trim().split('\n').pop();
  console.log(`packed ${tgz}`);
} else {
  kind = 'resource';
  const oss = JSON.parse(readFileSync(path.join(dir, 'oss.json'), 'utf8'));
  const errs = validate(oss);
  if (errs.length) die(`oss.json invalid:\n  ${errs.join('\n  ')}`);
  const fx = fxVersion(dir);
  if (fx.name !== oss.resource) die(`fxmanifest name '${fx.name}' ≠ oss.json resource '${oss.resource}'`);
  if (!fx.version) die('fxmanifest.lua has no version');
  version = fx.version;
  tag = `${oss.resource}@${version}`;
  notes = changelogSection(version);

  const stage = path.join(out, '.stage', oss.resource);
  mkdirSync(stage, { recursive: true });
  for (const rel of walk(dir)) {
    if (rel.startsWith('spec/') || rel.startsWith('.')) continue; // tests stay in the repo
    mkdirSync(path.dirname(path.join(stage, rel)), { recursive: true });
    cpSync(path.join(dir, rel), path.join(stage, rel));
  }
  cpSync(path.join(ROOT, 'LICENSE'), path.join(stage, 'LICENSE'));
  const epoch = new Date('1980-01-01T00:00:00Z');
  const files = walk(stage).map((f) => path.join(oss.resource, f));
  for (const f of files) utimesSync(path.join(out, '.stage', f), epoch, epoch);
  const zip = path.join(out, `${oss.resource}-${version}.zip`);
  execFileSync('zip', ['-X', '-q', '-D', zip, ...files], { cwd: path.join(out, '.stage'), env: { ...process.env, TZ: 'UTC' } });
  rmSync(path.join(out, '.stage'), { recursive: true, force: true });

  const caps = Object.entries(oss.capabilities)
    .map(([k, v]) => `| \`${k}\` | ${typeof v === 'boolean' ? v : JSON.stringify(v)} |`)
    .join('\n');
  notes += `\n\n### Capabilities (oss.json)\n\n| capability | declared |\n|---|---|\n${caps}`;
}

const sums = readdirSync(out)
  .filter((f) => !f.startsWith('.'))
  .sort()
  .map((f) => `${createHash('sha256').update(readFileSync(path.join(out, f))).digest('hex')}  ${f}`)
  .join('\n');
writeFileSync(path.join(out, 'SHA256SUMS'), sums + '\n');
notes += `\n\n### Verify before you install\n\n\`\`\`bash\ngh attestation verify <asset> --repo aeterna/nakara-oss\nsha256sum -c SHA256SUMS\n\`\`\`\n`;
writeFileSync(path.join(out, 'RELEASE_NOTES.md'), notes);

console.log(`${tag} (${kind})\n${sums}`);
if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `tag=${tag}\nkind=${kind}\n`);
