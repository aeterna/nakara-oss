'use strict';

// Ticket store tests: every state transition of ADR 0089 section 5, run on a hand-advanced clock and a
// counted random source, so no test depends on the real time or on crypto.
const test = require('node:test');
const assert = require('node:assert/strict');
const { TicketStore } = require('../server/js/tickets.js');

const TICKET_RE = /^[0-9a-f]{32}$/;
const NONCE_RE = /^[0-9a-f]{12}$/;
const SHA_A = 'a'.repeat(64);
const SHA_B = 'b'.repeat(64);
const TTL = 300000; // default ticket lifetime, ADR 0001 section 3
const IDLE = 60000; // buffer idle limit, ADR 0089 section 4

// A store on a clock the test moves by hand and a random source that counts, so tickets and nonces are
// deterministic and distinct. `firstByte` keeps two stores' random streams apart.
function makeStore(startMs = 1000000, firstByte = 0) {
    let ms = startMs;
    let next = firstByte;
    const randomBytes = (n) => {
        const bytes = [];
        for (let i = 0; i < n; i += 1) {
            next = (next + 1) & 0xff;
            bytes.push(next);
        }
        return Buffer.from(bytes);
    };
    return {
        store: new TicketStore({ now: () => ms, randomBytes }),
        advance: (delta) => { ms += delta; },
    };
}

function issue(store, changes = {}) {
    return store.issue({ caseId: 'case-1', policy: { collectors: [] }, ...changes });
}

test('issue returns a 32 hex ticket, a 12 hex nonce and the default 300000 ms lifetime', () => {
    const { store } = makeStore(5000);
    const issued = issue(store);
    assert.match(issued.ticket, TICKET_RE);
    assert.match(issued.nonce, NONCE_RE);
    assert.equal(issued.issuedAt, 5000);
    assert.equal(issued.expiresAt, 5000 + TTL);
    assert.equal(issue(store, { ttlMs: 50 }).expiresAt, 5050); // a custom ttlMs is honoured
    assert.equal(store.stateOf(issued.ticket), 'issued');
});

test('issued -> uploading when an upload is accepted', () => {
    const { store } = makeStore();
    const { ticket } = issue(store);
    assert.deepEqual(store.beginUpload(ticket, SHA_A), { ok: true, status: 200, uploadId: 1 });
    assert.equal(store.stateOf(ticket), 'uploading');
});

test('uploading -> consumed after the envelope authenticated and the nonce matched', () => {
    const { store } = makeStore();
    const { ticket } = issue(store, { caseId: 'case-9', policy: { name: 'Nakara' } });
    const first = store.beginUpload(ticket, SHA_A);
    const second = store.beginUpload(ticket, SHA_A);
    assert.deepEqual(store.consume(ticket, SHA_A), {
        ok: true,
        status: 200,
        caseId: 'case-9',
        policy: { name: 'Nakara' },
        dropped: [first.uploadId, second.uploadId],
    });
    assert.equal(store.stateOf(ticket), 'consumed');
    assert.equal(store.touch(first.uploadId), false); // consuming dropped both open buffers
    assert.equal(store.drop(second.uploadId), false);
});

test('an unknown ticket is 404 for uploads and for consume', () => {
    const { store } = makeStore();
    assert.deepEqual(store.beginUpload('d'.repeat(32), SHA_A), { ok: false, status: 404 });
    assert.deepEqual(store.consume('c'.repeat(32), SHA_A), { ok: false, status: 404 });
});

test('uploading -> issued on drop: a failed upload never consumes the ticket', () => {
    const { store } = makeStore();
    const { ticket } = issue(store);
    const { uploadId } = store.beginUpload(ticket, SHA_A);
    assert.equal(store.drop(uploadId), true);
    assert.equal(store.drop(uploadId), false); // dropping twice changes nothing
    assert.equal(store.stateOf(ticket), 'issued');
    // The same envelope may be uploaded again, as a fresh upload with a fresh buffer.
    assert.deepEqual(store.beginUpload(ticket, SHA_A), { ok: true, status: 200, uploadId: 2 });
});

test('touch keeps a buffer alive and sweepIdle drops it after 60 s with no new slice', () => {
    const { store, advance } = makeStore();
    const { ticket } = issue(store);
    const { uploadId } = store.beginUpload(ticket, SHA_A);
    advance(50000);
    assert.equal(store.touch(uploadId), true);
    advance(50000);
    assert.deepEqual(store.sweepIdle(), []); // 100 s since the first slice, 50 s since the last
    assert.equal(store.stateOf(ticket), 'uploading');
    advance(IDLE);
    assert.deepEqual(store.sweepIdle(), [uploadId]); // 110 s with no slice
    assert.equal(store.stateOf(ticket), 'issued');
});

test('an upload that started in time may finish past expires_at and still be consumed', () => {
    const { store, advance } = makeStore();
    const { ticket } = issue(store);
    store.beginUpload(ticket, SHA_A);
    advance(TTL + 1000);
    assert.equal(store.expireDue(), 0); // expireDue never touches an uploading ticket
    assert.equal(store.stateOf(ticket), 'uploading');
    assert.equal(store.consume(ticket, SHA_A).status, 200);
    assert.equal(store.stateOf(ticket), 'consumed');
});

test('a buffer dropped past expires_at leaves the ticket expired, not issued', () => {
    const { store, advance } = makeStore();
    const { ticket } = issue(store);
    const { uploadId } = store.beginUpload(ticket, SHA_A);
    advance(TTL + 1000);
    store.drop(uploadId);
    assert.equal(store.stateOf(ticket), 'expired');
    assert.deepEqual(store.beginUpload(ticket, SHA_A), { ok: false, status: 410 });
});

