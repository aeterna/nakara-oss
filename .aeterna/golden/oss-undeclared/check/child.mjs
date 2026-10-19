// Child process for the oss-undeclared golden check. check.sh starts this WITHOUT AETERNA_GOLDEN_NONCE.
// Parent/child design: check.sh holds the nonce and never imports fixture/. This child imports
// fixture/undeclared.mjs via a file URL and runs the expectations. The success line goes to stdout only when every
// expectation held and the count is exactly EXPECTED; every other outcome exits 1. The fixture runs in this process
// without the nonce in its environment, so it never sees the nonce.
// Builtins are captured BEFORE the fixture is imported, so a fixture that replaces globals or prototypes
// (JSON.stringify, Array.isArray, TypeError[Symbol.hasInstance], process.exit, ...) cannot change how this child
// compares values, detects TypeErrors or reports failures.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { deepStrictEqual } from 'node:assert';

const deepEqual = deepStrictEqual;
const stringify = JSON.stringify;
const structuredCopy = structuredClone;
const getProto = Object.getPrototypeOf;
const TYPE_ERROR_PROTO = TypeError.prototype;
const resolvePath = resolve;
const toFileUrl = pathToFileURL;
const writeOut = process.stdout.write.bind(process.stdout);
const writeErr = process.stderr.write.bind(process.stderr);
const exitProcess = process.exit.bind(process);
const EXPECTED = 17;

const fixtureDir = process.argv[2];
if (!fixtureDir) {
    writeErr('child: missing fixture directory argument\n');
    exitProcess(1);
}

let mod;
try {
    mod = await import(toFileUrl(resolvePath(fixtureDir, 'undeclared.mjs')).href);
} catch (err) {
    writeErr(`FAIL: fixture/undeclared.mjs did not load: ${err}\n`);
    exitProcess(1);
}
if (typeof mod.undeclaredNetEvents !== 'function') {
    writeErr('FAIL: fixture/undeclared.mjs must export undeclaredNetEvents\n');
    exitProcess(1);
}
const undeclaredNetEvents = mod.undeclaredNetEvents;

let passed = 0;
let failed = 0;

function expect(label, cond) {
    if (cond) {
        passed++;
    } else {
        failed++;
        writeErr(`FAIL: ${label}\n`);
    }
}

// Runs fn and returns its result, or the thrown value.
function run(fn) {
    try {
        return fn();
    } catch (err) {
        return err;
    }
}

// Structural equality through the captured deepStrictEqual; returns false instead of throwing.
function same(a, b) {
    try {
        deepEqual(a, b);
        return true;
    } catch {
        return false;
    }
}

// Printable form for failure messages only.
function show(v) {
    try {
        return String(stringify(v));
    } catch {
        return '<unprintable>';
    }
}

function expectList(label, got, want) {
    expect(`${label} (want ${show(want)}, got ${show(got)})`, same(got, want));
}

// True only for a value whose prototype is the intrinsic %TypeError.prototype% captured at startup.
function isTypeError(v) {
    return typeof v === 'object' && v !== null && getProto(v) === TYPE_ERROR_PROTO;
}

function expectTypeError(label, fn) {
    expect(`${label} (expected TypeError)`, isTypeError(run(fn)));
}

const manifest = (server, client) => ({ capabilities: { netEvents: { server, client } } });

// A: the example from task.md.
const example = manifest(['nakara:ping'], ['nakara:sync']);
expectList(
    'A1 example from task.md',
    run(() => undeclaredNetEvents([
        { name: 'nakara:ping', side: 'server' },
        { name: 'nakara:sync', side: 'server' },
        { name: 'nakara:sync', side: 'client' },
        { name: 'nakara:ping', side: 'server' },
    ], example)),
    ['nakara:sync'],
);

// B: everything declared on its own side gives an empty result.
expectList(
    'B1 all used names declared on their side',
    run(() => undeclaredNetEvents([
        { name: 'p', side: 'server' },
        { name: 'q', side: 'client' },
    ], manifest(['p'], ['q']))),
    [],
);

// C: empty input.
expectList('C1 empty used array', run(() => undeclaredNetEvents([], manifest(['a'], ['b']))), []);

