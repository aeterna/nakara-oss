const PATHS = new Set(['Citizen.InvokeNative', 'Citizen.invokeNative', 'Citizen.InvokeNative2', '_in', 'Citizen.InvokeFunctionReference']);

export default {
  id: 'invoke-native',
  severity: 'error',
  kind: 'hard-deny',
  description: 'server-side native call by hash (Citizen.InvokeNative / _in)',
  docs: 'Every capability rule matches natives by name. Calling a native by its hash (ExecuteCommand, GetConvar, SaveResourceFile all have one) skips them all. Client files are exempt: client code legitimately reaches undocumented game natives this way, and client natives cannot touch the server.',
  check(f, _r, emit) {
    if (!f.isServer) return;
    for (const ref of f.refs) {
      if (ref.path && PATHS.has(ref.path)) emit(ref.line, `${ref.path} on the server — natives called by hash bypass every capability check`);
    }
  },
};
