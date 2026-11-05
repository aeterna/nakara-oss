'use strict';

// Chunked POST report/chunk tests: reassembly, retries, limits and the shared finish path, on a
// hand-advanced clock. The harness mirrors spec/http.test.js.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { sealEnvelope } = require('../server/js/envelope.js');
const { TicketStore } = require('../server/js/tickets.js');
const { createHandler } = require('../server/js/http.js');
const kit = require('../test-vectors/envelope-v1.json').kit;
const POLICY = { collectors: ['a'], version: 2 };
const SLICE = 4096;

function makeHarness(options = {}) {
    let ms = 1000000;
    let next = 0;
    const store = new TicketStore({
        now: () => ms,
        randomBytes: (n) => Buffer.from(Array.from({ length: n }, () => next = (next + 1) & 0xff)),
    });
    const reports = [];
    const handler = createHandler({
        store, kit, now: () => ms,
        onReport: options.onReport || ((event) => reports.push(event)),
        log: () => {},
    });
    return { store, handler, reports, advance: (delta) => { ms += delta; } };
}

function issue(h, changes = {}) {
    return h.store.issue({ caseId: 'case-1', policy: POLICY, ...changes });
}

function call(h, method, path, headers, body) {
    const req = {
        method, path, headers: headers || {}, dataHandler: null,
        setDataHandler(cb) { this.dataHandler = cb; },
        deliver() {
            assert.equal(typeof this.dataHandler, 'function', 'handler must request the body');
            this.dataHandler(body);
        },
    };
    const res = {
        status: null, headers: null, body: null,
        writeHead(status, headers) { this.status = status; this.headers = headers || {}; },
        send(body) { this.body = body; },
    };
    h.handler(req, res);
    return { req, res, json: () => JSON.parse(res.body) };
}

function sha(value) {
    return crypto.createHash('sha256').update(value).digest('hex');
}

function envelope(record, ticket) {
    return sealEnvelope(JSON.stringify(record), kit.publicKey, ticket);
}

function sealed(h, changes = {}) {
    const { ticket, nonce } = issue(h, changes.issue);
    return { ticket, nonce, body: envelope({ schema: 2, binding: { ticket, nonce }, ...changes.record }, ticket) };
}

function split(body, size = SLICE) {
    const bytes = Buffer.from(body);
    const slices = [];
    for (let i = 0; i < bytes.length; i += size) slices.push(bytes.subarray(i, i + size));
    return slices;
}

function headers(ticket, reportSha, chunkSha, index, total, extra = {}) {
    return {
        'x-rongroi-upload-id': ticket, 'x-rongroi-report-sha256': reportSha,
        'x-rongroi-chunk-sha256': chunkSha, 'x-rongroi-chunk-index': String(index),
        'x-rongroi-chunk-total': String(total), ...extra,
    };
}

function post(h, ticket, reportSha, index, total, chunk, extra = {}) {
    const more = { 'content-length': String(Buffer.byteLength(chunk)), ...extra };
    return call(h, 'POST', '/report/chunk', headers(ticket, reportSha, sha(chunk), index, total, more), chunk);
}

function sendAll(h, ticket, body, options = {}) {
    const reportSha = options.reportSha || sha(body);
    const slices = options.slices || split(body, options.size);
    const results = slices.map((chunk, index) => {
        const result = post(h, ticket, reportSha, index, slices.length, chunk, options.extra);
        result.req.deliver();
        return result;
    });
    return { reportSha, slices, results };
}

test('chunked upload accepts a report larger than the direct limit', () => {
    const h = makeHarness();
    const { ticket, body } = sealed(h, { record: { note: 'x'.repeat(8000) } });
    assert.ok(Buffer.byteLength(body) > 7168);
    const { results } = sendAll(h, ticket, body);
    assert.ok(results.length >= 2 && results.every((result) => result.res.status === 200));
    assert.equal(h.reports.length, 1);
    assert.equal(h.store.stateOf(ticket), 'consumed');
});

