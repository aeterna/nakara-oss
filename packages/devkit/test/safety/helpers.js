// Builds a throwaway resource on disk and runs the real scanner over it, so every test exercises
// the same path a CI run does (manifest parsing, file classification, oss.json, allowlist).
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runSafety } from '../../src/safety/index.js';

export const MANIFEST = `fx_version 'cerulean'
game 'gta5'
lua54 'yes'
shared_scripts { 'shared/*.lua' }
client_scripts { 'client/*.lua', 'client/*.js' }
server_scripts { 'server/*.lua', 'server/*.js' }
`;

export function oss(caps = {}) {
  return {
    name: 'test-package',
    resource: 'nakara_test',
    capabilities: {
      http: [], commands: [], registeredCommands: [],
      convars: { read: [], write: [] },
      netEvents: { server: [], client: [] },
      nui: false,
      db: { tables: [], ddl: false },
      files: { write: [] },
      ...caps,
    },
  };
}

// files: { 'server/main.lua': '...', ... } — strings or Buffers
export function makeResource(files, { manifest = MANIFEST, ossJson = oss(), name = 'nakara_test' } = {}) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'devkit-safety-'));
  const dir = path.join(root, name);
  mkdirSync(dir, { recursive: true });
  if (manifest !== null) writeFileSync(path.join(dir, 'fxmanifest.lua'), manifest);
  if (ossJson !== null) writeFileSync(path.join(dir, 'oss.json'), typeof ossJson === 'string' ? ossJson : JSON.stringify(ossJson));
  for (const [rel, content] of Object.entries(files)) {
    const p = path.join(dir, rel);
    mkdirSync(path.dirname(p), { recursive: true });
    writeFileSync(p, content);
  }
  return { root, dir };
}

export async function scan(files, opts = {}) {
  const { root, dir } = makeResource(files, opts);
  return runSafety({ cwd: root, config: { safety: opts.safety ?? {}, file: path.join(root, '.fivem-devkit.json') }, paths: [dir] });
}

export const of = (findings, id) => findings.filter((f) => f.check === `safety/${id}`);
export const ids = (findings) => [...new Set(findings.map((f) => f.check.replace('safety/', '')))].sort();

// one server-side Lua file
export const lua = (code, opts) => scan({ 'server/main.lua': code }, opts);
export const clientLua = (code, opts) => scan({ 'client/main.lua': code }, opts);
export const js = (code, opts) => scan({ 'server/main.js': code }, opts);
export const nui = (code, opts) => scan({ 'html/app.js': code }, opts);
