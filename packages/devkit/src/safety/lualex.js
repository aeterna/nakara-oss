// CfxLua lexer. luaparse cannot read CfxLua (`<const>`, backtick hashes, `+=`, `?.`), and a scanner
// that fails to parse a file is a scanner an attacker can blind with one exotic token. So the safety
// rules work on a token stream instead of an AST: text inside comments and strings never looks like
// code, and code can never hide inside something the lexer mistook for a comment or string.
//
// Token = { type, value, line, start, end, ... }
//   type: 'name' | 'keyword' | 'string' | 'number' | 'hash' | 'op' | 'eof'
//   string tokens also carry: raw (source text incl. quotes), long (bool), escRun (longest run of
//   consecutive \xNN / \ddd / \u{...} escapes — an obfuscation signal)
//
// lex(src) never throws: problems (unterminated string, bad long bracket) land in `errors`, and the
// caller reports them — a file Lua itself would refuse to load is still worth a red mark.

export const KEYWORDS = new Set([
  'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in',
  'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while',
]);

// longest first; CfxLua adds compound assignment, `!=` and safe navigation on top of Lua 5.4
const OPS3 = new Set(['...', '..=', '<<=', '>>=', '//=']);
const OPS2 = new Set([
  '..', '==', '~=', '!=', '<=', '>=', '<<', '>>', '//', '::',
  '+=', '-=', '*=', '/=', '%=', '^=', '&=', '|=', '?.',
]);
const OPS1 = new Set('+-*/%^#&~|<>=(){}[];:,.?!'.split(''));

