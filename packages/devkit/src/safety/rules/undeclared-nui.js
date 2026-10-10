const NUI = new Set([
  'SetNuiFocus', 'SetNuiFocusKeepInput', 'RegisterNUICallback', 'RegisterNuiCallback', 'RegisterNuiCallbackType',
  'SendNUIMessage', 'SendNuiMessage',
]);

export default {
  id: 'undeclared-nui',
  severity: 'error',
  kind: 'must-declare',
  needsManifest: true,
  description: 'NUI use (ui_page, SetNuiFocus, RegisterNUICallback, SendNUIMessage, __cfx_nui: handlers) without capabilities.nui: true',
  docs: 'NUI is a browser inside the game client: it can take keyboard/mouse focus from the player and its callbacks are a client entry point. Declared so the owner knows a package draws UI.',
  check(f, rctx, emit) {
    if (f.isNui) return;
    const uses = f.refs.filter((r) => r.call && (NUI.has(r.path) ||
      ((r.path === 'AddEventHandler' || r.path === 'on') && (r.call.args[0]?.parts?.[0] ?? '').toString().startsWith('__cfx_nui:'))));
    if (!uses.length) return;
    rctx.used.nui = true;
    if (!rctx.caps.nui) emit(uses[0].line, `NUI used (${uses[0].path}${uses.length > 1 ? ` and ${uses.length - 1} more` : ''}) — oss.json capabilities.nui is not true`);
  },
  checkResource(rctx, emit) {
    if (!rctx.res.manifest.ui_page) return;
    rctx.used.nui = true;
    if (!rctx.caps.nui) emit(null, `fxmanifest ui_page '${rctx.res.manifest.ui_page}' — oss.json capabilities.nui is not true`, { file: rctx.res.manifestPath });
  },
};
