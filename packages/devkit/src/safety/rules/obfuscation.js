// Signals that code is hiding from its reviewer. None of them is proof; all of them are cheap to
// avoid in honest code, so they are errors.
const BASE64 = /^[A-Za-z0-9+/_-]{200,}={0,2}$/;
const CHAR_FNS = new Set(['string.char', 'utf8.char', 'String.fromCharCode', 'String.fromCodePoint']);
const UNPACK = new Set(['unpack', 'table.unpack']);

export const MAX_LINE = 1000;

export default {
  id: 'obfuscation',
  severity: 'error',
  kind: 'hard-deny',
  description: 'obfuscated code: long \\x/\\ddd escape runs, base64 blobs, string.char/fromCharCode byte lists, char tables, lines over 1000 chars',
  docs: 'Obfuscation exists to get code past a reviewer. Escape runs and byte lists spell out strings like "load" or a URL without the text appearing in the file; base64 blobs carry payloads; very long lines hide code off-screen.',
  check(f, _r, emit) {
    for (const s of f.strings) {
      if (s.escRun >= 8) emit(s.line, `string with ${s.escRun} consecutive byte escapes (\\xNN / \\ddd) — spell the text out`);
      const v = s.value.trim();
      if (BASE64.test(v)) emit(s.line, `${v.length}-char base64-looking literal — ship data as a reviewed file, not an inline blob`);
    }
    let charCalls = 0;
    for (const ref of f.refs) {
      if (!ref.call || !ref.path || !CHAR_FNS.has(ref.path.replace(/\.apply$/, ''))) continue;
      charCalls++;
      const args = ref.call.args;
      const numeric = args.filter((a) => a.kind === 'number').length;
      if (ref.path.endsWith('.apply')) emit(ref.line, `${ref.path} — builds a string from a byte array`);
      else if (numeric >= 8) emit(ref.line, `${ref.path} with ${numeric} numeric arguments — builds a hidden string`);
      else if (args.some((a) => a.kind === 'spread')) emit(ref.line, `${ref.path}(...array) — builds a string from a byte array`);
      else if (f.lang === 'lua' && f.refs.some((r) => UNPACK.has(r.path) && r.idx > args[0]?.range?.[0] - 1 && r.idx < (args[args.length - 1]?.range?.[1] ?? 0))) {
        emit(ref.line, `${ref.path}(unpack(...)) — builds a string from a byte table`);
      }
    }
    if (charCalls) {
      for (const t of f.numericTables ?? []) if (t.count >= 32) emit(t.line, `table of ${t.count} numbers in a file that calls string.char/utf8.char — encoded string?`);
    }
    if (f.longLines?.length) {
      emit(f.longLines[0], `${f.longLines.length} line(s) longer than ${MAX_LINE} characters (first here) — code hidden off-screen or minified`);
    }
  },
};
