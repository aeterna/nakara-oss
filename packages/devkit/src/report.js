// Finding = { check, file, line?, message, severity: 'error' | 'warn' }
export function format(findings, fmt, cwd) {
  const rel = (f) => (f ? f.replace(cwd + '/', '') : '');
  if (fmt === 'json') return JSON.stringify(findings.map((f) => ({ ...f, file: rel(f.file) })), null, 2);
  if (fmt === 'github') {
    return findings
      .map((f) => `::${f.severity === 'warn' ? 'warning' : 'error'} file=${rel(f.file)}${f.line ? `,line=${f.line}` : ''},title=${f.check}::${f.message.replace(/\n/g, '%0A')}`)
      .join('\n');
  }
  return findings
    .map((f) => `${f.severity === 'warn' ? '⚠' : '✗'} [${f.check}] ${rel(f.file)}${f.line ? `:${f.line}` : ''}\n    ${f.message}`)
    .join('\n');
}
