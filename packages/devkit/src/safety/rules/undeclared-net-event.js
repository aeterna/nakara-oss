import { capMatches } from '../capabilities.js';
import { literal, netRegistrations, partsText } from './util.js';

export default {
  id: 'undeclared-net-event',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'RegisterNetEvent/RegisterServerEvent/onNet/lib.callback.register not in capabilities.netEvents.server (server files) / .client (client files)',
  docs: 'A server-side net event is an entry point every connected client can call with any arguments — the main way cheaters reach server logic. Declared events show up in the package README so a server owner sees the surface before installing. Shared and unlisted files count as both sides.',
  check(f, rctx, emit) {
    for (const reg of netRegistrations(f)) {
      const name = literal(reg.name);
      if (name === null) { emit(reg.line, `${reg.api}('${partsText(reg.name)}') — event name built at runtime; use a literal`); continue; }
      const sides = [];
      if (f.isServer) sides.push('server');
      if (f.isClient) sides.push('client');
      for (const side of sides) {
        const hits = rctx.caps.netEvents[side].filter((p) => capMatches([p], name));
        hits.forEach((h) => rctx.used[side === 'server' ? 'netServer' : 'netClient'].add(h));
        if (!hits.length) emit(reg.line, `${reg.api}('${name}') in a ${f.side} file — not declared in oss.json capabilities.netEvents.${side}`);
      }
    }
  },
};