const isDigit = (c) => c >= 48 && c <= 57;
const isHex = (c) => isDigit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
const isNameStart = (c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95;
const isNameChar = (c) => isNameStart(c) || isDigit(c);

const SIMPLE_ESC = { a: '\x07', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t', v: '\v', '\\': '\\', '"': '"', "'": "'" };

export function lex(src) {
  const tokens = [];
  const errors = [];
  const n = src.length;
  let i = 0;
  let line = 1;

  // shebang
  if (src.startsWith('#!')) {
    while (i < n && src.charCodeAt(i) !== 10) i++;
  }

  // `[` `=`* `[` at position p → level (number of '='), or -1
  const longOpen = (p) => {
    if (src.charCodeAt(p) !== 91) return -1;
    let q = p + 1;
    while (src.charCodeAt(q) === 61) q++;
    return src.charCodeAt(q) === 91 ? q - p - 1 : -1;
  };

  // reads a long bracket body starting at p (pointing at the first '['); returns { value, end } or null
  const readLong = (p, level) => {
    let q = p + level + 2;
    // a newline right after the opening bracket is skipped
    if (src.charCodeAt(q) === 13) q += src.charCodeAt(q + 1) === 10 ? 2 : 1, line++;
    else if (src.charCodeAt(q) === 10) q += src.charCodeAt(q + 1) === 13 ? 2 : 1, line++;
    const close = ']' + '='.repeat(level) + ']';
    const idx = src.indexOf(close, q);
    if (idx < 0) return null;
    const value = src.slice(q, idx);
    for (let k = 0; k < value.length; k++) if (value.charCodeAt(k) === 10) line++;
    return { value, end: idx + close.length };
  };

  while (i < n) {
    const c = src.charCodeAt(i);

    // whitespace
    if (c === 10) { line++; i++; continue; }
    if (c === 32 || c === 9 || c === 13 || c === 11 || c === 12) { i++; continue; }

    // comments
    if (c === 45 && src.charCodeAt(i + 1) === 45) {
      const lvl = longOpen(i + 2);
      if (lvl >= 0) {
        const startLine = line;
        const body = readLong(i + 2, lvl);
        if (!body) {
          errors.push({ line: startLine, message: 'unterminated long comment' });
          i = n;
        } else i = body.end;
        continue;
      }
      while (i < n && src.charCodeAt(i) !== 10) i++;
      continue;
    }

    const start = i;
    const tokLine = line;

    // names / keywords
    if (isNameStart(c)) {
      while (i < n && isNameChar(src.charCodeAt(i))) i++;
      const value = src.slice(start, i);
      tokens.push({ type: KEYWORDS.has(value) ? 'keyword' : 'name', value, line: tokLine, start, end: i });
      continue;
    }

    // numbers
    if (isDigit(c) || (c === 46 && isDigit(src.charCodeAt(i + 1)))) {
      if (c === 48 && (src[i + 1] === 'x' || src[i + 1] === 'X')) {
        i += 2;
        while (i < n && (isHex(src.charCodeAt(i)) || src[i] === '.')) i++;
        if (src[i] === 'p' || src[i] === 'P') {
          i++;
          if (src[i] === '+' || src[i] === '-') i++;
          while (i < n && isDigit(src.charCodeAt(i))) i++;
        }
      } else {
        while (i < n && (isDigit(src.charCodeAt(i)) || src[i] === '.')) i++;
        if (src[i] === 'e' || src[i] === 'E') {
          i++;
          if (src[i] === '+' || src[i] === '-') i++;
          while (i < n && isDigit(src.charCodeAt(i))) i++;
        }
      }
      const raw = src.slice(start, i);
      tokens.push({ type: 'number', value: raw, num: Number(raw), line: tokLine, start, end: i });
      continue;
    }

    // short strings
    if (c === 34 || c === 39) {
      const q = c;
      i++;
      let out = '';
      let run = 0;
      let escRun = 0;
      let closed = false;
      while (i < n) {
        const d = src.charCodeAt(i);
        if (d === q) { closed = true; i++; break; }
        if (d === 10 || d === 13) break; // unescaped newline ends (and breaks) a short string
        if (d !== 92) { out += src[i]; i++; run = 0; continue; }
        // escape
        const e = src[i + 1];
        if (e === undefined) { i++; break; }
        if (SIMPLE_ESC[e] !== undefined) { out += SIMPLE_ESC[e]; i += 2; run = 0; continue; }
        if (e === '\n' || e === '\r') {
          out += '\n';
          line++;
          i += 2;
          if ((e === '\n' && src[i] === '\r') || (e === '\r' && src[i] === '\n')) i++;
          run = 0;
          continue;
        }
        if (e === 'z') {
          i += 2;
          while (i < n && /\s/.test(src[i])) { if (src[i] === '\n') line++; i++; }
          run = 0;
          continue;
        }
        if (e === 'x') {
          const h = src.slice(i + 2, i + 4);
          if (/^[0-9a-fA-F]{2}$/.test(h)) { out += String.fromCharCode(parseInt(h, 16)); i += 4; }
          else { errors.push({ line, message: 'invalid \\x escape' }); i += 2; }
          escRun = Math.max(escRun, ++run);
          continue;
        }
        if (e >= '0' && e <= '9') {
          let k = i + 1;
          let digits = '';
          while (digits.length < 3 && src[k] >= '0' && src[k] <= '9') digits += src[k++];
          out += String.fromCharCode(Number(digits) & 0xff);
          i = k;
          escRun = Math.max(escRun, ++run);
          continue;
        }
        if (e === 'u' && src[i + 2] === '{') {
          const close = src.indexOf('}', i + 3);
          const hex = close > 0 ? src.slice(i + 3, close) : '';
          if (/^[0-9a-fA-F]+$/.test(hex)) {
            const cp = parseInt(hex, 16);
            out += cp <= 0x10ffff ? String.fromCodePoint(cp) : '�';
            i = close + 1;
          } else { errors.push({ line, message: 'invalid \\u escape' }); i += 2; }
          escRun = Math.max(escRun, ++run);
          continue;
        }
        errors.push({ line, message: `invalid escape \\${e}` });
        out += e;
        i += 2;
        run = 0;
      }
      if (!closed) errors.push({ line: tokLine, message: 'unterminated string' });
      tokens.push({ type: 'string', value: out, raw: src.slice(start, i), long: false, escRun, line: tokLine, start, end: i });
      continue;
    }

    // long strings
    if (c === 91) {
      const lvl = longOpen(i);
      if (lvl >= 0) {
        const body = readLong(i, lvl);
        if (!body) {
          errors.push({ line: tokLine, message: 'unterminated long string' });
          tokens.push({ type: 'string', value: src.slice(i + lvl + 2), raw: src.slice(i), long: true, escRun: 0, line: tokLine, start, end: n });
          i = n;
        } else {
          tokens.push({ type: 'string', value: body.value, raw: src.slice(start, body.end), long: true, escRun: 0, line: tokLine, start, end: body.end });
          i = body.end;
        }
        continue;
      }
    }

    // backtick hash strings (CfxLua: compile-time joaat of the contents)
    if (c === 96) {
      const close = src.indexOf('`', i + 1);
      const nl = src.indexOf('\n', i + 1);
      if (close < 0 || (nl >= 0 && nl < close)) {
        errors.push({ line: tokLine, message: 'unterminated backtick string' });
        i = nl >= 0 ? nl : n;
        continue;
      }
      tokens.push({ type: 'hash', value: src.slice(i + 1, close), line: tokLine, start, end: close + 1 });
      i = close + 1;
      continue;
    }

    // operators
    const s3 = src.substr(i, 3);
    const s2 = src.substr(i, 2);
    if (OPS3.has(s3)) { tokens.push({ type: 'op', value: s3, line: tokLine, start, end: i + 3 }); i += 3; continue; }
    if (OPS2.has(s2)) { tokens.push({ type: 'op', value: s2, line: tokLine, start, end: i + 2 }); i += 2; continue; }
    if (OPS1.has(src[i])) { tokens.push({ type: 'op', value: src[i], line: tokLine, start, end: i + 1 }); i++; continue; }

    // anything else (stray byte, non-ASCII outside a string): keep going, but say so
    errors.push({ line: tokLine, message: `unexpected character ${JSON.stringify(src[i])}` });
    i++;
  }
  tokens.push({ type: 'eof', value: '', line, start: n, end: n });
  return { tokens, errors };
}
