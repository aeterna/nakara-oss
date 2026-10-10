import { partsText } from './util.js';

export const CONVAR_GETTERS = new Set(['GetConvar', 'GetConvarInt', 'GetConvarBool', 'GetConvarFloat']);
const SECRET_NAMES = new Set(['rcon_password', 'sv_licensekey', 'steam_webapikey', 'mysql_connection_string']);
const SECRET_RE = /(token|secret|password|apikey|api_key|webhook)/i;

// literal text of a convar name (runtime parts as '*') → is it, or could it be, a secret?
export function isSecretConvar(parts) {
  const text = parts.map((p) => (typeof p === 'string' ? p : '*')).join('').replace(/[\u0002\u0003][^\u0002\u0003]*[\u0002\u0003]/g, '*').replaceAll('\u0004', '*');
  return SECRET_NAMES.has(text.toLowerCase()) || SECRET_RE.test(text);
}

export default {
  id: 'secret-convar',
  severity: 'error',
  kind: 'hard-deny',
  suppressible: false,
  description: 'reads a secret convar (rcon_password, sv_licenseKey, steam_webApiKey, mysql_connection_string, *token*/*secret*/*password*/*apikey*/*webhook*)',
  docs: 'A resource that can read these can hand the server to whoever receives them: the rcon password, the database, the license key. Cannot be allowlisted — a package that needs a credential takes it through its own non-secret-named convar set by the owner, so the owner decides what it gets.',
  check(f, _r, emit) {
    for (const ref of f.refs) {
      if (!ref.call || !CONVAR_GETTERS.has(ref.path)) continue;
      const name = ref.call.args[0];
      if (name && isSecretConvar(name.parts)) emit(ref.line, `${ref.path}('${partsText(name.parts)}') reads a secret convar`);
    }
  },
};