// D: duplicates are removed and the result is sorted.
expectList(
    'D1 duplicates removed and sorted',
    run(() => undeclaredNetEvents([
        { name: 'evt:b', side: 'server' },
        { name: 'evt:a', side: 'server' },
        { name: 'evt:b', side: 'server' },
    ], manifest([], []))),
    ['evt:a', 'evt:b'],
);
expectList(
    'D2 sorted across three names given out of order',
    run(() => undeclaredNetEvents([
        { name: 'zeta', side: 'client' },
        { name: 'alpha', side: 'server' },
        { name: 'mid', side: 'client' },
    ], manifest([], []))),
    ['alpha', 'mid', 'zeta'],
);

// E: side matters. A name declared on the other side is still undeclared.
expectList(
    'E1 client-only declaration does not cover a server use',
    run(() => undeclaredNetEvents([{ name: 'shared', side: 'server' }], manifest([], ['shared']))),
    ['shared'],
);
expectList(
    'E2 server-only declaration does not cover a client use',
    run(() => undeclaredNetEvents([{ name: 'x', side: 'client' }], manifest(['x'], []))),
    ['x'],
);

// F: a name undeclared on both sides appears once.
expectList(
    'F1 same name undeclared on both sides appears once',
    run(() => undeclaredNetEvents([
        { name: 'd', side: 'server' },
        { name: 'd', side: 'client' },
    ], manifest([], []))),
    ['d'],
);

// G: invalid manifests throw a TypeError.
expectTypeError(
    'G1 server array missing',
    () => undeclaredNetEvents([], { capabilities: { netEvents: { client: [] } } }),
);
expectTypeError('G2 client is a string, not an array', () => undeclaredNetEvents([], manifest(['a'], 'c')));
expectTypeError('G3 server array holds a non-string', () => undeclaredNetEvents([], manifest([1], [])));
expectTypeError('G4 capabilities missing', () => undeclaredNetEvents([], {}));
expectTypeError('G5 client array holds a non-string', () => undeclaredNetEvents([], manifest([], ['ok', 2])));

// H: larger mixed-side input with several declared and undeclared names on both sides.
const bigManifest = manifest(
    ['srv:login', 'srv:logout', 'srv:shared'],
    ['cli:hud', 'cli:shared', 'cli:menu'],
);
const bigUsed = [
    { name: 'srv:login', side: 'server' },
    { name: 'srv:logout', side: 'client' },
    { name: 'cli:hud', side: 'client' },
    { name: 'cli:hud', side: 'server' },
    { name: 'srv:bank', side: 'server' },
    { name: 'cli:menu', side: 'client' },
    { name: 'srv:shared', side: 'server' },
    { name: 'cli:shared', side: 'server' },
    { name: 'cli:shared', side: 'client' },
    { name: 'srv:bank', side: 'client' },
    { name: 'cli:zz', side: 'client' },
    { name: 'srv:login', side: 'client' },
];
expectList(
    'H1 larger mixed-side input',
    run(() => undeclaredNetEvents(bigUsed, bigManifest)),
    ['cli:hud', 'cli:shared', 'cli:zz', 'srv:bank', 'srv:login', 'srv:logout'],
);

// H2: default sort order (UTF-16 code units), not localeCompare: '10' < '9' < 'B' < 'a'.
expectList(
    'H2 default sort order',
    run(() => undeclaredNetEvents([
        { name: 'B', side: 'server' },
        { name: 'a', side: 'server' },
        { name: '10', side: 'server' },
        { name: '9', side: 'server' },
    ], manifest([], []))),
    ['10', '9', 'B', 'a'],
);

// H3: the inputs are not mutated.
const usedIn = [{ name: 'k', side: 'client' }, { name: 'a', side: 'server' }];
const manifestIn = manifest(['a'], []);
const usedBefore = structuredCopy(usedIn);
const manifestBefore = structuredCopy(manifestIn);
expectList('H3 result for a small input', run(() => undeclaredNetEvents(usedIn, manifestIn)), ['k']);
expect('H3 used and manifest are not mutated', same(usedIn, usedBefore) && same(manifestIn, manifestBefore));

// Success line only when every expectation held and the count is the one this child defines.
if (failed === 0 && passed === EXPECTED) {
    writeOut(`GOLDEN_OK oss-undeclared expectations=${passed}\n`);
} else {
    writeErr(`oss-undeclared: ${failed} failed, ran ${passed + failed} expectations, want ${EXPECTED}\n`);
    exitProcess(1);
}
