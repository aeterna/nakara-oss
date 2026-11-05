'use strict';

// Storage tests: one shared suite on both backends, then the file backend's slots, torn writes and crash order.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createFileBackend } = require('../server/js/filestore.js');
const { createKvpBackend, createStorage, detectEdition } = require('../server/js/storage.js');
const { TicketStore } = require('../server/js/tickets.js');

const SHA_A = 'a'.repeat(64);
const SHA_B = 'b'.repeat(64);
const TICKET_A = '1'.repeat(32);
const TICKET_B = '2'.repeat(32);
const FOLDER = 'cache/rongroi-reports';

function fakeFiles() {
    const files = new Map();
    let ops = 0;
    let saves = 0;
    let fail = null;
    globalThis.GetCurrentResourceName = () => 'nakara_rongroi';
    globalThis.LoadResourceFile = (resource, path) => {
        ops += 1;
        return files.has(path) ? files.get(path) : null;
    };
    globalThis.SaveResourceFile = (resource, path, text) => {
        ops += 1;
        saves += 1;
        if (fail && fail(path)) return false;
        files.set(path, text);
        return true;
    };
    return { files, ops: () => ops, saves: () => saves, fail: (fn) => { fail = fn; } };
}

function fileEnv() {
    const natives = fakeFiles();
    return { ...natives, backend: createFileBackend() };
}

function kvpEnv() {
    const store = new Map();
    let ops = 0;
    const backend = createKvpBackend({
        get: (key) => { ops += 1; return store.has(key) ? store.get(key) : null; },
        set: (key, value) => { ops += 1; store.set(key, value); },
        del: (key) => { ops += 1; store.delete(key); },
    });
    return { store, ops: () => ops, backend };
}

function open(storage, caseId, ticket = TICKET_A, openedAt = 100, facts = {}) {
    storage.openCase({ caseId, ticket, openedAt, ...facts });
}

for (const [label, make] of [['file', fileEnv], ['kvp', kvpEnv]]) {
    test(`${label}: open, get, list and a bad ticket`, () => {
        const env = make();
        const storage = createStorage(env.backend);
        open(storage, 'case-a', TICKET_A, 100, { openedBy: 'staff' });
        assert.deepEqual(storage.getCase('case-a'), { caseId: 'case-a', ticket: TICKET_A, openedAt: 100, openedBy: 'staff' });
        assert.deepEqual(storage.listCases({ page: 0 }), [{ caseId: 'case-a', ticket: TICKET_A, openedAt: 100, reportSha256: null, consumedAt: null }]);
        assert.deepEqual(storage.listCases({ page: 1 }), []);
        assert.equal(storage.getCase('missing'), null);
        assert.throws(() => storage.getReport('A'.repeat(32)), TypeError);
        assert.throws(() => storage.getReport('abc'), TypeError);
    });

    test(`${label}: report, declined, delete and invalid names`, () => {
        const env = make();
        const storage = createStorage(env.backend);
        open(storage, 'case-a', TICKET_A);
        storage.saveReport({ caseId: 'case-a', ticket: TICKET_A, reportSha256: SHA_A, receivedAt: 200, record: { value: 7 } });
        assert.deepEqual(storage.getReport(TICKET_A), { record: { value: 7 } });
        assert.deepEqual(storage.getCase('case-a'), { caseId: 'case-a', ticket: TICKET_A, openedAt: 100, state: 'received', receivedAt: 200 });
        assert.deepEqual(storage.entries(), [{ caseId: 'case-a', ticket: TICKET_A, openedAt: 100, reportSha256: SHA_A, consumedAt: 200 }]);
        assert.deepEqual(storage.consumedSnapshot(), [{ ticket: TICKET_A, caseId: 'case-a', reportSha256: SHA_A, consumedAt: 200 }]);

        open(storage, 'case-b', TICKET_B);
        storage.saveReport({ caseId: 'case-b', ticket: TICKET_B, reportSha256: SHA_B, receivedAt: 300, declined: true });
        assert.deepEqual(storage.getReport(TICKET_B), { declined: true });
        assert.equal(storage.getCase('case-b').state, 'declined');
        assert.throws(() => storage.saveReport({ caseId: 'missing', ticket: TICKET_A, reportSha256: SHA_A, receivedAt: 1 }));

        assert.equal(storage.deleteCase('case-a'), true);
        assert.equal(storage.getCase('case-a'), null);
        assert.equal(storage.getReport(TICKET_A), null);
        assert.equal(storage.deleteCase('case-a'), false);
        assert.deepEqual(storage.listCases({ page: 0 }).map((entry) => entry.caseId), ['case-b']);

        const before = env.ops();
        for (const bad of ['../x', 'case-XYZ', 'other-ab']) {
            assert.throws(() => env.backend.read(bad), TypeError);
            assert.throws(() => env.backend.write(bad, {}), TypeError);
            assert.throws(() => env.backend.writeOnce(bad, {}), TypeError);
            assert.throws(() => env.backend.remove(bad), TypeError);
        }
        assert.equal(env.ops(), before);
    });

    test(`${label}: restart keeps cases, index and consumed tickets`, () => {
        const env = make();
        const first = createStorage(env.backend);
        open(first, 'case-a', TICKET_A);
        first.saveReport({ caseId: 'case-a', ticket: TICKET_A, reportSha256: SHA_A, receivedAt: 200, record: { ok: true } });
        const second = createStorage(env.backend);
        second.load();
        assert.deepEqual(second.getCase('case-a'), { caseId: 'case-a', ticket: TICKET_A, openedAt: 100, state: 'received', receivedAt: 200 });
        assert.deepEqual(second.getReport(TICKET_A), { record: { ok: true } });
        assert.deepEqual(second.consumedSnapshot(),
            [{ ticket: TICKET_A, caseId: 'case-a', reportSha256: SHA_A, consumedAt: 200 }]);
    });

    test(`${label}: 101 cases roll over to a second page; duplicate caseId is refused`, () => {
        const env = make();
        const storage = createStorage(env.backend);
        for (let i = 0; i < 101; i += 1) open(storage, `case-${i}`, i.toString(16).padStart(32, '0'), i);
        assert.equal(storage.listCases({ page: 0 }).length, 100);
        assert.deepEqual(storage.listCases({ page: 1 }).map((entry) => entry.caseId), ['case-100']);
        assert.throws(() => open(storage, 'case-0'), TypeError);
        assert.equal(storage.entries().length, 101);
    });
}

