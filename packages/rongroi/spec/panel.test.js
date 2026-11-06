'use strict';

// Staff panel controller: caller checks, per-source limits, case ids and only-safe payloads.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createPanel, pruneRateWindows } = require('../server/js/panel.js');
const { createSettings } = require('../server/js/settings.js');
const { createStorage } = require('../server/js/storage.js');
const { TicketStore } = require('../server/js/tickets.js');
const { policyHash } = require('../server/js/pairing.js');
const envelope = require('../server/js/envelope.js');
const kit = require('../test-vectors/envelope-v1.json').kit;

const STAFF = 1;
const PLAYER = 42;
const ALT_PLAYER = 43;
const ORIGIN = 'http://192.0.2.10:30120';

function memoryBackend() {
    const store = new Map();
    const copy = (value) => JSON.parse(JSON.stringify(value));
    return {
        read: (name) => (store.has(name) ? copy(store.get(name)) : null),
        write: (name, value) => store.set(name, copy(value)),
        writeOnce: (name, value) => { if (!store.has(name)) store.set(name, copy(value)); },
        remove: (name) => store.delete(name),
    };
}

function counted(seed) {
    return (n) => Buffer.from(Array.from({ length: n }, () => (seed.value = (seed.value + 1) & 0xff)));
}

function makeHarness({ publicOrigin = ORIGIN, serverName = 'Example City' } = {}) {
    let ms = 1000000;
    const store = new TicketStore({ now: () => ms, randomBytes: counted({ value: 0 }) });
    const kvp = new Map();
    const settings = createSettings({ get: (key) => kvp.get(key), set: (key, value) => kvp.set(key, value) });
    if (publicOrigin !== null) settings.set('publicOrigin', publicOrigin);
    if (serverName !== null) settings.set('serverName', serverName);
    const storage = createStorage(memoryBackend());
    storage.load();
    const players = new Map([[PLAYER, {
        name: 'Player One', identifier: 'license:player', endpoint: '203.0.113.55',
    }], [ALT_PLAYER, {
        name: 'Player One Alt', identifier: 'license:player', endpoint: '203.0.113.56',
    }]]);
    const staff = new Set([STAFF]);
    const sent = [];
    const caseCalls = [];
    const caseSeed = { value: 100 };
    const panelKit = { ...kit };
    let rotateCalls = 0;
    const panel = createPanel({
        settings, storage, store, kit: panelKit, now: () => ms,
        isStaff: (src) => staff.has(src),
        getPlayer: (src) => players.get(src) || players.get(Number(src)) || null,
        send: (src, event, payload) => sent.push({ src, event, payload }),
        randomBytes: (n) => { caseCalls.push(n); return counted(caseSeed)(n); },
        rotateKitKey: () => {
            rotateCalls += 1;
            const pair = envelope.generateKeyPair();
            panelKit.publicKey = pair.publicKey;
            panelKit.privateKey = pair.privateKey;
            return pair;
        },
    });
    return {
        panel, storage, store, settings, kit: panelKit, staff, sent, caseCalls,
        rotateCalls: () => rotateCalls,
        advance: (delta) => { ms += delta; },
    };
}

test('createPanel requires a rotateKitKey dependency', () => {
    assert.throws(() => createPanel({
        settings: { get: () => ({}) },
        storage: { getCase: () => null, openCase: () => {} },
        store: { issue: () => ({}) },
        kit: {},
        now: () => 0,
        isStaff: () => false,
        getPlayer: () => null,
        send: () => {},
        randomBytes: () => Buffer.alloc(16),
    }), { name: 'TypeError', message: /rotateKitKey/ });
});

test('a non-staff source gets nothing from any entry point', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpen(2), false);
    assert.equal(h.panel.panelCase(2, 'case-a'), false);
    assert.equal(h.panel.panelOpenCase(2, PLAYER), false);
    assert.equal(h.panel.requestCode(2), false);
    assert.equal(h.panel.saveSettings(2, { serverName: 'Other City' }), false);
    assert.equal(h.panel.settingsOpen(2, 'settings'), false);
    assert.equal(h.panel.deleteCase(2, 'case-a'), false);
    assert.equal(h.panel.deletePlayer(2, 'license:player'), false);
    assert.equal(h.panel.rotateKey(2), false);
    assert.deepEqual(h.sent, []);
    assert.equal(h.storage.entries().length, 0);
    assert.equal(h.settings.get().serverName, 'Example City');
});

