export default {
  id: 'code-eval',
  severity: 'error',
  kind: 'hard-deny',
  description: 'JS string-to-code: eval, Function/new Function, .constructor(...), setTimeout/setInterval with a string',
  docs: 'The JS twin of Lua load(): whatever string reaches it runs with the resource\'s full power (server) or the player\'s NUI session (client).',
  check(f, _r, emit) {
    if (f.lang !== 'js') return;
    for (const ref of f.refs) {
      const p = ref.path;
      if (p === 'eval' || p === 'execScript') {
        if (!ref.typeofOperand) emit(ref.line, `${p} ${ref.call ? 'called' : 'referenced'}`);
      } else if (p === 'Function' || p === 'Function.prototype.constructor') {
        if (!ref.typeofOperand && !ref.instanceofRhs) emit(ref.line, `${ref.call?.isNew ? 'new ' : ''}Function ${ref.call ? 'called' : 'referenced'} — compiles a string into code`);
      } else if ((p === 'setTimeout' || p === 'setInterval' || p === 'setImmediate') && ref.call) {
        const a = ref.call.args[0];
        if (a && (a.kind === 'string' || a.kind === 'template' || (a.kind === 'other' && a.parts.some((x) => typeof x === 'string')))) {
          emit(ref.line, `${p} with a string argument evaluates it as code`);
        }
      }
    }
    for (const s of f.evalSinks ?? []) emit(s.line, `${s.what} — reaches Function without naming it`);
  },
};
