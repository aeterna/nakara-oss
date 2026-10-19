// Child process for the oss-undeclared golden check. check.sh starts this WITHOUT AETERNA_GOLDEN_NONCE.
// It imports fixture/undeclared.mjs and runs the expectations. Failures go to stderr. The success line goes to
// stdout only when every expectation held.
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const fixtureDir = process.argv[2];
if (!fixtureDir) {
    process.stderr.write('child: missing fixture directory argument\n');
    process.exit(1);
}

let mod;
try {
    mod = await import(pathToFileURL(resolve(fixtureDir, 'undeclared.mjs')).href);
} catch (err) {
    process.stderr.write(`FAIL: fixture/undeclared.mjs did not load: ${err}\n`);
    process.exit(1);
}
if (typeof mod.undeclaredNetEvents !== 'function') {
    process.stderr.write('FAIL: fixture/undeclared.mjs must export undeclaredNetEvents\n');
    process.exit(1);
}
const undeclaredNetEvents = mod.undeclaredNetEvents;

let passed = 0;
let failed = 0;

function expect(label, cond) {
    if (cond) {
        passed++;
    } else {
        failed++;
        process.stderr.write(`FAIL: ${label}\n`);
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

function expectList(label, got, want) {
    const same = Array.isArray(got) && JSON.stringify(got) === JSON.stringify(want);
    expect(`${label} (want ${JSON.stringify(want)}, got ${JSON.stringify(got)})`, same);
}

function expectTypeError(label, fn) {
    expect(`${label} (expected TypeError)`, run(fn) instanceof TypeError);
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

if (failed > 0) {
    process.stderr.write(`${failed} of ${passed + failed} expectations failed\n`);
    process.exitCode = 1;
} else {
    process.stdout.write(`GOLDEN_OK oss-undeclared expectations=${passed}\n`);
}
