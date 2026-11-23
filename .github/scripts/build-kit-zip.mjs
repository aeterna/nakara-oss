#!/usr/bin/env node
// Build the combined Starter Kit zip into <outDir> (ADR 0005 decision 10):
//   aeterna-starter-kit-<version>.zip = every `ensure aeterna_*` resource of kits/starter/resources.cfg, taken from
//   its own GitHub release (already built and attested by release.yml), plus resources.cfg, README.md and LICENSE,
//   all under one category folder `[aeterna_kit]/`: unzipped into resources/ it is found by FXServer as it is
//   (a folder without brackets would be taken for a resource and its contents never scanned).
// plus SHA256SUMS and RELEASE_NOTES.md. The kit version is the newest "## [x.y.z]" of kits/starter/CHANGELOG.md.
// Refuses when: a package release is missing · its zip does not match that release's SHA256SUMS · a package tag is
// not on the commit being built (all packages must be released from the same commit as the kit).
// Deterministic like build-release.mjs: sorted entries, fixed mtimes, no extra attrs.
// Offline mode for local checks: KIT_ZIP_DIR=<dir with the package zips + SHA256SUMS.<resource>> skips gh calls.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { appendFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, utimesSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { ROOT, fxVersion } from './oss-manifest.mjs';

const KIT = path.join(ROOT, 'kits', 'starter');
const REPO = process.env.GITHUB_REPOSITORY || 'aeterna/nakara-oss';
const out = path.resolve(process.argv[2] || 'out');
const offline = process.env.KIT_ZIP_DIR ? path.resolve(process.env.KIT_ZIP_DIR) : null;

function die(msg) {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

const sha256 = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');
const gh = (args) => execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }).trim();

// The resources of the kit, in resources.cfg order.
export function kitResources(cfgText) {
  return cfgText
    .split('\n')
    .map((l) => l.trim().match(/^ensure\s+(aeterna_[a-z0-9_]+)\s*$/))
    .filter(Boolean)
    .map((m) => m[1]);
}