test('issued -> expired at expires_at: expireDue(), a lazy 410, then 410 for uploads and consume', () => {
    const { store, advance } = makeStore();
    const { ticket } = issue(store);
    advance(TTL);
    assert.equal(store.expireDue(), 1);
    assert.equal(store.stateOf(ticket), 'expired');
    assert.deepEqual(store.beginUpload(ticket, SHA_A), { ok: false, status: 410 });
    assert.deepEqual(store.consume(ticket, SHA_A), { ok: false, status: 410 });
    const late = issue(store).ticket; // past its ttl, a ticket is 410 even before expireDue() runs
    advance(TTL + 1);
    assert.deepEqual(store.beginUpload(late, SHA_A), { ok: false, status: 410 });
    assert.equal(store.stateOf(late), 'expired');
});

test('a consumed ticket answers 409, or 200 repeat for the same accepted envelope', () => {
    const { store } = makeStore();
    const { ticket } = issue(store);
    store.beginUpload(ticket, SHA_A);
    store.consume(ticket, SHA_A);

    assert.deepEqual(store.beginUpload(ticket, SHA_A), { ok: true, status: 200, repeat: true });
    assert.deepEqual(store.beginUpload(ticket, SHA_B), { ok: false, status: 409 });
    assert.equal(store.consume(ticket, SHA_A).repeat, true);
    assert.deepEqual(store.consume(ticket, SHA_B), { ok: false, status: 409 });
    assert.equal(store.stateOf(ticket), 'consumed');
});

test('a third open upload on one ticket is 429; dropping the last buffer returns to issued', () => {
    const { store } = makeStore();
    const { ticket } = issue(store);
    const first = store.beginUpload(ticket, SHA_A);
    const second = store.beginUpload(ticket, SHA_A);
    assert.deepEqual(store.beginUpload(ticket, SHA_A), { ok: false, status: 429 });
    assert.equal(store.stateOf(ticket), 'uploading');

    store.drop(first.uploadId); // one open buffer left keeps the ticket uploading
    assert.equal(store.stateOf(ticket), 'uploading');
    store.drop(second.uploadId);
    assert.equal(store.stateOf(ticket), 'issued');
    assert.equal(store.beginUpload(ticket, SHA_A).ok, true); // the per-ticket cap is freed
});

test('the seventeenth open upload in total is 429 until a slot is freed', () => {
    const { store } = makeStore();
    const tickets = [];
    for (let i = 0; i < 8; i += 1) {
        tickets.push(issue(store, { caseId: `case-${i}` }).ticket);
    }
    const open = [];
    for (const ticket of tickets) {
        open.push(store.beginUpload(ticket, SHA_A).uploadId);
        open.push(store.beginUpload(ticket, SHA_A).uploadId);
    }
    assert.equal(open.length, 16);
    const ninth = issue(store, { caseId: 'case-8' }).ticket;
    assert.deepEqual(store.beginUpload(ninth, SHA_A), { ok: false, status: 429 });

    store.drop(open[0]);
    assert.equal(store.beginUpload(ninth, SHA_A).ok, true);
});

test('a consumed ticket survives a restart through snapshotConsumed()/restoreConsumed()', () => {
    const { store } = makeStore();
    const { ticket } = issue(store, { caseId: 'case-9' });
    store.beginUpload(ticket, SHA_A);
    store.consume(ticket, SHA_A);
    const snapshot = JSON.parse(JSON.stringify(store.snapshotConsumed()));
    assert.deepEqual(snapshot, [
        { ticket, caseId: 'case-9', reportSha256: SHA_A, consumedAt: 1000000 },
    ]);

    const restarted = makeStore(9999, 200).store;
    restarted.restoreConsumed(snapshot);
    assert.equal(restarted.stateOf(ticket), 'consumed');
    assert.deepEqual(restarted.beginUpload(ticket, SHA_A), { ok: true, status: 200, repeat: true });
    assert.deepEqual(restarted.beginUpload(ticket, SHA_B), { ok: false, status: 409 });
    assert.notEqual(issue(restarted).ticket, ticket); // fresh cases still mint working tickets
    assert.throws(() => restarted.restoreConsumed(snapshot), TypeError); // a ticket is restored once
});

test('restoreConsumed rejects a malformed snapshot with a TypeError', () => {
    const { store } = makeStore();
    const entry = { ticket: 'f'.repeat(32), caseId: 'c', reportSha256: SHA_A, consumedAt: 1 };
    assert.throws(() => store.restoreConsumed('nope'), TypeError);
    assert.throws(() => store.restoreConsumed([{ ...entry, ticket: 'x' }]), TypeError);
    assert.throws(() => store.restoreConsumed([{ ...entry, reportSha256: 'zz' }]), TypeError);
    assert.throws(() => store.restoreConsumed([{ ...entry, caseId: '' }]), TypeError);
    assert.throws(() => store.restoreConsumed([{ ...entry, consumedAt: 'later' }]), TypeError);
});

test('malformed arguments throw a TypeError, like the envelope module', () => {
    const { store } = makeStore();
    assert.throws(() => issue(store, { caseId: '' }), TypeError);
    assert.throws(() => issue(store, { policy: 'no' }), TypeError);
    assert.throws(() => issue(store, { ttlMs: 0 }), TypeError);
    assert.throws(() => store.beginUpload('nothex', SHA_A), TypeError);
    assert.throws(() => store.beginUpload('a'.repeat(32), 'a'.repeat(63)), TypeError);
    assert.throws(() => store.consume('a'.repeat(32), SHA_B.toUpperCase()), TypeError);
    assert.throws(() => new TicketStore({ now: () => 0 }), TypeError);
    assert.throws(() => new TicketStore(), TypeError);
});
