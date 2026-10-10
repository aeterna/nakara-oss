export default {
  id: 'missing-manifest',
  severity: 'error',
  kind: 'must-declare',
  description: 'resource has no oss.json (or an invalid one)',
  docs: 'oss.json is the capability manifest: what the resource may do to the server running it. Without one the resource declares nothing, so every capability use is reported. Set safety.requireManifest: false to scan third-party resources for hard-deny rules only.',
  checkResource(rctx, emit) {
    const { oss, opts, res } = rctx;
    if (!oss.exists) {
      if (opts.requireManifest) emit(null, 'missing oss.json — the resource declares no capabilities, so every capability use is reported', { file: res.manifestPath });
      return;
    }
    if (oss.problems.length) emit(null, `invalid oss.json: ${oss.problems.join('; ')}`, { file: oss.file });
  },
};