// The newest version heading of the kit changelog.
export function kitVersion(changelog) {
  const m = changelog.match(/^##\s*\[?(\d+\.\d+\.\d+)\]?/m);
  return m ? m[1] : null;
}

// The notes for one version of the kit changelog.
export function kitNotes(changelog, version) {
  const m = changelog.match(new RegExp(`^##\\s*\\[?${version.replace(/\./g, '\\.')}\\]?[^\\n]*\\n([\\s\\S]*?)(?=^##\\s|$(?![\\s\\S]))`, 'm'));
  return m ? m[1].trim() : null;
}

// The package folder whose oss.json names `resource`.
function packageDir(resource) {
  for (const d of readdirSync(path.join(ROOT, 'packages'))) {
    const oss = path.join(ROOT, 'packages', d, 'oss.json');
    if (existsSync(oss) && JSON.parse(readFileSync(oss, 'utf8')).resource === resource) return path.join(ROOT, 'packages', d);
  }
  return null;
}

function walk(d, base = d) {
  return readdirSync(d, { withFileTypes: true })
    .flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name), base) : [path.relative(base, path.join(d, e.name))]))
    .sort();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const changelogFile = path.join(KIT, 'CHANGELOG.md');
  if (!existsSync(changelogFile)) die('kits/starter/CHANGELOG.md missing');
  const changelog = readFileSync(changelogFile, 'utf8');
  const version = kitVersion(changelog);
  if (!version) die('kits/starter/CHANGELOG.md has no "## [x.y.z]" section');
  const notesBody = kitNotes(changelog, version);
  const resources = kitResources(readFileSync(path.join(KIT, 'resources.cfg'), 'utf8'));
  if (resources.length === 0) die('kits/starter/resources.cfg ensures no aeterna_* resource');
  const head = process.env.GITHUB_SHA || execFileSync('git', ['rev-parse', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim();

  rmSync(out, { recursive: true, force: true });
  const dl = path.join(out, '.dl');
  const stage = path.join(out, '.stage');
  const top = '[aeterna_kit]';
  mkdirSync(dl, { recursive: true });
  mkdirSync(path.join(stage, top), { recursive: true });

  const rows = [];
  for (const res of resources) {
    const dir = packageDir(res);
    if (!dir) die(`no package declares resource ${res}`);
    const ver = fxVersion(dir).version;
    const tag = `${res}@${ver}`;
    const zip = `${res}-${ver}.zip`;
    let zipPath;
    let sums;
    if (offline) {
      zipPath = path.join(offline, zip);
      const sumsFile = path.join(offline, `SHA256SUMS.${res}`);
      if (!existsSync(zipPath) || !existsSync(sumsFile)) die(`offline: ${zip} or SHA256SUMS.${res} missing in ${offline}`);
      sums = readFileSync(sumsFile, 'utf8');
    } else {
      const commit = gh(['api', `repos/${REPO}/commits/${encodeURIComponent(tag)}`, '--jq', '.sha']);
      if (commit !== head) die(`${tag} is on ${commit.slice(0, 12)}, not on ${head.slice(0, 12)}: release every package from this commit first`);
      const into = path.join(dl, res);
      mkdirSync(into, { recursive: true });
      gh(['release', 'download', tag, '--repo', REPO, '--dir', into, '--pattern', zip, '--pattern', 'SHA256SUMS']);
      zipPath = path.join(into, zip);
      sums = readFileSync(path.join(into, 'SHA256SUMS'), 'utf8');
    }
    const want = sums.split('\n').map((l) => l.trim().split(/\s+/)).find((p) => p[1] === zip)?.[0];
    const got = sha256(zipPath);
    if (!want || want !== got) die(`${zip}: sha256 ${got} does not match its release's SHA256SUMS (${want ?? 'not listed'})`);
    execFileSync('unzip', ['-q', zipPath, '-d', path.join(stage, top)]);
    rows.push(`| \`${res}\` | ${ver} | \`${got.slice(0, 16)}…\` |`);
  }
  cpSync(path.join(KIT, 'resources.cfg'), path.join(stage, top, 'resources.cfg'));
  cpSync(path.join(KIT, 'README.md'), path.join(stage, top, 'README.md'));
  cpSync(path.join(ROOT, 'LICENSE'), path.join(stage, top, 'LICENSE'));

  const epoch = new Date('1980-01-01T00:00:00Z');
  const files = walk(stage);
  for (const f of files) utimesSync(path.join(stage, f), epoch, epoch);
  const zipName = `aeterna-starter-kit-${version}.zip`;
  execFileSync('zip', ['-X', '-q', '-D', path.join(out, zipName), ...files], { cwd: stage, env: { ...process.env, TZ: 'UTC' } });
  rmSync(stage, { recursive: true, force: true });
  rmSync(dl, { recursive: true, force: true });

  const sumsOut = `${sha256(path.join(out, zipName))}  ${zipName}`;
  writeFileSync(path.join(out, 'SHA256SUMS'), sumsOut + '\n');
  const tag = `aeterna-starter-kit@${version}`;
  let notes = (notesBody || '').trim();
  notes += `\n\n### What is inside\n\nUnzip into \`resources/\` (you get \`resources/[aeterna_kit]/\`), then copy \`[aeterna_kit]/resources.cfg\` into \`server.cfg\`.\n\n| resource | version | zip sha256 |\n|---|---|---|\n${rows.join('\n')}\n`;
  notes += `\nEach resource is the same zip as its own release (\`<resource>@<version>\`), checked against that release's SHA256SUMS.\n`;
  notes += `\n### Verify before you install\n\n\`\`\`bash\ngh attestation verify ${zipName} --repo aeterna/nakara-oss --signer-workflow aeterna/nakara-oss/.github/workflows/release.yml\nsha256sum -c SHA256SUMS\n\`\`\`\n`;
  writeFileSync(path.join(out, 'RELEASE_NOTES.md'), notes);
  console.log(`${tag} (kit)\n${sumsOut}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `tag=${tag}\nkind=kit\n`);
}
