import path from 'node:path';

export const MAX_FONT_BYTES = 1024 * 1024; // 1 MB per resource
const DENIED_FONTS = new Set(['.ttf', '.otf', '.woff', '.eot']);

function isPackageResource(rctx) {
  const dir = rctx?.res?.dir;
  return typeof dir === 'string' && path.basename(path.dirname(dir)) === 'packages';
}

function isLauncherAsset(entry) {
  const norm = entry.file.split(path.sep).join('/');
  return entry.rel.startsWith('launcher/assets/') || norm.includes('/launcher/assets/');
}

export default {
  id: 'font-assets',
  severity: 'error',
  kind: 'hard-deny',
  description: 'fonts and .svg under packages/*: only .woff2 in html/fonts/ with OFL.txt (≤ 1 MB/package); no .ttf/.otf/.woff/.eot or .svg',
  docs: 'Under packages/*, fonts must be OFL-licensed .woff2 files inside html/fonts/ with OFL.txt beside them and at most 1 MB of fonts per package. Other font formats (.ttf, .otf, .woff, .eot) and standalone .svg files are refused (inline icons in JS and list the icon set in NOTICE). launcher/assets/** keeps its existing exception.',
  checkFile(e, rctx, emit) {
    if (!isPackageResource(rctx) || isLauncherAsset(e)) return;
    const state = (rctx.fontAssets ??= { files: new Set(), totalBytes: 0, firstFile: null, lastFile: null });
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

    if (path.posix.dirname(e.rel) !== 'html/fonts') {
      emit(null, `.woff2 font outside html/fonts/ (${e.rel}) — fonts are only allowed inside html/fonts/ with OFL.txt`);
      return;
    }

    state.firstFile ??= e.file;
    state.lastFile = e.file;
    state.totalBytes += e.size ?? Buffer.byteLength(e.text ?? '');
  },
  checkResource(rctx, emit) {
    const state = rctx.fontAssets;
    if (!state || !state.firstFile) return;
    if (!state.files.has('html/fonts/OFL.txt')) {
      emit(null, '.woff2 font in html/fonts/ without html/fonts/OFL.txt — include OFL.txt in the same folder', { file: state.firstFile });
    }
    if (state.totalBytes > MAX_FONT_BYTES) {
      emit(null, `${state.totalBytes} bytes of fonts in html/fonts/ exceeds the 1 MB (${MAX_FONT_BYTES} bytes) per-package limit`, { file: state.lastFile });
    }
  },
};
