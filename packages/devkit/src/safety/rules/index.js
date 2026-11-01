// Registry of safety rules. Each module default-exports:
//
//   {
//     id: 'dynamic-load',            // finding check = 'safety/<id>'; key in safety.allow
//     severity: 'error' | 'warn',
//     kind: 'hard-deny' | 'must-declare' | 'quality' | 'meta',
//     suppressible: false,           // optional; false = safety.allow cannot silence it
//     needsManifest: true,           // optional; skipped for resources without oss.json when
//                                    //   safety.requireManifest is false
//     description, docs,
//     check(file, rctx, emit)        // per parsed Lua/JS source (see util.js for the file model)
//     checkFile(entry, rctx, emit)   // per file of any type (entry: { file, text, binary, ... })
//     checkResource(rctx, emit)      // once per resource, after every file
//   }
//
// emit(line, message, { severity, file }?)
import aceCommand from './ace-command.js';
import codeEval from './code-eval.js';
import commandInjection from './command-injection.js';
import dynamicLoad from './dynamic-load.js';
import envTamper from './env-tamper.js';
import hostAccess from './host-access.js';
import hostExec from './host-exec.js';
import invokeNative from './invoke-native.js';
import { invalidAllow, noResources, parseError, unscanned } from './meta.js';
import missingManifest from './missing-manifest.js';
import netEventRateLimit from './net-event-rate-limit.js';
import nuiHtmlInjection from './nui-html-injection.js';
import obfuscation from './obfuscation.js';
import opaqueFile from './opaque-file.js';
import overDeclared from './over-declared.js';
import secretConvar from './secret-convar.js';
import undeclaredCommand from './undeclared-command.js';
import undeclaredConvar from './undeclared-convar.js';
import undeclaredDb from './undeclared-db.js';
import undeclaredFileWrite from './undeclared-file-write.js';
import undeclaredHttp from './undeclared-http.js';
import undeclaredHttpHandler from './undeclared-http-handler.js';
import undeclaredNetEvent from './undeclared-net-event.js';
import undeclaredNui from './undeclared-nui.js';
import undeclaredRegisteredCommand from './undeclared-registered-command.js';

// order matters only for over-declared, which reads what the others marked as used
export const safetyRules = [
  dynamicLoad, hostExec, hostAccess, codeEval, envTamper, invokeNative, secretConvar, aceCommand,
  commandInjection, obfuscation, opaqueFile,
  missingManifest, undeclaredHttp, undeclaredHttpHandler, undeclaredCommand, undeclaredRegisteredCommand,
  undeclaredConvar, undeclaredNetEvent, undeclaredNui, undeclaredFileWrite, undeclaredDb,
  netEventRateLimit, nuiHtmlInjection,
  overDeclared,
];

export const metaRules = [parseError, invalidAllow, noResources, unscanned];

export const allRules = [...safetyRules, ...metaRules];
export const ruleById = new Map(allRules.map((r) => [r.id, r]));