test('hasCase follows the index', () => {
    const env = fileEnv();
    const storage = createStorage(env.backend);
    assert.equal(storage.hasCase('case-a'), false);
    open(storage, 'case-a', TICKET_A);
    assert.equal(storage.hasCase('case-a'), true);
    assert.equal(storage.hasCase('case-b'), false);
    assert.equal(storage.deleteCase('case-a'), true);
    assert.equal(storage.hasCase('case-a'), false);
});

test('detectEdition follows gamename and passes the default', () => {
    assert.equal(detectEdition(() => 'gta5enhanced'), 'enhanced');
    assert.equal(detectEdition(() => 'gta5'), 'legacy');
    const calls = [];
    detectEdition((name, fallback) => { calls.push([name, fallback]); return ''; });
    assert.deepEqual(calls, [['gamename', '']]);
});

test('file slots alternate; a torn newest slot reads older and is overwritten next', () => {
    const env = fileEnv();
    const backend = env.backend;
    for (const n of [1, 2, 3]) backend.write('case-a', { n });
    assert.equal(JSON.parse(env.files.get(`${FOLDER}/case-a.a.json`)).seq, 3);
    assert.equal(JSON.parse(env.files.get(`${FOLDER}/case-a.b.json`)).seq, 2);
    assert.deepEqual(backend.read('case-a'), { n: 3 });
    env.files.set(`${FOLDER}/case-a.a.json`, '{"seq":3,');
    assert.deepEqual(backend.read('case-a'), { n: 2 });
    backend.write('case-a', { n: 4 });
    assert.equal(JSON.parse(env.files.get(`${FOLDER}/case-a.a.json`)).seq, 3);
    assert.deepEqual(backend.read('case-a'), { n: 4 });
});

test('a torn report reads null and a false SaveResourceFile throws', () => {
    const env = fileEnv();
    const backend = env.backend;
    backend.writeOnce(`report-${TICKET_A}`, { record: { ok: true } });
    env.files.set(`${FOLDER}/report-${TICKET_A}.json`, '{"record":');
    assert.equal(backend.read(`report-${TICKET_A}`), null);
    env.fail((path) => path.includes('/case-a.'));
    assert.throws(() => backend.write('case-a', {}), /rongroi storage: write failed/);
});