test('requestCode stays silent without an open case and drops it at ticket expiry', () => {
    const h = makeHarness();
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.deepEqual(h.sent, []);
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), true);
    assert.equal(h.sent.length, 1);
    assert.equal(h.sent[0].src, PLAYER);
    assert.equal(h.sent[0].event, 'nakara_rongroi:showCode');
    assert.match(h.sent[0].payload.code, /^rr1\./);
    assert.equal(typeof h.sent[0].payload.expiresAt, 'number');
    h.advance(300001);
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.deepEqual(h.sent, []);
});

test('opening a case without a public origin refuses with the reason', () => {
    const missingOrigin = makeHarness({ publicOrigin: null });
    assert.equal(missingOrigin.panel.panelOpenCase(STAFF, PLAYER), false);
    assert.deepEqual(missingOrigin.sent, [{
        src: STAFF,
        event: 'nakara_rongroi:panel:data',
        payload: { screen: 'error', reason: 'public_origin_missing' },
    }]);
    assert.equal(missingOrigin.storage.entries().length, 0);
});

test('panelOpenCase makes a 16-byte hex case, stores target facts and replies only to staff', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    assert.deepEqual(h.caseCalls, [16]);
    assert.equal(h.sent.length, 1);
    assert.equal(h.sent[0].src, STAFF);
    assert.equal(h.sent[0].payload.screen, 'case');
    assert.equal(h.sent[0].payload.case.state, 'opened');
    const row = h.storage.entries()[0];
    assert.match(row.caseId, /^[0-9a-f]{32}$/);
    const data = h.storage.getCase(row.caseId);
    assert.equal(data.identifier, 'license:player');
    assert.equal(Object.prototype.hasOwnProperty.call(data, 'address'), false);
    assert.equal(data.connectAddress, '203.0.113.55');
    assert.equal(data.openedBy, `staff:${STAFF}`);
    assert.equal(data.policy.profile, 'posture');
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), true);
    assert.equal(h.sent[0].src, PLAYER);
    assert.equal(h.panel.requestCode(STAFF), false);
});

test('panelOpenCase forgets a live earlier ticket for the same target', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    const first = h.storage.entries()[0];
    assert.equal(h.store.stateOf(first.ticket), 'issued');
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    const second = h.storage.entries()[1];
    assert.notEqual(second.ticket, first.ticket);
    assert.equal(h.store.stateOf(first.ticket), 'unknown');
    assert.equal(h.store.stateOf(second.ticket), 'issued');
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), true);
    assert.match(h.sent[0].payload.code, /^rr1\./);
});

test('panel payloads never carry the private key, the envelope or a stored record body', () => {
    const h = makeHarness();
    h.panel.panelOpenCase(STAFF, PLAYER);
    const entry = h.storage.entries()[0];
    const secret = 'stored-record-body-must-not-leak';
    h.storage.saveReport({
        caseId: entry.caseId, ticket: entry.ticket, reportSha256: 'a'.repeat(64), receivedAt: 1,
        record: { schema: 2, note: secret, envelope: { v: 1, epk: 'x', iv: 'y', ct: 'z' } },
    });
    h.sent.length = 0;
    assert.equal(h.panel.panelOpen(STAFF), true);
    assert.equal(h.sent[0].payload.screen, 'cases');
    assert.equal(h.panel.panelCase(STAFF, entry.caseId), true);
    assert.deepEqual(Object.keys(h.sent[0].payload.cases[0]).sort(),
        ['caseId', 'openedAt', 'openedBy', 'origin', 'receivedAt', 'state']);
    for (const message of h.sent) {
        const text = JSON.stringify(message.payload);
        assert.equal(text.includes(secret), false);
        assert.equal(text.includes(kit.privateKey), false);
        assert.equal(text.includes('"epk"'), false);
    }
});

