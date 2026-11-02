'use strict';

// HTTP handler tests: direct POST report and GET policy, on a hand-advanced clock. Envelopes are sealed
// with the Kit test key from test-vectors/envelope-v1.json.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { sealEnvelope } = require('../server/js/envelope.js');
const { policyHash } = require('../server/js/pairing.js');
const { TicketStore } = require('../server/js/tickets.js');
const { createHandler } = require('../server/js/http.js');
const vectors = require('../test-vectors/envelope-v1.json');

const kit = vectors.kit;
const TTL = 300000;
const POLICY = { collectors: ['a'], version: 2 };

function makeHarness(options = {}) {
    let ms = 1000000;
    let next = 0;
    const store = new TicketStore({
        now: () => ms,
        randomBytes: (n) => {
            const bytes = [];
            for (let i = 0; i < n; i += 1) bytes.push(next = (next + 1) & 0xff);
            return Buffer.from(bytes);
        },
    });
    const logs = [];
    const reports = [];
    const onReport = options.onReport || ((event) => reports.push(event));
    const handler = createHandler({ store, kit, now: () => ms, onReport, log: (...a) => logs.push(a) });
    return { store, handler, logs, reports, advance: (delta) => { ms += delta; } };
}

function issue(harness, changes = {}) {
    return harness.store.issue({ caseId: 'case-1', policy: POLICY, ...changes });
}

function call(harness, method, path, headers, body) {
    const req = {
        method,
        path,
        headers: headers || {},
        dataHandler: null,
        setDataHandler(cb) { this.dataHandler = cb; },
        deliver() {
            assert.equal(typeof this.dataHandler, 'function', 'handler must request the body');
            this.dataHandler(body);
        },
    };
    const res = {
        status: null,
        headers: null,
        body: null,
        writeHead(status, headers) { this.status = status; this.headers = headers || {}; },
        send(body) { this.body = body; },
    };
    harness.handler(req, res);
    return { req, res, json: () => JSON.parse(res.body) };
}

function sha(text) {
    return crypto.createHash('sha256').update(text).digest('hex');
}

function envelope(record, ticket) {
    return sealEnvelope(JSON.stringify(record), kit.publicKey, ticket);
}

function postReport(harness, ticket, body, extra = {}) {
    const headers = {
        'x-rongroi-upload-id': ticket,
        'x-rongroi-report-sha256': sha(body),
        'content-length': String(Buffer.byteLength(body)),
        ...extra,
    };
    return call(harness, 'POST', '/report', headers, body);
}

test('GET policy returns the issued policy with its policy_hash', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    const { res, json } = call(h, 'GET', `/policy/${ticket}`);
    assert.equal(res.status, 200);
    assert.equal(res.headers['Content-Type'], 'application/json');
    assert.deepEqual(json(), { ...POLICY, policy_hash: policyHash(POLICY) });
});

test('GET policy is 400, 404 or 410 for a bad, unknown or expired ticket', () => {
    const h = makeHarness();
    assert.equal(call(h, 'GET', '/policy/nothex').res.status, 400);
    assert.equal(call(h, 'GET', `/policy/${'e'.repeat(32)}`).res.status, 404);
    const { ticket } = issue(h);
    h.advance(TTL);
    assert.equal(call(h, 'GET', `/policy/${ticket}`).res.status, 410);
});

test('POST report accepts a sealed report and a declined answer with the case facts', () => {
    const h = makeHarness();
    const first = issue(h, { caseId: 'case-42' });
    const record = { schema: 2, binding: { ticket: first.ticket, nonce: first.nonce }, note: 'ok' };
    const reportBody = envelope(record, first.ticket);
    const report = postReport(h, first.ticket, reportBody);
    assert.equal(h.reports.length, 0);
    report.req.deliver();
    assert.equal(report.res.status, 200);
    assert.equal(report.res.headers['Content-Type'], 'application/json');
    assert.deepEqual(report.json(), { status: 200 });
    assert.deepEqual(h.reports, [{ caseId: 'case-42', ticket: first.ticket, reportSha256: sha(reportBody), receivedAt: 1000000, record }]);
    assert.equal(h.store.stateOf(first.ticket), 'consumed');
    const second = issue(h, { caseId: 'case-2' });
    const declinedBody = envelope({ scan: 'declined', binding: { ticket: second.ticket, nonce: second.nonce } }, second.ticket);
    const declined = postReport(h, second.ticket, declinedBody);
    declined.req.deliver();
    assert.equal(declined.res.status, 200);
    assert.deepEqual(h.reports[1], { caseId: 'case-2', ticket: second.ticket, reportSha256: sha(declinedBody), receivedAt: 1000000, declined: true });
});

test('a repeat is 200 and a different envelope is 409, both without reading the body', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const first = postReport(h, ticket, body);
    first.req.deliver();
    assert.equal(first.res.status, 200);
    const repeat = postReport(h, ticket, body);
    assert.equal(repeat.res.status, 200);
    assert.equal(repeat.req.dataHandler, null);
    const other = envelope({ schema: 2, binding: { ticket, nonce }, note: 'other' }, ticket);
    const different = postReport(h, ticket, other);
    assert.equal(different.res.status, 409);
    assert.equal(different.req.dataHandler, null);
});