test('deleting empties only the paths that exist', () => {
    const env = fileEnv();
    const backend = env.backend;
    for (const n of [1, 2]) backend.write('case-a', { n });
    backend.writeOnce('case-a', { n: 3 });
    backend.writeOnce(`report-${TICKET_A}`, { record: { ok: true } });
    backend.remove('case-a');
    assert.equal(env.files.get(`${FOLDER}/case-a.a.json`), '');
    assert.equal(env.files.get(`${FOLDER}/case-a.b.json`), '');
    assert.equal(env.files.get(`${FOLDER}/case-a.json`), '');
    backend.remove(`report-${TICKET_A}`);
    assert.equal(env.files.get(`${FOLDER}/report-${TICKET_A}.json`), '');
    const saves = env.saves();
    backend.remove('case-a');
    assert.equal(env.saves(), saves);
});

test('crash order: a failed case write leaves its index entry; a failed case delete keeps it', () => {
    const env = fileEnv();
    const storage = createStorage(env.backend);
    env.fail((path) => path.includes('/case-'));
    assert.throws(() => open(storage, 'case-a'), /rongroi storage: write failed/);
    assert.equal(storage.getCase('case-a'), null);
    assert.deepEqual(storage.entries().map((entry) => entry.caseId), ['case-a']);
    const second = fileEnv();
    const other = createStorage(second.backend);
    open(other, 'case-b');
    second.fail((path) => path.includes('/case-'));
    assert.throws(() => other.deleteCase('case-b'), /rongroi storage: write failed/);
    assert.deepEqual(other.entries().map((entry) => entry.caseId), ['case-b']);
    const restarted = createStorage(second.backend);
    restarted.load();
    assert.deepEqual(restarted.entries().map((entry) => entry.caseId), ['case-b']);
});

function reload(env) {
    const storage = createStorage(env.backend);
    const result = storage.load();
    return { storage, result };
}

test('openCase write failures leave disk consistent and a retry works', () => {
    const caseEnv = fileEnv();
    const cases = createStorage(caseEnv.backend);
    caseEnv.fail((path) => path.includes('/case-'));
    assert.throws(() => open(cases, 'case-a'), /write failed/);
    const afterCase = reload(caseEnv).storage;
    assert.deepEqual([afterCase.entries().map((e) => e.caseId), afterCase.getCase('case-a')], [['case-a'], null]);

    const indexEnv = fileEnv();
    const index = createStorage(indexEnv.backend);
    indexEnv.fail((path) => path.includes('/index-0.'));
    assert.throws(() => open(index, 'case-a'), /write failed/);
    assert.deepEqual([index.entries(), index.listCases({ page: 0 })], [[], []]);
    assert.deepEqual(reload(indexEnv).result, { damaged: 0 });
    indexEnv.fail(() => false);
    open(index, 'case-a');
    assert.deepEqual(index.entries().map((entry) => entry.caseId), ['case-a']);
    assert.deepEqual(reload(indexEnv).storage.entries().map((entry) => entry.caseId), ['case-a']);
});

test('saveReport failing at each write leaves the completed writes on disk', () => {
    const report = { caseId: 'case-a', ticket: TICKET_A, reportSha256: SHA_A, receivedAt: 200, record: { value: 7 } };
    for (const [name, path] of [['report', '/report-'], ['case', '/case-'], ['index', '/index-']]) {
        const env = fileEnv();
        const storage = createStorage(env.backend);
        open(storage, 'case-a', TICKET_A);
        env.fail((candidate) => candidate.includes(path));
        assert.throws(() => storage.saveReport(report), /write failed/, name);
        const restarted = reload(env).storage;
        assert.equal(restarted.getReport(TICKET_A) !== null, name !== 'report', name);
        assert.equal(restarted.getCase('case-a').state, name === 'index' ? 'received' : undefined, name);
        assert.equal(restarted.entries()[0].reportSha256, null, name);
        env.fail(() => false);
        restarted.saveReport(report);
        assert.equal(restarted.entries()[0].reportSha256, SHA_A, name);
    }
});

test('saveReport refuses a ticket that is not the index entry ticket before writing', () => {
    const env = fileEnv();
    const storage = createStorage(env.backend);
    open(storage, 'case-a', TICKET_A);
    const before = env.ops();
    const report = { caseId: 'case-a', ticket: TICKET_B, reportSha256: SHA_A, receivedAt: 200, record: {} };
    assert.throws(() => storage.saveReport(report), /ticket does not match the case/);
    assert.equal(env.ops(), before);
    assert.deepEqual(storage.entries()[0],
        { caseId: 'case-a', ticket: TICKET_A, openedAt: 100, reportSha256: null, consumedAt: null });
    const restarted = reload(env).storage;
    assert.equal(restarted.getReport(TICKET_B), null);
    assert.equal(restarted.getCase('case-a').state, undefined);
});