test('staff allow 20 calls per 10 s and requestCode allows 3', () => {
    const h = makeHarness();
    for (let i = 0; i < 20; i += 1) assert.equal(h.panel.panelOpen(STAFF), true);
    assert.equal(h.sent.length, 20);
    assert.equal(h.panel.panelOpen(STAFF), false);
    assert.equal(h.panel.saveSettings(STAFF, {}), false);
    assert.equal(h.panel.deleteCase(STAFF, 'missing'), false);
    assert.equal(h.panel.deletePlayer(STAFF, 'license:player'), false);
    assert.equal(h.panel.rotateKey(STAFF), false);
    h.advance(9999);
    assert.equal(h.panel.panelOpen(STAFF), false);
    h.advance(1);
    assert.equal(h.panel.panelOpen(STAFF), true);
    const code = makeHarness();
    code.panel.panelOpenCase(STAFF, PLAYER);
    code.sent.length = 0;
    for (let i = 0; i < 3; i += 1) assert.equal(code.panel.requestCode(PLAYER), true);
    assert.equal(code.sent.length, 3);
    assert.equal(code.panel.requestCode(PLAYER), false);
    assert.equal(code.sent.length, 3);
});

test('bad arguments are refused without throwing', () => {
    const h = makeHarness();
    assert.deepEqual([h.panel.panelCase(STAFF, 12), h.sent.at(-1).payload.reason], [false, 'invalid_case_id']);
    assert.deepEqual([h.panel.panelCase(STAFF, 'missing'), h.sent.at(-1).payload.reason], [false, 'case_not_found']);
    assert.deepEqual([h.panel.panelOpenCase(STAFF, {}), h.sent.at(-1).payload.reason], [false, 'invalid_target']);
    assert.deepEqual([h.panel.panelOpenCase(STAFF, 999), h.sent.at(-1).payload.reason], [false, 'player_not_found']);
    assert.deepEqual([h.panel.saveSettings(STAFF, []), h.sent.at(-1).payload.reason], [false, 'invalid_settings']);
    assert.deepEqual([h.panel.deleteCase(STAFF, 7), h.sent.at(-1).payload.reason], [false, 'invalid_case_id']);
    assert.deepEqual([h.panel.deletePlayer(STAFF, 7), h.sent.at(-1).payload.reason], [false, 'invalid_identifier']);
});

test('playerCases normalises a source to String on set and get', () => {
    const numberOpen = makeHarness();
    assert.equal(numberOpen.panel.panelOpenCase(STAFF, PLAYER), true);
    numberOpen.sent.length = 0;
    assert.equal(numberOpen.panel.requestCode(String(PLAYER)), true);
    assert.equal(numberOpen.sent[0].src, String(PLAYER));

    const stringOpen = makeHarness();
    assert.equal(stringOpen.panel.panelOpenCase(STAFF, String(PLAYER)), true);
    stringOpen.sent.length = 0;
    assert.equal(stringOpen.panel.requestCode(PLAYER), true);
    assert.equal(stringOpen.sent[0].src, PLAYER);
});

test('playerDropped removes the open pairing so a reused source gets no old code', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    h.sent.length = 0;
    assert.equal(h.panel.playerDropped(String(PLAYER)), true);
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.deepEqual(h.sent, []);
    assert.equal(h.panel.playerDropped(PLAYER), false);
});