test('bad sha, binding, nonce, schema and envelope failures never consume the ticket', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const other = 'e'.repeat(32);
    const wrongNonce = (nonce[0] === '0' ? '1' : '0') + nonce.slice(1);
    const good = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const cases = [
        ['sha mismatch', good, { 'x-rongroi-report-sha256': 'a'.repeat(64) }, 422],
        ['wrong nonce', envelope({ schema: 2, binding: { ticket, nonce: wrongNonce } }, ticket), {}, 422],
        ['wrong binding ticket', envelope({ schema: 2, binding: { ticket: other, nonce } }, ticket), {}, 422],
        ['missing binding on a declined answer', envelope({ scan: 'declined' }, ticket), {}, 422],
        ['schema 1 report', envelope({ schema: 1, binding: { ticket, nonce } }, ticket), {}, 422],
        ['not authentic', envelope({ schema: 2, binding: { ticket, nonce } }, other), {}, 422],
        ['malformed envelope', '{"not":"an envelope"}', {}, 400],
    ];
    for (const [name, body, extra, status] of cases) {
        const { req, res } = postReport(h, ticket, body, extra);
        req.deliver();
        assert.equal(res.status, status, name);
        assert.equal(h.store.stateOf(ticket), 'issued', name);
    }
    const accepted = postReport(h, ticket, good);
    accepted.req.deliver();
    assert.equal(accepted.res.status, 200); // every failed upload left the ticket usable
});

test('size, headers and expiry are refused before the body is read', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const tooLong = postReport(h, ticket, body, { 'content-length': '7169' });
    assert.equal(tooLong.res.status, 413);
    assert.equal(tooLong.req.dataHandler, null);
    assert.equal(h.store.stateOf(ticket), 'issued');
    for (const headers of [
        { 'x-rongroi-report-sha256': 'a'.repeat(64) },
        { 'x-rongroi-upload-id': ticket },
        { 'x-rongroi-upload-id': 'nothex', 'x-rongroi-report-sha256': 'a'.repeat(64) },
    ]) {
        const bad = call(h, 'POST', '/report', headers, body);
        assert.equal(bad.res.status, 400);
        assert.equal(bad.req.dataHandler, null);
    }
    const oversize = postReport(h, ticket, 'x'.repeat(7169), { 'content-length': undefined });
    oversize.req.deliver();
    assert.equal(oversize.res.status, 413);
    assert.equal(h.store.stateOf(ticket), 'issued');
    const expired = issue(h, { caseId: 'case-2' });
    h.advance(TTL);
    const binding = { ticket: expired.ticket, nonce: expired.nonce };
    const late = postReport(h, expired.ticket, envelope({ schema: 2, binding }, expired.ticket));
    assert.equal(late.res.status, 410);
    assert.equal(late.req.dataHandler, null);
});

test('two concurrent uploads of one envelope report once', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const first = postReport(h, ticket, body);
    const second = postReport(h, ticket, body);
    assert.equal(first.res.status, null);
    assert.equal(second.res.status, null);
    assert.equal(typeof first.req.dataHandler, 'function');
    assert.equal(typeof second.req.dataHandler, 'function');
    first.req.deliver();
    second.req.deliver();
    assert.equal(first.res.status, 200);
    assert.equal(second.res.status, 200);
    assert.equal(h.reports.length, 1);
    assert.equal(h.store.stateOf(ticket), 'consumed');
});

test('a third open upload on one ticket is 429 with Retry-After: 5', () => {
    const h = makeHarness();
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const first = postReport(h, ticket, body);
    const second = postReport(h, ticket, body);
    for (const open of [first, second]) {
        assert.equal(open.res.status, null);
        assert.equal(typeof open.req.dataHandler, 'function');
    }
    const third = postReport(h, ticket, body);
    assert.equal(third.res.status, 429);
    assert.equal(third.res.headers['Retry-After'], '5');
    assert.equal(third.res.headers['Content-Type'], 'application/json');
    assert.equal(third.req.dataHandler, null);
});

test('a wrong method on a known path is 405 and an unknown path is 404', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    assert.equal(call(h, 'GET', '/report').res.status, 405);
    assert.equal(call(h, 'POST', `/policy/${ticket}`).res.status, 405);
    assert.equal(call(h, 'POST', '/report/other').res.status, 404);
    assert.equal(call(h, 'GET', '/upload').res.status, 404);
});

test('an onReport exception still answers 200 and logs a fixed string', () => {
    const h = makeHarness({ onReport: () => { throw new Error('boom'); } });
    const { ticket, nonce } = issue(h);
    const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
    const { req, res, json } = postReport(h, ticket, body);
    req.deliver();
    assert.equal(res.status, 200);
    assert.deepEqual(json(), { status: 200 });
    assert.equal(h.store.stateOf(ticket), 'consumed');
    assert.match(JSON.stringify(h.logs), /onReport failed/);
});

test('the log never sees the body or an unvalidated path', () => {
    const h = makeHarness();
    const bodySentinel = 'SECRET-BODY-SENTINEL';
    const pathSentinel = '/policy/SECRET-PATH-SENTINEL';
    call(h, 'GET', pathSentinel);
    const { ticket } = issue(h);
    call(h, 'POST', '/report', {
        'x-rongroi-upload-id': ticket,
        'x-rongroi-report-sha256': 'SECRET-HEADER-SENTINEL',
    }, bodySentinel);
    const { ticket: second } = issue(h, { caseId: 'case-2' });
    const malformed = postReport(h, second, bodySentinel);
    malformed.req.deliver();
    const logged = JSON.stringify(h.logs);
    assert.equal(logged.includes(bodySentinel), false);
    assert.equal(logged.includes(pathSentinel), false);
    assert.equal(logged.includes('SECRET-HEADER-SENTINEL'), false);
});
