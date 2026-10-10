import path from 'node:path';
import { findResources } from './manifest.js';
import { readText, walk } from './fs.js';

// What every check receives. Checks must only read through this object so they stay testable
// against fixture trees (tests build a temp dir and point `cwd` at it).
export function createContext({ cwd, config }) {
  const ignore = config.ignorePaths ?? ['node_modules', '.git', 'dist'];
  let resources;
  return {
    cwd,
    config,
    rel: (p) => path.relative(cwd, p) || '.',
    readText,
    walk: (dir, exts) => walk(path.resolve(cwd, dir), { exts, ignore }),
    get resources() {
      resources ??= findResources(cwd, config.roots ?? ['resources'], ignore);
      return resources;
    },
    // all files of the given extensions inside every resource
    resourceFiles(exts) {
      return this.resources.flatMap((r) => walk(r.dir, { exts, ignore }));
    },
    specFiles() {
      return (config.specRoots ?? []).flatMap((d) => walk(path.resolve(cwd, d), { exts: ['.lua'], ignore }));
    },
  };
}