test('saveSettings applies a valid patch and refuses a bad one whole', () => {
    const h = makeHarness();
    assert.equal(h.panel.saveSettings(STAFF, { serverName: 'Other City', ttlMs: 60000 }), true);
    assert.equal(h.settings.get().serverName, 'Other City');
    assert.equal(h.settings.get().ttlMs, 60000);
    const saved = h.sent.at(-1);
    assert.equal(saved.event, 'nakara_rongroi:settings:data');
    assert.equal(saved.payload.screen, 'settings');
    assert.equal(saved.payload.settings.serverName, 'Other City');
    assert.equal(saved.payload.settings.ttlMs, 60000);
    assert.equal(saved.payload.policy.server_name, 'Other City');
    assert.equal(saved.payload.policyHash, policyHash(saved.payload.policy));

    const before = h.settings.get();
    assert.equal(h.panel.saveSettings(STAFF, { serverName: 'Half Applied', ttlMs: 1 }), false);
    assert.deepEqual(h.sent.at(-1).payload, { screen: 'error', reason: 'invalid_ttl_ms' });
    const after = h.settings.get();
    assert.equal(after.serverName, before.serverName);
    assert.equal(after.ttlMs, before.ttlMs);
});

test('settingsOpen sends the settings, policy and hash for either screen to staff only', () => {
    const h = makeHarness();
    assert.equal(h.panel.settingsOpen(2, 'settings'), false);
    assert.deepEqual(h.sent, []);

    assert.equal(h.panel.settingsOpen(STAFF, 'settings'), true);
    const settingsMessage = h.sent.at(-1);
    assert.equal(settingsMessage.src, STAFF);
    assert.equal(settingsMessage.event, 'nakara_rongroi:settings:data');
    assert.equal(settingsMessage.payload.screen, 'settings');
    assert.equal(settingsMessage.payload.settings.serverName, 'Example City');
    assert.equal(settingsMessage.payload.policy.profile, 'posture');
    assert.equal(settingsMessage.payload.policy.server_name, 'Example City');
    assert.equal(settingsMessage.payload.policyHash, policyHash(settingsMessage.payload.policy));

    assert.equal(h.panel.settingsOpen(STAFF, 'policy'), true);
    assert.equal(h.sent.at(-1).payload.screen, 'policy');
    assert.equal(h.panel.settingsOpen(STAFF, 'cases'), false);
    assert.deepEqual(h.sent.at(-1).payload, { screen: 'error', reason: 'invalid_screen' });
});

test('saveSettings replies with the policy screen when the patch carried a policy', () => {
    const h = makeHarness();
    assert.equal(h.panel.saveSettings(STAFF, { policy: { profile: 'standard' } }), true);
    const saved = h.sent.at(-1).payload;
    assert.equal(saved.screen, 'policy');
    assert.equal(saved.settings.policy.profile, 'standard');
    assert.equal(saved.policy.profile, 'standard');
    assert.equal(saved.policyHash, policyHash(saved.policy));
});

test('deleteCase removes the case, forgets its ticket and drops the player code', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    const entry = h.storage.entries()[0];
    assert.notEqual(h.store.stateOf(entry.ticket), 'unknown');
    h.sent.length = 0;
    assert.equal(h.panel.deleteCase(STAFF, entry.caseId), true);
    assert.equal(h.storage.getCase(entry.caseId), null);
    assert.equal(h.store.stateOf(entry.ticket), 'unknown');
    assert.equal(h.sent.at(-1).event, 'nakara_rongroi:panel:data');
    assert.equal(h.sent.at(-1).payload.screen, 'cases');
    assert.deepEqual(h.sent.at(-1).payload.cases, []);
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.deepEqual(h.sent, []);
    assert.equal(h.panel.deleteCase(STAFF, entry.caseId), false);
    assert.deepEqual(h.sent.at(-1).payload, { screen: 'error', reason: 'case_not_found' });
});

test('deletePlayer removes every case of the identifier and forgets each ticket', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    assert.equal(h.panel.panelOpenCase(STAFF, ALT_PLAYER), true);
    const tickets = h.storage.entries().map((entry) => entry.ticket);
    assert.equal(tickets.length, 2);
    for (const ticket of tickets) assert.notEqual(h.store.stateOf(ticket), 'unknown');
    h.sent.length = 0;
    assert.equal(h.panel.deletePlayer(STAFF, 'license:player'), true);
    assert.deepEqual(h.storage.entries(), []);
    for (const ticket of tickets) assert.equal(h.store.stateOf(ticket), 'unknown');
    assert.equal(h.sent.at(-1).payload.screen, 'cases');
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.equal(h.panel.requestCode(ALT_PLAYER), false);
    assert.deepEqual(h.sent, []);
});

