import path from 'node:path';

const BINARY = new Set(['.dll', '.exe', '.so', '.dylib', '.zip', '.rar', '.7z', '.jar', '.luac', '.bin', '.node', '.wasm', '.gz', '.tar', '.tgz']);
const ASSETS = new Set(['.ycd', '.ytd', '.yft', '.ydr', '.ydd', '.ybn', '.ymap', '.ytyp', '.rpf']);

export default {
  id: 'opaque-file',
  severity: 'error',
  kind: 'hard-deny',
  description: 'files nobody can review: binaries/archives, Lua bytecode, minified JS, streamed GTA assets (unless safety.allowAssets)',
  docs: 'A reviewer can only approve what they can read. Binaries and archives can carry anything; minified bundles must be built in CI from reviewed source; streamed assets from outside contributors are opt-in per project.',
  checkFile(e, rctx, emit) {
    const ext = path.extname(e.file).toLowerCase();
    if (BINARY.has(ext)) return emit(null, `${ext} file — binary/archive content cannot be reviewed`);
    if (ASSETS.has(ext)) {
      if (!rctx.opts.allowAssets) emit(null, `${ext} streamed asset — not allowed unless safety.allowAssets is true`);
      return;
    }
    if (e.bytecode) return emit(null, 'precompiled Lua bytecode — ship source');
    if (e.binary) return emit(null, 'binary content in a source file — cannot be reviewed');
    if (e.minified) return emit(null, `${e.minified} — build it in CI from reviewed source instead of committing it (the file was not scanned further)`);
  },
};
