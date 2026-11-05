'use strict';

// HTTP rate-limit tests: fixed 60 s windows on the hand-advanced clock. The harness mirrors
// spec/http.test.js and spec/http-chunk.test.js, with a source address per request.
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { sealEnvelope } = require('../server/js/envelope.js');
const { TicketStore } = require('../server/js/tickets.js');
const { createHandler } = require('../server/js/http.js');
const kit = require('../test-vectors/envelope-v1.json').kit;
const POLICY = { collectors: ['a'], version: 2 };
const SLICE = 4096;
const UNKNOWN = 'e'.repeat(32);

function makeHarness() {
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
    const reports = [];
    const handler = createHandler({
        store, kit, now: () => ms,
        onReport: (event) => reports.push(event),
        log: () => {},
    });
    return { store, handler, reports, advance: (delta) => { ms += delta; } };
}

function issue(h, changes = {}) {
    return h.store.issue({ caseId: 'case-1', policy: POLICY, ...changes });
}

function call(h, method, path, headers, body, address) {
    const req = {
        method, path, headers: headers || {}, address, dataHandler: null,
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

function postReport(h, ticket, body, extra = {}, address) {
    const headers = {
        'x-rongroi-upload-id': ticket,
        'x-rongroi-report-sha256': sha(body),
        'content-length': String(Buffer.byteLength(body)),
        ...extra,
    };
    return call(h, 'POST', '/report', headers, body, address);
}

function postUnknownReport(h, address) {
    const headers = {
        'x-rongroi-upload-id': UNKNOWN,
        'x-rongroi-report-sha256': 'a'.repeat(64),
        'content-length': '0',
    };
    return call(h, 'POST', '/report', headers, '', address);
}

function chunkHeaders(ticket, reportSha, chunk, index, total) {
    return {
        'x-rongroi-upload-id': ticket, 'x-rongroi-report-sha256': reportSha,
        'x-rongroi-chunk-sha256': sha(chunk), 'x-rongroi-chunk-index': String(index),
        'x-rongroi-chunk-total': String(total), 'content-length': String(Buffer.byteLength(chunk)),
    };
}

function postChunk(h, ticket, reportSha, chunk, index, total, address) {
    return call(h, 'POST', '/report/chunk', chunkHeaders(ticket, reportSha, chunk, index, total), chunk, address);
}

function postUnknownChunk(h, address) {
    return postChunk(h, UNKNOWN, 'a'.repeat(64), Buffer.from('x'), 0, 1, address);
}

function split(body, size = SLICE) {
    const bytes = Buffer.from(body);
    const slices = [];
    for (let i = 0; i < bytes.length; i += size) slices.push(bytes.subarray(i, i + size));
    return slices;
}

test('the 31st policy GET is 429, the window resets and sweep drops ended windows', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    const address = '1.2.3.4';
    for (let i = 0; i < 30; i += 1) {
        assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, address).res.status, 200);
    }
    const limited = call(h, 'GET', `/policy/${ticket}`, null, undefined, address);
    assert.equal(limited.res.status, 429);
    assert.equal(limited.res.headers['Retry-After'], '60');
    assert.deepEqual(limited.json(), { status: 429 });
    h.advance(60000);
    h.handler.sweep();
    for (let i = 0; i < 30; i += 1) {
        assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, address).res.status, 200);
    }
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, address).res.status, 429);
});

test('address keys share a count, strip one trailing port and keep IPv6 whole', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    for (let i = 0; i < 30; i += 1) {
        assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '1.2.3.4:50000').res.status, 200);
    }
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '1.2.3.4:50001').res.status, 429);
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '5.6.7.8').res.status, 200);

    for (let i = 0; i < 30; i += 1) {
        assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '2001:db8::1').res.status, 200);
    }
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '2001:db8::1').res.status, 429);
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '2001:db8::1:999').res.status, 200);
});

test('a bracketed IPv6 address shares one count across ports', () => {
    const h = makeHarness();
    const { ticket } = issue(h);
    for (let i = 0; i < 30; i += 1) {
        assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '[::1]:30120').res.status, 200);
    }
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '[::1]:30121').res.status, 429);
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, '[::2]:30120').res.status, 200);
});

test('an unknown ticket counts per address on report and chunk, and the 31st is 429', () => {
    const h = makeHarness();
    const reportAddress = '10.0.0.1';
    for (let i = 0; i < 30; i += 1) {
        const result = postUnknownReport(h, reportAddress);
        assert.equal(result.res.status, 404);
        assert.equal(result.req.dataHandler, null);
    }
    const reportLimited = postUnknownReport(h, reportAddress);
    assert.equal(reportLimited.res.status, 429);
    assert.equal(reportLimited.res.headers['Retry-After'], '60');

    const chunkAddress = '10.0.0.2';
    for (let i = 0; i < 30; i += 1) {
        const result = postUnknownChunk(h, chunkAddress);
        assert.equal(result.res.status, 404);
        assert.equal(result.req.dataHandler, null);
    }
    const chunkLimited = postUnknownChunk(h, chunkAddress);
    assert.equal(chunkLimited.res.status, 429);
    assert.equal(chunkLimited.res.headers['Retry-After'], '60');
});

test('a valid direct POST is not counted against the address', () => {
    const h = makeHarness();
    const address = '9.9.9.9';
    for (let i = 0; i < 30; i += 1) {
        const { ticket, nonce } = issue(h, { caseId: `case-${i}` });
        const body = envelope({ schema: 2, binding: { ticket, nonce } }, ticket);
        const result = postReport(h, ticket, body, {}, address);
        result.req.deliver();
        assert.equal(result.res.status, 200);
    }
    const { ticket } = issue(h, { caseId: 'policy' });
    for (let i = 0; i < 30; i += 1) {
        assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, address).res.status, 200);
    }
    assert.equal(call(h, 'GET', `/policy/${ticket}`, null, undefined, address).res.status, 429);
});

test('the 601st slice is 429 with the buffer kept and the upload finishes after the window', () => {
    const h = makeHarness();
    const { ticket, body } = sealed(h, { record: { note: 'x'.repeat(4000) } });
    const reportSha = sha(body);
    const slices = split(body);
    assert.equal(slices.length, 2);
    const address = '7.7.7.7';
    const first = postChunk(h, ticket, reportSha, slices[0], 0, 2, address);
    first.req.deliver();
    assert.equal(first.res.status, 200);
    for (let i = 0; i < 599; i += 1) {
        const retry = postChunk(h, ticket, reportSha, slices[0], 0, 2, address);
        assert.equal(retry.res.status, 200);
        assert.equal(retry.req.dataHandler, null);
    }
    const limited = postChunk(h, ticket, reportSha, slices[0], 0, 2, address);
    assert.equal(limited.res.status, 429);
    assert.equal(limited.res.headers['Retry-After'], '60');
    assert.equal(limited.req.dataHandler, null);
    assert.equal(h.store.openForTicket(ticket), 1);

    h.advance(60000);
    const last = postChunk(h, ticket, reportSha, slices[1], 1, 2, address);
    last.req.deliver();
    assert.equal(last.res.status, 200);
    assert.equal(h.reports.length, 1);
    assert.equal(h.store.stateOf(ticket), 'consumed');
});

test('report/chunk with no headers is 400', () => {
    const h = makeHarness();
    const result = call(h, 'POST', '/report/chunk');
    assert.equal(result.res.status, 400);
    assert.equal(result.req.dataHandler, null);
});
