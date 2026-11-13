'use strict';

// Robustness tests: a thrown handler still answers, concurrent copies of one slice, aborted requests,
// the mandatory Content-Length and the refused-request counter. The harness mirrors spec/http.test.js.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { sealEnvelope } = require('../server/js/envelope.js');
const { TicketStore } = require('../server/js/tickets.js');
const { createHandler } = require('../server/js/http.js');
const kit = require('../test-vectors/envelope-v1.json').kit;
const POLICY = { collectors: ['a'], version: 2 };
const SLICE = 4096;
const TTL = 300000;

function makeHarness() {
    let ms = 1000000;
    let next = 0;
    const store = new TicketStore({
        now: () => ms,
        randomBytes: (n) => Buffer.from(Array.from({ length: n }, () => next = (next + 1) & 0xff)),
    });
    const logs = [], reports = [];
    const handler = createHandler({
        store, kit, now: () => ms, onReport: (event) => reports.push(event), log: (...a) => logs.push(a),
    });
    return { store, handler, logs, reports, advance: (delta) => { ms += delta; } };
}
const issue = (h, changes = {}) => h.store.issue({ caseId: 'case-1', policy: POLICY, ...changes });

function call(h, method, path, headers, body) {
    const req = {
        method, path, headers: headers || {}, dataHandler: null, cancelHandler: null,
        setDataHandler(cb) { this.dataHandler = cb; },
        setCancelHandler(cb) { this.cancelHandler = cb; },
        deliver() { this.dataHandler(body); },
        cancel() { assert.equal(typeof this.cancelHandler, 'function'); this.cancelHandler(); },
    };
    const res = {
        status: null, headers: null, body: null,
        writeHead(status, headers) { this.status = status; this.headers = headers || {}; },
        send(body) { this.body = body; },
    };
    h.handler(req, res);
    return { req, res, json: () => JSON.parse(res.body) };
}
const sha = (value) => crypto.createHash('sha256').update(value).digest('hex');
const envelope = (record, ticket) => sealEnvelope(JSON.stringify(record), kit.publicKey, ticket);

function split(body, size = SLICE) {
    const bytes = Buffer.from(body);
    const slices = [];
    for (let i = 0; i < bytes.length; i += size) slices.push(bytes.subarray(i, i + size));
    return slices;
}
function report(h, ticket, body, extra = {}) {
    return call(h, 'POST', '/report', {
        'x-rongroi-upload-id': ticket, 'x-rongroi-report-sha256': sha(body),
        'content-length': String(Buffer.byteLength(body)), ...extra,
    }, body);
}
function post(h, ticket, reportSha, chunk, index, total, extra = {}) {
    return call(h, 'POST', '/report/chunk', {
        'x-rongroi-upload-id': ticket, 'x-rongroi-report-sha256': reportSha,
        'x-rongroi-chunk-sha256': sha(chunk), 'x-rongroi-chunk-index': String(index),
        'x-rongroi-chunk-total': String(total),
        'content-length': String(Buffer.byteLength(chunk)), ...extra,
    }, chunk);
}

