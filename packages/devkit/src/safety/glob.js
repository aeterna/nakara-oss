// Tiny glob helpers (no dependency). Two flavours:
//   pathGlob — file paths: `**` crosses '/', `*` and `?` do not. A pattern with no glob characters
//              is a prefix ("resources/foo" matches "resources/foo/x.lua").
//   nameGlob — capability names (convars, events, commands): `*` matches anything.

const esc = (s) => s.replace(/[.+^${}()|[\]\\]/g, '\\$&');

export function hasGlob(p) {
  return /[*?]/.test(p);
}

export function pathGlobRegex(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      if (glob[i + 2] === '/') { re += '(?:.*/)?'; i += 2; } else { re += '.*'; i += 1; }
    } else if (c === '*') re += '[^/]*';
    else if (c === '?') re += '[^/]';
    else re += esc(c);
  }
  return new RegExp(`^${re}$`);
}

export function pathMatches(pattern, relPath) {
  const p = pattern.replace(/\\/g, '/').replace(/^\.\//, '');
  const r = relPath.replace(/\\/g, '/');
  if (hasGlob(p)) return pathGlobRegex(p).test(r);
  const base = p.replace(/\/+$/, '');
  return base !== '' && (r === base || r.startsWith(base + '/'));
}

export function nameMatches(pattern, name) {
  if (!hasGlob(pattern)) return pattern === name;
  let re = '';
  for (const c of pattern) re += c === '*' ? '.*' : c === '?' ? '.' : esc(c);
  return new RegExp(`^${re}$`).test(name);
}
