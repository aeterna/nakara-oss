import { capMatches } from '../capabilities.js';

const SQL_START = /^\s*\(?\s*(SELECT|INSERT|UPDATE|DELETE|REPLACE|CREATE|ALTER|DROP|TRUNCATE|RENAME|WITH)\b/i;
const DDL = /^\s*(CREATE|ALTER|DROP|TRUNCATE|RENAME)\b/i;
const TABLE_RE = /(?<!\b(?:KEY|FOR|ON)\s+)\b(FROM|INTO|UPDATE|JOIN|TABLE(?:\s+IF\s+(?:NOT\s+)?EXISTS)?)\s+(`?)([A-Za-z_][\w$]*)\2(?:\s*\.\s*(`?)([A-Za-z_][\w$]*)\4)?(?![\w$`])(\s*\()?/gi;
const DANGLING = /\b(?:FROM|INTO|UPDATE|JOIN|TABLE)\s*[`'"]?\s*$/i;
const NOT_TABLES = new Set(['select', 'set', 'values', 'value', 'where', 'dual', 'lateral', 'unnest', 'if', 'exists', 'not', 'current_timestamp', 'cascade', 'restrict']);

// tables named by one SQL statement; CTE names are not tables
export function sqlTables(sql) {
  const ctes = new Set();
  for (const m of sql.matchAll(/(?:\bWITH\s+(?:RECURSIVE\s+)?|,\s*)([A-Za-z_]\w*)\s+AS\s*\(/gi)) ctes.add(m[1].toLowerCase());
  const out = [];
  for (const m of sql.matchAll(TABLE_RE)) {
    // FROM JSON_TABLE(...) / FROM some_function(...) is not a table; CREATE TABLE t (...) is
    if (m[6] && !/^TABLE/i.test(m[1]) && !/^INTO/i.test(m[1])) continue;
    const name = m[5] ? `${m[3]}.${m[5]}` : m[3];
    if (NOT_TABLES.has(name.toLowerCase()) || ctes.has(name.toLowerCase())) continue;
    out.push(name);
  }
  return out;
}

export function isSql(s) {
  return SQL_START.test(s) && /\b(FROM|INTO|UPDATE|TABLE|JOIN|SET|INDEX|VIEW|PROCEDURE|TRIGGER|EVENT|DATABASE|SCHEMA)\b/i.test(s.replace(SQL_START, ''));
}

function checkSql(sql, line, rctx, emit) {
  if (DDL.test(sql)) {
    rctx.used.ddl = true;
    if (!rctx.caps.db.ddl) emit(line, `DDL statement (${DDL.exec(sql)[1].toUpperCase()}) — oss.json capabilities.db.ddl is not true`);
  }
  for (const t of new Set(sqlTables(sql))) {
    const hits = rctx.caps.db.tables.filter((p) => capMatches([p], t) || capMatches([p], t.split('.').pop()));
    hits.forEach((h) => rctx.used.tables.add(h));
    if (!hits.length) emit(line, `SQL touches table '${t}' — not declared in oss.json capabilities.db.tables`);
  }
  if (DANGLING.test(sql)) emit(line, 'SQL with a table name appended at runtime — cannot check which table', { severity: 'warn' });
}

export default {
  id: 'undeclared-db',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'SQL touching tables not in capabilities.db.tables, or DDL (CREATE/ALTER/DROP) without db.ddl: true',
  docs: 'Every resource shares one database. Declaring tables keeps a package from reading the players or accounts tables it has no business with; DDL is declared separately because it can destroy data. Best effort: table names are read from SQL string literals in server-side code and .sql files.',
  check(f, rctx, emit) {
    if (!f.isServer) return;
    for (const s of f.strings) if (isSql(s.value)) checkSql(s.value, s.line, rctx, emit);
  },
  checkFile(e, rctx, emit) {
    if (!e.file.toLowerCase().endsWith('.sql') || e.binary) return;
    const text = e.text.replace(/--[^\n]*|\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '));
    let offset = 0;
    for (const stmt of text.split(';')) {
      const line = text.slice(0, offset).split('\n').length + (stmt.match(/^\s*/)[0].split('\n').length - 1);
      offset += stmt.length + 1;
      if (isSql(stmt)) checkSql(stmt, line, rctx, emit);
    }
  },
};