test('a policy canonicalization refuses answers 500 and later requests still work', () => {
    const h = makeHarness();
    const broken = issue(h, { policy: { a: undefined } });
    const failed = call(h, 'GET', `/policy/${broken.ticket}`);
    assert.deepEqual([failed.res.status, failed.json().status], [500, 500]);
    assert.match(JSON.stringify(h.logs), /request failed/);
    assert.equal(JSON.stringify(h.logs).includes(broken.ticket), true);
    const good = issue(h, { caseId: 'case-2' });
    assert.equal(call(h, 'GET', `/policy/${good.ticket}`).json().version, 2);
});
test('concurrent copies of a middle and of the last slice answer 200 and report once', () => {
    const h = makeHarness();
    const middle = issue(h);
    const middleBody = envelope({
        schema: 2,
        binding: { ticket: middle.ticket, nonce: middle.nonce },
        note: ['x'.repeat(4000), 'x'.repeat(4000), 'x'.repeat(992)],
    }, middle.ticket);
    const middleSha = sha(middleBody);
    const slices = split(middleBody);
    assert.equal(slices.length, 3);
    post(h, middle.ticket, middleSha, slices[0], 0, 3).req.deliver();
    const copyA = post(h, middle.ticket, middleSha, slices[1], 1, 3);
    const copyB = post(h, middle.ticket, middleSha, slices[1], 1, 3);
    copyA.req.deliver();
    copyB.req.deliver();
    assert.deepEqual([copyA.res.status, copyB.res.status], [200, 200]);
    post(h, middle.ticket, middleSha, slices[2], 2, 3).req.deliver();
    assert.equal(h.store.stateOf(middle.ticket), 'consumed');
    assert.equal(h.reports.length, 1);

    const ending = issue(h, { caseId: 'case-2' });
    const endBody = envelope({
        schema: 2,
        binding: { ticket: ending.ticket, nonce: ending.nonce },
        note: ['y'.repeat(4000), 'y'.repeat(995)],
    }, ending.ticket);
    const endSha = sha(endBody);
    const endSlices = split(endBody);
    assert.equal(endSlices.length, 2);
    post(h, ending.ticket, endSha, endSlices[0], 0, 2).req.deliver();
    const endA = post(h, ending.ticket, endSha, endSlices[1], 1, 2);
    const endB = post(h, ending.ticket, endSha, endSlices[1], 1, 2);
    endA.req.deliver();
    endB.req.deliver();
    assert.deepEqual([endA.res.status, endB.res.status], [200, 200]);
    assert.equal(h.reports.length, 2);
    assert.equal(h.store.stateOf(ending.ticket), 'consumed');
});
test('a stale copy after the buffer was dropped does not delete a newer buffer', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce }, note: 'x'.repeat(5000) }, ticket);
    const reportSha = sha(body);
    const slices = split(body);
    const stale = post(h, ticket, reportSha, slices[0], 0, 2);
    h.advance(60000);
    h.handler.sweep();
    const fresh = post(h, ticket, reportSha, slices[0], 0, 2);
    fresh.req.deliver();
    assert.equal(fresh.res.status, 200);
    stale.req.deliver();
    assert.equal(stale.res.status, 422);
    const last = post(h, ticket, reportSha, slices[1], 1, 2);
    last.req.deliver();
    assert.equal(last.res.status, 200);
    assert.equal(h.reports.length, 1);
});
test('a direct POST whose upload slot was swept answers 422 and leaves the ticket usable', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const pending = report(h, ticket, body);
    h.advance(60000);
    h.handler.sweep();
    assert.equal(h.store.stateOf(ticket), 'issued');
    pending.req.deliver();
    assert.deepEqual([pending.res.status, h.reports.length], [422, 0]);
    assert.match(JSON.stringify(h.logs), /upload slot gone/);
    const retry = report(h, ticket, body);
    retry.req.deliver();
    assert.equal(retry.res.status, 200);
    assert.equal(h.reports.length, 1);
    assert.equal(h.store.stateOf(ticket), 'consumed');
});
test('a direct POST for an expired ticket answers 410 and never reports', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const pending = report(h, ticket, body);
    h.advance(TTL);
    h.handler.sweep();
    assert.equal(h.store.stateOf(ticket), 'expired');
    pending.req.deliver();
    assert.deepEqual([pending.res.status, h.reports.length], [410, 0]);
});
test('a chunked upload finishes on its last slice while its slot stays open', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce }, note: 'x'.repeat(5000) }, ticket);
    const reportSha = sha(body);
    const slices = split(body);
    assert.equal(slices.length, 2);
    post(h, ticket, reportSha, slices[0], 0, 2).req.deliver();
    h.handler.sweep();
    const last = post(h, ticket, reportSha, slices[1], 1, 2);
    last.req.deliver();
    assert.equal(last.res.status, 200);
    assert.equal(h.reports.length, 1);
    assert.equal(h.store.stateOf(ticket), 'consumed');
});
test('an aborted request drops only what is unsafe and a cancel after reply does nothing', () => {
    const h = makeHarness();
    const direct = issue(h);
    const directBody = envelope({ schema: 2, binding: { ticket: direct.ticket, nonce: direct.nonce } }, direct.ticket);
    const pending = report(h, direct.ticket, directBody);
    pending.req.cancel();
    assert.deepEqual([h.store.openForTicket(direct.ticket), h.store.stateOf(direct.ticket)], [0, 'issued']);
    pending.req.deliver();
    assert.deepEqual([pending.res.status, h.reports.length], [null, 0]);

    const first = issue(h, { caseId: 'case-2' });
    const firstBody = envelope({ schema: 2, binding: { ticket: first.ticket, nonce: first.nonce }, note: 'x'.repeat(5000) }, first.ticket);
    const firstSha = sha(firstBody);
    const firstSlices = split(firstBody);
    const aborted = post(h, first.ticket, firstSha, firstSlices[0], 0, 2);
    aborted.req.cancel();
    assert.equal(h.store.openForTicket(first.ticket), 0);
    aborted.req.deliver();
    assert.equal(aborted.res.status, null);
    assert.equal(post(h, first.ticket, firstSha, firstSlices[1], 1, 2).res.status, 422);

    const later = issue(h, { caseId: 'case-3' });
    const laterBody = envelope({ schema: 2, binding: { ticket: later.ticket, nonce: later.nonce }, note: 'x'.repeat(5000) }, later.ticket);
    const laterSha = sha(laterBody);
    const laterSlices = split(laterBody);
    post(h, later.ticket, laterSha, laterSlices[0], 0, 2).req.deliver();
    const cancelled = post(h, later.ticket, laterSha, laterSlices[1], 1, 2);
    cancelled.req.cancel();
    assert.equal(h.store.openForTicket(later.ticket), 1);
    cancelled.req.deliver();
    assert.equal(cancelled.res.status, null);
    const retry = post(h, later.ticket, laterSha, laterSlices[1], 1, 2);
    retry.req.deliver();
    assert.equal(retry.res.status, 200);
    assert.equal(h.reports.length, 1);

    const replied = issue(h, { caseId: 'case-4' });
    const repliedBody = envelope({ schema: 2, binding: { ticket: replied.ticket, nonce: replied.nonce }, note: 'x'.repeat(5000) }, replied.ticket);
    const repliedSha = sha(repliedBody);
    const repliedSlices = split(repliedBody);
    const answered = post(h, replied.ticket, repliedSha, repliedSlices[0], 0, 2);
    answered.req.deliver();
    answered.req.cancel();
    assert.equal(h.store.openForTicket(replied.ticket), 1);
    const last = post(h, replied.ticket, repliedSha, repliedSlices[1], 1, 2);
    last.req.deliver();
    assert.equal(last.res.status, 200);
    assert.equal(h.reports.length, 2);
});
test('a report or chunk without Content-Length is 400 before the ticket is touched', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const direct = call(h, 'POST', '/report', {
        'x-rongroi-upload-id': ticket, 'x-rongroi-report-sha256': sha(body),
    }, body);
    assert.deepEqual([direct.res.status, direct.req.dataHandler, h.store.stateOf(ticket)], [400, null, 'issued']);
    const chunk = call(h, 'POST', '/report/chunk', {
        'x-rongroi-upload-id': ticket, 'x-rongroi-report-sha256': sha(body),
        'x-rongroi-chunk-sha256': sha(body), 'x-rongroi-chunk-index': '0', 'x-rongroi-chunk-total': '1',
    }, body);
    assert.deepEqual([chunk.res.status, chunk.req.dataHandler, h.store.openForTicket(ticket)], [400, null, 0]);
});
test('refused requests are counted and logged once per minute by sweep', () => {
    const h = makeHarness();
    for (let i = 0; i < 100; i += 1) assert.equal(call(h, 'GET', `/unknown-${i}`).res.status, 404);
    assert.equal(h.logs.length, 0);
    h.handler.sweep();
    assert.deepEqual(h.logs, [['rongroi http: refused 100 requests']]);
    h.handler.sweep();
    assert.equal(h.logs.length, 1);
});
