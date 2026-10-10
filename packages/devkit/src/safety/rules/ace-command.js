import { allWords, commandWords, partsText } from './util.js';

// Words that are never innocent anywhere in a console command string.
const ALWAYS = new Set(['add_ace', 'add_principal', 'remove_ace', 'remove_principal', 'rcon', 'rcon_password']);
// Console commands that change permissions, server config or which code runs. Matched at command
// position (first word of each `;`/newline-separated command) so `say we restart at 6` passes.
const AT_COMMAND = new Set([
  ...ALWAYS, 'exec', 'set', 'sets', 'setr', 'seta', 'quit', 'restart', 'stop', 'start', 'ensure', 'refresh',
  'sv_licensekey', 'endpoint_add_tcp', 'endpoint_add_udp', 'load_server_icon', 'con_addchannelfilter',
]);

export default {
  id: 'ace-command',
  severity: 'error',
  kind: 'hard-deny',
  suppressible: false,
  description: 'ExecuteCommand that grants permissions, changes server config, or starts/stops resources (add_ace, add_principal, exec, set*, ensure, stop, quit, ...)',
  docs: 'ExecuteCommand runs as the server console, which holds every permission. add_ace/add_principal make an attacker admin; set/exec rewrite config; start/stop/ensure swap the code that runs. On the server a command whose name is built at runtime is treated the same way: it is how the above gets hidden. Cannot be allowlisted.',
  check(f, _r, emit) {
    for (const ref of f.refs) {
      if (ref.path !== 'ExecuteCommand') continue;
      if (!ref.call) {
        if (!ref.aliasSource && !ref.typeofOperand && !ref.assigned) emit(ref.line, 'ExecuteCommand referenced as a value — the commands it runs cannot be checked');
        continue;
      }
      const arg = ref.call.args[0];
      if (!arg) continue;
      const words = commandWords(arg.parts);
      const hit = words.find((w) => w.word !== null && AT_COMMAND.has(w.word.toLowerCase())) ?? null;
      const always = allWords(arg.parts).find((w) => ALWAYS.has(w.toLowerCase()));
      if (hit || always) {
        emit(ref.line, `ExecuteCommand('${partsText(arg.parts)}') runs '${(hit?.word ?? always).toLowerCase()}' as the server console`);
        continue;
      }
      if (f.isServer && (words.length === 0 || words.some((w) => w.word === null))) {
        emit(ref.line, `ExecuteCommand('${partsText(arg.parts)}') — command name is built at runtime, so it could be add_ace or exec`);
      }
    }
  },
};
