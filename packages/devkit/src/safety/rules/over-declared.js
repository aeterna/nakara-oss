export default {
  id: 'over-declared',
  severity: 'warn',
  kind: 'quality',
  needsManifest: true,
  description: 'capability declared in oss.json but not used by the code',
  docs: 'Unused capabilities make the manifest lie in the safe direction today and the unsafe direction tomorrow: a later change can start using them without the capability diff showing anything. Keep oss.json exact.',
  checkResource(rctx, emit) {
    const { oss, caps, used } = rctx;
    if (!oss.exists || !oss.data) return;
    const at = { file: oss.file };
    const unused = (list, set, label) => {
      for (const v of list) if (!set.has(v)) emit(null, `${label} '${v}' is declared but never used`, at);
    };
    unused(caps.http, used.http, 'http');
    unused(caps.commands, used.commands, 'commands');
    unused(caps.registeredCommands, used.registeredCommands, 'registeredCommands');
    unused(caps.convars.read, used.convarsRead, 'convars.read');
    unused(caps.convars.write, used.convarsWrite, 'convars.write');
    unused(caps.netEvents.server, used.netServer, 'netEvents.server');
    unused(caps.netEvents.client, used.netClient, 'netEvents.client');
    unused(caps.db.tables, used.tables, 'db.tables');
    unused(caps.files.write, used.filesWrite, 'files.write');
    if (caps.nui && !used.nui) emit(null, 'nui is true but no NUI use was found', at);
    if (caps.db.ddl && !used.ddl) emit(null, 'db.ddl is true but no DDL statement was found', at);
  },
};