test('a missing middle page is damaged while later pages load and stay writable', () => {
    const env = fileEnv();
    const storage = createStorage(env.backend);
    const ticket = (i) => i.toString(16).padStart(32, '0');
    for (let i = 0; i < 201; i += 1) open(storage, `case-${i}`, ticket(i), i);
    env.backend.remove('index-0');
    const { storage: restarted, result } = reload(env);
    assert.deepEqual([result, restarted.listCases({ page: 0 }).length], [{ damaged: 1 }, 0]);
    assert.deepEqual([restarted.listCases({ page: 1 }).length, restarted.listCases({ page: 2 }).map((e) => e.caseId)],
        [100, ['case-200']]);
    open(restarted, 'case-201', ticket(201), 201);
    assert.deepEqual([restarted.listCases({ page: 0 }).length, restarted.listCases({ page: 2 }).map((e) => e.caseId)],
        [0, ['case-200', 'case-201']]);
    const { storage: saved, result: again } = reload(env);
    assert.deepEqual([again, saved.listCases({ page: 0 }).length, saved.listCases({ page: 1 }).length,
        saved.listCases({ page: 2 }).map((e) => e.caseId)], [{ damaged: 1 }, 0, 100, ['case-200', 'case-201']]);
    assert.equal(env.backend.read('index-0'), null);
});

test('a non-array page stays damaged in memory and is never written', () => {
    const env = fileEnv();
    env.backend.write('index-0', { not: 'an array' });
    const storage = createStorage(env.backend);
    assert.deepEqual([storage.load(), storage.listCases({ page: 0 })], [{ damaged: 1 }, []]);
    open(storage, 'case-a', TICKET_A);
    assert.deepEqual([env.backend.read('index-0'), storage.listCases({ page: 1 }).map((e) => e.caseId)],
        [{ not: 'an array' }, ['case-a']]);
    const { storage: restarted, result } = reload(env);
    assert.deepEqual(result, { damaged: 1 });
    assert.deepEqual([restarted.listCases({ page: 0 }), restarted.listCases({ page: 1 }).map((e) => e.caseId)], [[], ['case-a']]);
});

test('consumedSnapshot omits entries restoreConsumed would reject', () => {
    const env = fileEnv();
    const storage = createStorage(env.backend);
    open(storage, 'case-a', TICKET_A);
    storage.saveReport({ caseId: 'case-a', ticket: TICKET_A, reportSha256: SHA_A, receivedAt: 200, record: { value: 7 } });
    const page = env.backend.read('index-0').slice();
    page.push(
        { caseId: 'bad-ticket', ticket: 'A'.repeat(32), reportSha256: SHA_A, consumedAt: 1 },
        { caseId: 'bad-sha', ticket: TICKET_B, reportSha256: 'Z'.repeat(64), consumedAt: 1 },
        { caseId: 'bad-time', ticket: '3'.repeat(32), reportSha256: SHA_A, consumedAt: 'later' });
    env.backend.write('index-0', page);
    const snapshot = reload(env).storage.consumedSnapshot();
    assert.deepEqual(snapshot, [{ ticket: TICKET_A, caseId: 'case-a', reportSha256: SHA_A, consumedAt: 200 }]);
    const tickets = new TicketStore({ now: () => 1000, randomBytes: (n) => Buffer.alloc(n, 7) });
    tickets.restoreConsumed(snapshot);
    assert.equal(tickets.stateOf(TICKET_A), 'consumed');
});

test('consumedSnapshot omits an entry whose caseId is not a non-empty string', () => {
    const env = fileEnv();
    const storage = createStorage(env.backend);
    open(storage, 'case-a', TICKET_A);
    storage.saveReport({ caseId: 'case-a', ticket: TICKET_A, reportSha256: SHA_A, receivedAt: 200, record: { value: 7 } });
    const page = env.backend.read('index-0').slice();
    page.push(
        { caseId: '', ticket: TICKET_B, reportSha256: SHA_B, consumedAt: 1 },
        { caseId: 7, ticket: '3'.repeat(32), reportSha256: SHA_A, consumedAt: 1 });
    env.backend.write('index-0', page);
    const snapshot = reload(env).storage.consumedSnapshot();
    assert.deepEqual(snapshot, [{ ticket: TICKET_A, caseId: 'case-a', reportSha256: SHA_A, consumedAt: 200 }]);
    const tickets = new TicketStore({ now: () => 1000, randomBytes: (n) => Buffer.alloc(n, 7) });
    tickets.restoreConsumed(snapshot);
    assert.equal(tickets.stateOf(TICKET_A), 'consumed');
});