test('a declined answer sent as two slices reports once', () => {
    const h = makeHarness();
    const { ticket, body } = sealed(h, { issue: { caseId: 'case-2' }, record: { scan: 'declined', note: 'x'.repeat(5000) } });
    const { slices, results } = sendAll(h, ticket, body);
    assert.equal(slices.length, 2);
    assert.equal(results[1].res.status, 200);
    assert.deepEqual(h.reports, [{ caseId: 'case-2', ticket, reportSha256: sha(body), receivedAt: 1000000, declined: true }]);
});

test('a retry is 200 without reading and a different sha at that index is 422', () => {
    const h = makeHarness();
    const one = sealed(h, { record: { note: 'x'.repeat(5000) } });
    const slices = split(one.body);
    const first = post(h, one.ticket, sha(one.body), 0, 2, slices[0]);
    first.req.deliver();
    assert.equal(first.res.status, 200);
    const retry = post(h, one.ticket, sha(one.body), 0, 2, slices[0]);
    assert.deepEqual([retry.res.status, retry.req.dataHandler], [200, null]);
    const last = post(h, one.ticket, sha(one.body), 1, 2, slices[1]);
    last.req.deliver();
    assert.equal(last.res.status, 200);
    assert.equal(h.reports.length, 1);
    const two = sealed(h, { issue: { caseId: 'case-2' }, record: { note: 'x'.repeat(5000) } });
    const twoSlices = split(two.body);
    const twoFirst = post(h, two.ticket, sha(two.body), 0, 2, twoSlices[0]);
    twoFirst.req.deliver();
    assert.equal(twoFirst.res.status, 200);
    const wrong = post(h, two.ticket, sha(two.body), 0, 2, twoSlices[0], { 'x-rongroi-chunk-sha256': sha('other') });
    assert.deepEqual([wrong.res.status, wrong.req.dataHandler], [422, null]);
    assert.equal(h.store.openForTicket(two.ticket), 0);
});

test('out of order and a missing buffer are 422, and the ticket can start again', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    const body = Buffer.alloc(9000, 7);
    const reportSha = sha(body);
    const slices = split(body);
    const first = post(h, ticket, reportSha, 0, 3, slices[0]);
    first.req.deliver();
    assert.equal(first.res.status, 200);
    const skipped = post(h, ticket, reportSha, 2, 3, slices[2]);
    assert.deepEqual([skipped.res.status, skipped.req.dataHandler], [422, null]);
    const restart = post(h, ticket, reportSha, 0, 3, slices[0]);
    restart.req.deliver();
    assert.equal(restart.res.status, 200);
    const other = issue(h, { caseId: 'case-2' });
    const missing = post(h, other.ticket, reportSha, 1, 2, slices[1]);
    assert.deepEqual([missing.res.status, missing.req.dataHandler], [422, null]);
    assert.equal(h.store.openForTicket(other.ticket), 0);
});

test('a bad whole hash, slice hash or middle length is 422 without consuming', () => {
    const h = makeHarness();
    const mismatch = sealed(h);
    const sent = sendAll(h, mismatch.ticket, mismatch.body, { reportSha: sha('other') });
    assert.equal(sent.results.at(-1).res.status, 422);
    assert.equal(h.store.stateOf(mismatch.ticket), 'issued');
    const wrong = sealed(h, { issue: { caseId: 'case-2' } });
    const badSlice = post(h, wrong.ticket, sha(wrong.body), 0, 1, wrong.body, { 'x-rongroi-chunk-sha256': sha('other') });
    badSlice.req.deliver();
    assert.equal(badSlice.res.status, 422);
    assert.equal(h.store.stateOf(wrong.ticket), 'issued');
    const short = issue(h, { caseId: 'case-3' });
    const shortBody = Buffer.alloc(100, 2);
    const middle = post(h, short.ticket, sha(shortBody), 0, 2, shortBody);
    middle.req.deliver();
    assert.equal(middle.res.status, 422);
    assert.equal(h.store.openForTicket(short.ticket), 0);
    assert.equal(h.reports.length, 0);
});