test('deletePlayerDataAndForget drops the identifier cases, tickets and player code', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    const entry = h.storage.entries()[0];
    h.sent.length = 0;
    assert.deepEqual(h.panel.deletePlayerDataAndForget('license:player'), [entry.ticket]);
    assert.deepEqual(h.storage.entries(), []);
    assert.equal(h.store.stateOf(entry.ticket), 'unknown');
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.deepEqual(h.sent, []);
});

test('deleteCaseAndForget is the retention pass helper', () => {
    const h = makeHarness();
    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    const entry = h.storage.entries()[0];
    assert.equal(h.panel.deleteCaseAndForget(entry.caseId), entry.ticket);
    assert.equal(h.storage.getCase(entry.caseId), null);
    assert.equal(h.store.stateOf(entry.ticket), 'unknown');
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.deepEqual(h.sent, []);
    assert.equal(h.panel.deleteCaseAndForget(entry.caseId), false);
});

test('rotateKey calls rotateKitKey once and invalidates issued and uploading tickets only', () => {
    const h = makeHarness();
    const expired = h.store.issue({ caseId: 'case-expired', policy: {} });
    h.advance(300001);
    h.store.lookup(expired.ticket);
    assert.equal(h.store.stateOf(expired.ticket), 'expired');

    assert.equal(h.panel.panelOpenCase(STAFF, PLAYER), true);
    const openTicket = h.storage.entries()[0].ticket;
    assert.equal(h.store.stateOf(openTicket), 'issued');

    const uploading = h.store.issue({ caseId: 'case-uploading', policy: {} });
    assert.equal(h.store.beginUpload(uploading.ticket, 'b'.repeat(64)).ok, true);

    const consumed = h.store.issue({ caseId: 'case-consumed', policy: {} });
    assert.equal(h.store.beginUpload(consumed.ticket, 'a'.repeat(64)).ok, true);
    assert.equal(h.store.consume(consumed.ticket, 'a'.repeat(64)).ok, true);

    const oldPrivateKey = h.kit.privateKey;
    h.sent.length = 0;
    assert.equal(h.panel.rotateKey(STAFF), true);
    assert.equal(h.rotateCalls(), 1);
    assert.notEqual(h.kit.privateKey, oldPrivateKey);
    assert.equal(h.store.stateOf(openTicket), 'unknown');
    assert.equal(h.store.stateOf(uploading.ticket), 'unknown');
    assert.equal(h.store.stateOf(expired.ticket), 'expired');
    assert.equal(h.store.stateOf(consumed.ticket), 'consumed');
    const rotated = h.sent.at(-1);
    assert.equal(rotated.event, 'nakara_rongroi:settings:data');
    assert.equal(rotated.payload.screen, 'settings');
    assert.equal(rotated.payload.settings.serverName, 'Example City');
    assert.equal(rotated.payload.policyHash, policyHash(rotated.payload.policy));
    h.sent.length = 0;
    assert.equal(h.panel.requestCode(PLAYER), false);
    assert.deepEqual(h.sent, []);
});

test('rate limit windows prune ended entries only above 256 entries', () => {
    const windows = new Map();
    for (let i = 0; i < 256; i += 1) windows.set(`staff:${i}`, { end: 2000, count: 1 });
    windows.set('staff:ended', { end: 999, count: 1 });
    assert.equal(windows.size, 257);
    pruneRateWindows(windows, 1000);
    assert.equal(windows.has('staff:ended'), false);
    assert.equal(windows.has('staff:1'), true);
    assert.equal(windows.size, 256);

    windows.delete('staff:0');
    windows.set('staff:ended-again', { end: 999, count: 1 });
    assert.equal(windows.size, 256);
    pruneRateWindows(windows, 1000);
    assert.equal(windows.has('staff:ended-again'), true);
    assert.equal(windows.size, 256);
});
