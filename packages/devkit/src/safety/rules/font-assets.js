import path from 'node:path';

export const MAX_FONT_BYTES = 1024 * 1024; // 1 MB per package
const DENIED_FONTS = new Set(['.ttf', '.otf', '.woff', '.eot']);

function isLauncherAsset(entry) {
  const norm = entry.file.split(path.sep).join('/');
  return entry.rel.startsWith('launcher/assets/') || norm.includes('/launcher/assets/');
}

function packageRel(rel, resDir) {
  const m = /^packages\/([^/]+)\/(.+)$/.exec(rel);
  return {
    pkgKey: m ? m[1] : resDir,
    pkgRel: m ? m[2] : rel,
    fontsRelDir: m ? `packages/${m[1]}/html/fonts` : 'html/fonts',
  };
}

export default {
  id: 'font-assets',
  severity: 'error',
  kind: 'hard-deny',
  description: 'fonts and .svg under packages/*: only .woff2 in html/fonts/ with OFL.txt (≤ 1 MB/package); no .ttf/.otf/.woff/.eot or .svg',
  docs: 'Under packages/*, fonts must be OFL-licensed .woff2 files inside packages/<pkg>/html/fonts/ with OFL.txt beside them and at most 1 MB of fonts per package. Other font formats (.ttf, .otf, .woff, .eot) and standalone .svg files are refused (inline icons in JS and list the icon set in NOTICE). launcher/assets/** keeps its existing exception.',
  checkFile(e, rctx, emit) {
    if (isLauncherAsset(e)) return;
    const state = (rctx.fontAssets ??= { files: new Set(), pkgs: new Map() });
    state.files.add(e.rel);

    const ext = e.ext ?? path.extname(e.file).toLowerCase();
    if (ext === '.svg') {
      emit(null, '.svg file — standalone SVG files are not allowed under packages/*; inline icons in JS and list the set in NOTICE');
      return;
    }
    if (DENIED_FONTS.has(ext)) {
      emit(null, `${ext} font file — only .woff2 fonts inside html/fonts/ (with OFL.txt) are allowed`);
      return;
    }
    if (ext !== '.woff2') return;

    const { pkgKey, pkgRel, fontsRelDir } = packageRel(e.rel, rctx.res?.dir ?? '');
    if (path.posix.dirname(pkgRel) !== 'html/fonts') {
      emit(null, `.woff2 font outside html/fonts/ (${e.rel}) — fonts are only allowed inside html/fonts/ with OFL.txt`);
      return;
    }

    let pkg = state.pkgs.get(pkgKey);
    if (!pkg) {
      pkg = { fontsRelDir, totalBytes: 0, firstFile: e.file, lastFile: e.file };
      state.pkgs.set(pkgKey, pkg);
    }
    pkg.totalBytes += e.size ?? Buffer.byteLength(e.text ?? '');
    pkg.lastFile = e.file;
  },
  checkResource(rctx, emit) {
    const state = rctx.fontAssets;
    if (!state) return;
    for (const pkg of state.pkgs.values()) {
      if (!state.files.has(`${pkg.fontsRelDir}/OFL.txt`)) {
        emit(null, `.woff2 font in ${pkg.fontsRelDir}/ without ${pkg.fontsRelDir}/OFL.txt — include OFL.txt in the same folder`, { file: pkg.firstFile });
      }
      if (pkg.totalBytes > MAX_FONT_BYTES) {
        emit(null, `${pkg.totalBytes} bytes of fonts in ${pkg.fontsRelDir}/ exceeds the 1 MB (${MAX_FONT_BYTES} bytes) per-package limit`, { file: pkg.lastFile });
      }
    }
  },
};
