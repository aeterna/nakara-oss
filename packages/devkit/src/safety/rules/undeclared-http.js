import { httpEntryMatches, urlIsDynamic } from '../capabilities.js';
import { RES_MARKER, partsText, valueRefs } from './util.js';

const LUA_CALLS = new Set(['PerformHttpRequest']);
const LUA_INTERNAL = new Set(['PerformHttpRequestInternal', 'PerformHttpRequestInternalEx']);
const JS_CALLS = new Set([
  'fetch', 'module:node-fetch', 'module:undici.fetch', 'module:undici.request',
  'module:http.request', 'module:http.get', 'module:https.request', 'module:https.get', 'module:http2.connect',
  'axios', 'axios.get', 'axios.post', 'axios.put', 'axios.patch', 'axios.delete', 'axios.head', 'axios.options', 'axios.request',
  'module:axios', 'module:axios.get', 'module:axios.post', 'module:axios.put', 'module:axios.patch', 'module:axios.delete', 'module:axios.head', 'module:axios.options', 'module:axios.request',
  'WebSocket', 'EventSource', 'navigator.sendBeacon', 'PerformHttpRequest',
]);
const JS_UNVERIFIABLE = new Set(['XMLHttpRequest', 'module:undici', 'module:http2']);

// NUI callbacks look like HTTP but stay inside the game: https://<resource>/cb or https://${GetParentResourceName()}/cb
function isNuiCallback(parts, names) {
  const s = parts.map((p) => (p === null ? '\u0001' : p)).join('');
  const m = /^(?:https?:)?\/\/([^/?#]*)/i.exec(s);
  if (!m) return false;
  const host = m[1];
  return host === RES_MARKER || names.has(host) || host.startsWith('cfx-nui-');
}

// relative URLs in NUI code are local files of the resource
function isLocal(parts) {
  const first = parts[0];
  if (typeof first !== 'string' || first === RES_MARKER) return false;
  if (/^(?:[a-z][a-z0-9+.-]*:)?\/\//i.test(first)) return /^nui:\/\//i.test(first);
  if (/^[a-z][a-z0-9+.-]*:/i.test(first)) return /^(?:nui|data|blob):/i.test(first);
  return true;
}

export function checkUrl(rctx, parts, line, emit, api) {
  const shown = partsText(parts);
  if (urlIsDynamic(parts)) {
    emit(line, `${api}(${shown}) — dynamic URL; declare the host in oss.json capabilities.http and build the URL from a constant`);
    return;
  }
  const hits = rctx.caps.http.filter((e) => httpEntryMatches(e, parts));
  for (const h of hits) rctx.used.http.add(h);
  if (!hits.length) emit(line, `${api} to '${shown}' — not declared in oss.json capabilities.http`);
}

export default {
  id: 'undeclared-http',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'outbound HTTP (PerformHttpRequest, fetch, http(s).request, axios, WebSocket) to a URL not in capabilities.http',
  docs: 'Outbound HTTP is how data leaves the server and how payloads come in. Every destination is declared as a URL prefix; ${convar} placeholders stand for values the server owner configures.',
  check(f, rctx, emit) {
    const names = rctx.names;
    for (const ref of f.refs) {
      if (!ref.call || ref.path === null) continue;
      if (f.lang === 'lua' && LUA_INTERNAL.has(ref.path)) { emit(ref.line, `${ref.path} — internal HTTP native; use PerformHttpRequest with a declared URL`); continue; }
      if (f.lang === 'js' && JS_UNVERIFIABLE.has(ref.path)) { emit(ref.line, `${ref.path} — cannot verify the destination; use fetch with a literal URL`); continue; }
      const set = f.lang === 'lua' ? LUA_CALLS : JS_CALLS;
      if (!set.has(ref.path)) continue;
      const arg = ref.call.args[0];
      if (!arg) continue;
      if (arg.kind === 'table') { emit(ref.line, `${ref.path}({...}) — request options object; pass a literal URL so the destination can be checked`); continue; }
      if (f.lang === 'js' && (isLocal(arg.parts) || isNuiCallback(arg.parts, names))) continue;
      checkUrl(rctx, arg.parts, ref.line, emit, ref.path);
    }
    const all = new Set([...(f.lang === 'lua' ? [...LUA_CALLS, ...LUA_INTERNAL] : [...JS_CALLS, ...JS_UNVERIFIABLE])]);
    for (const ref of valueRefs(f, all)) emit(ref.line, `${ref.path} referenced as a value — its destinations cannot be checked`);
  },
  checkResource(rctx, emit) {
    const m = rctx.res.manifest;
    for (const key of ['ui_page', 'loadscreen']) {
      const v = m[key];
      if (v && /^(?:https?:)?\/\//i.test(v)) checkUrl(rctx, [v], null, (line, msg) => emit(line, `fxmanifest ${key}: ${msg}`, { file: rctx.res.manifestPath }), key);
    }
  },
};
