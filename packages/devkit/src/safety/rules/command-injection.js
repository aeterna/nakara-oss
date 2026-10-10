import { commandWords, partsText } from './util.js';

export default {
  id: 'command-injection',
  severity: 'error',
  kind: 'hard-deny',
  description: 'server-side ExecuteCommand with arguments built at runtime',
  docs: 'The server console splits on `;`: ExecuteCommand(\'say \' .. msg) with msg = "hi; add_ace ..." runs a second command as the console. Validate the value against a strict pattern and allow the file with a reason, or avoid ExecuteCommand.',
  check(f, _r, emit) {
    if (!f.isServer) return;
    for (const ref of f.refs) {
      if (ref.path !== 'ExecuteCommand' || !ref.call || !ref.call.args[0]) continue;
      const words = commandWords(ref.call.args[0].parts);
      if (words.some((w) => w.word === null)) continue; // ace-command reports runtime command names
      if (words.some((w) => w.dynamicArgs)) {
        emit(ref.line, `ExecuteCommand('${partsText(ref.call.args[0].parts)}') — runtime value in a console command; a ';' in it runs another command`);
      }
    }
  },
};