test('slice, total and header limits are refused before the body is read', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    const large = Buffer.alloc(SLICE + 1, 3);
    const bodyTooLarge = post(h, ticket, sha(large), 0, 2, large, { 'content-length': '1' });
    bodyTooLarge.req.deliver();
    assert.equal(bodyTooLarge.res.status, 413);
    const tiny = Buffer.alloc(1, 4);
    const total = post(h, ticket, sha(tiny), 0, 513, tiny);
    assert.deepEqual([total.res.status, total.req.dataHandler], [413, null]);
    const chunk = Buffer.from('abc');
    const base = headers(ticket, sha(chunk), sha(chunk), 0, 1);
    for (const bad of [
        { ...base, 'x-rongroi-upload-id': 'nothex' },
        { ...base, 'x-rongroi-report-sha256': 'a'.repeat(63) },
        { ...base, 'x-rongroi-chunk-sha256': 'A'.repeat(64) },
        { ...base, 'x-rongroi-chunk-index': '1.5' },
        { ...base, 'x-rongroi-chunk-total': '-1' },
        { ...base, 'x-rongroi-chunk-total': '0' },
        { ...base, 'x-rongroi-chunk-index': '1', 'x-rongroi-chunk-total': '1' },
    ]) {
        const result = call(h, 'POST', '/report/chunk', bad, chunk);
        assert.deepEqual([result.res.status, result.req.dataHandler], [400, null]);
    }
    assert.equal(call(h, 'GET', '/report/chunk').res.status, 405);
});

test('a consumed ticket repeats 200 and another envelope is 409 without reading', () => {
    const h = makeHarness();
    const { ticket, body } = sealed(h);
    sendAll(h, ticket, body);
    const repeat = post(h, ticket, sha(body), 0, 1, body);
    assert.deepEqual([repeat.res.status, repeat.req.dataHandler], [200, null]);
    const other = post(h, ticket, sha('other'), 0, 1, Buffer.from('x'));
    assert.deepEqual([other.res.status, other.req.dataHandler], [409, null]);
});

test('an idle upload is swept and its next slice is 422', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    const body = Buffer.alloc(SLICE + 10, 5);
    const reportSha = sha(body);
    const slices = split(body);
    const first = post(h, ticket, reportSha, 0, 2, slices[0]);
    first.req.deliver();
    assert.equal(first.res.status, 200);
    h.advance(60000);
    h.handler.sweep();
    const next = post(h, ticket, reportSha, 1, 2, slices[1]);
    assert.deepEqual([next.res.status, next.req.dataHandler], [422, null]);
    assert.equal(h.store.openForTicket(ticket), 0);
});

test('a consumed upload frees its rival on the same ticket', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const bodyA = envelope({ schema: 2, binding: { ticket, nonce }, note: 'A'.repeat(5000) }, ticket);
    const bodyB = envelope({ schema: 2, binding: { ticket, nonce }, note: 'B'.repeat(5000) }, ticket);
    const shaA = sha(bodyA);
    const shaB = sha(bodyB);
    const a = split(bodyA);
    const b = split(bodyB);
    let result = post(h, ticket, shaA, 0, 2, a[0]);
    result.req.deliver();
    assert.equal(result.res.status, 200);
    result = post(h, ticket, shaB, 0, 2, b[0]);
    result.req.deliver();
    assert.equal(result.res.status, 200);
    result = post(h, ticket, shaA, 1, 2, a[1]);
    result.req.deliver();
    assert.equal(result.res.status, 200);
    assert.equal(h.reports.length, 1);
    const rival = post(h, ticket, shaB, 1, 2, b[1]);
    assert.deepEqual([rival.res.status, rival.req.dataHandler], [409, null]);
});

test('the 17th open upload is 429 with Retry-After: 5', () => {
    const h = makeHarness();
    for (let i = 0; i < 16; i += 1) {
        const { ticket } = issue(h, { caseId: `case-${i}` });
        const body = Buffer.alloc(SLICE, i);
        const result = post(h, ticket, sha(body), 0, 2, body);
        result.req.deliver();
        assert.equal(result.res.status, 200);
    }
    const { ticket } = issue(h, { caseId: 'case-17' });
    const body = Buffer.alloc(SLICE, 17);
    const capped = post(h, ticket, sha(body), 0, 2, body);
    assert.deepEqual([capped.res.status, capped.req.dataHandler], [429, null]);
    assert.equal(capped.res.headers['Retry-After'], '5');
});
