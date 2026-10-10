export default {
  id: 'nui-html-injection',
  severity: 'error',
  kind: 'quality',
  description: 'innerHTML/outerHTML/insertAdjacentHTML/document.write (or jQuery .html) with a non-literal value',
  docs: 'NUI is Chromium with access to the resource\'s NUI callbacks. Player-controlled text (names, chat, item labels) rendered as HTML runs script in every viewer\'s game client and can call those callbacks as the victim. Use textContent, or build elements.',
  check(f, _r, emit) {
    for (const s of f.htmlSinks ?? []) emit(s.line, `${s.sink} with a non-literal value — XSS in NUI; use textContent or build elements`);
  },
};
