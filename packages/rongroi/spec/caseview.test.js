'use strict';

// Staff case view model: facts, self-asserted fields, policy, findings and the visual-hash fact.
const test = require('node:test');
const assert = require('node:assert/strict');
const { visualHash } = require('../server/js/record.js');
const { caseList, caseView } = require('../server/js/caseview.js');

const DENY = ['score', 'verdict', 'verified', 'clean', 'risk', 'ban', 'color'];

const POLICY = {
    profile: 'posture',
    required_collectors: ['posture', 'net_config', 'pca'],
    require_elevation: true,
    server_name: 'Example City',
    policy_hash: '94b51d336f083fe5',
};

const CASE_FACTS = {
    caseId: 'case-1',
    ticket: '9f82c4e1b07a412891d604e38a291bf0',
    openedBy: 'staff:42',
    openedAt: 1000,
    state: 'opened',
    address: '198.51.100.7:30120',
    connectAddress: '203.0.113.55',
    policy: POLICY,
    expiresAt: 5000,
};

const REPORT = {
    kind: 'rongroi-saved-report',
    schema: 2,
    case_code: '7K9M-2X4P',
    rongroi_version: '0.14.0',
    official_build: true,
    producer: { name: 'rongroi-connect', version: '0.1.0', mode: 'single-shot' },
    binding: {
        server_origin: 'http://203.0.113.10:30130',
        ticket: '9f82c4e1b07a412891d604e38a291bf0',
        nonce: 'c4b82e91024a',
        issued_at: '2026-10-31T14:30:00Z',
        expires_at: '2026-10-31T14:35:00Z',
    },
    policy: POLICY,
    view: {
        generated_at: '2026-10-31T14:30:00Z',
        schema_version: 2,
        evidence: [
            { rule_id: 'rule-1', collector: 'posture', strength: 'posture', state: 'found', observations: [] },
            { rule_id: 'rule-2', collector: 'net_config', strength: 'posture', state: 'not_found', retention: '30 days' },
            { rule_id: 'rule-3', collector: 'pca', strength: 'posture', state: 'unmeasured', reason: 'pca_missing', expected: true },
        ],
    },
};

function hashed(report) {
    const copy = { ...report };
    delete copy.visual_hash;
    copy.visual_hash = visualHash(copy);
    return copy;
}

function keysOf(value, keys = []) {
    if (Array.isArray(value)) {
        for (const item of value) keysOf(item, keys);
        return keys;
    }
    if (value !== null && typeof value === 'object') {
        for (const key of Object.keys(value)) {
            keys.push(key);
            keysOf(value[key], keys);
        }
    }
    return keys;
}

function view(overrides = {}) {
    return caseView({
        caseFacts: CASE_FACTS,
        ticketState: 'consumed',
        report: { record: hashed(REPORT) },
        now: 3000,
        ...overrides,
    });
}

test('a declined case is state declined and carries no findings', () => {
    const fromCase = view({ caseFacts: { ...CASE_FACTS, state: 'declined', receivedAt: 2000 }, report: { record: hashed(REPORT) } });
    assert.equal(fromCase.state, 'declined');
    assert.deepEqual(fromCase.findings, []);
    assert.deepEqual(fromCase.visualHash, { recorded: null, recomputed: null, equal: null });

    const fromReport = view({ report: { declined: true } });
    assert.equal(fromReport.state, 'declined');
    assert.deepEqual(fromReport.findings, []);
});

test('a mismatching visual_hash gives equal:false and changes nothing else', () => {
    const matched = view();
    const mismatched = view({ report: { record: { ...hashed(REPORT), visual_hash: '0000000000000000' } } });

    assert.equal(matched.visualHash.equal, true);
    assert.equal(mismatched.visualHash.equal, false);
    assert.equal(mismatched.visualHash.recorded, '0000000000000000');
    assert.equal(mismatched.visualHash.recomputed, matched.visualHash.recomputed);

    for (const key of ['fixedLineKey', 'facts', 'selfAsserted', 'policy', 'findings', 'state', 'origin']) {
        assert.deepEqual(mismatched[key], matched[key], key);
    }
});

test('no output key names a score, verdict, colour or rank', () => {
    const built = view();
    for (const key of keysOf(built)) {
        assert.equal(DENY.includes(key.toLowerCase()), false, `caseView key ${key}`);
    }
    for (const key of keysOf(caseList([{ ...CASE_FACTS, state: 'received', receivedAt: 2000 }]))) {
        assert.equal(DENY.includes(key.toLowerCase()), false, `caseList key ${key}`);
    }
});

test('the case view has exactly the documented top-level keys', () => {
    assert.deepEqual(Object.keys(view()).sort(), [
        'facts',
        'findings',
        'fixedLineKey',
        'origin',
        'policy',
        'selfAsserted',
        'state',
        'visualHash',
    ]);
    assert.equal(view().fixedLineKey, 'rongroi.case.fixedLine');
});

test('no function reads a clock except the injected now', () => {
    const RealDate = globalThis.Date;
    let built;
    let opened;
    try {
        globalThis.Date = function Date() {
            throw new Error('the view read the system clock');
        };
        globalThis.Date.now = function now() {
            throw new Error('the view read the system clock');
        };
        built = caseView({
            caseFacts: { ...CASE_FACTS, expiresAt: 100 },
            ticketState: 'issued',
            report: null,
            now: 100,
        });
        opened = caseView({ caseFacts: CASE_FACTS, ticketState: 'issued', report: null, now: 3000 });
    } finally {
        globalThis.Date = RealDate;
    }
    assert.equal(built.state, 'expired');
    assert.equal(opened.state, 'opened');
});

test('known evidence states keep their rows and reasons', () => {
    assert.deepEqual(view().findings, [
        { rule_id: 'rule-1', collector: 'posture', strength: 'posture', state: 'found' },
        { rule_id: 'rule-2', collector: 'net_config', strength: 'posture', state: 'not_found' },
        { rule_id: 'rule-3', collector: 'pca', strength: 'posture', state: 'unmeasured', reason: 'pca_missing' },
    ]);
});

test('findings come only from record.view.evidence', () => {
    const built = view({
        report: {
            record: hashed({
                ...REPORT,
                evidence: [{ rule_id: 'top-level', collector: 'posture', strength: 'posture', state: 'found' }],
                view: { ...REPORT.view, evidence: [] },
            }),
        },
    });

    assert.deepEqual(built.findings, []);
});

test('an unknown evidence state is kept as unknown and not dropped', () => {
    const built = view({
        report: {
            record: hashed({
                ...REPORT,
                view: {
                    ...REPORT.view,
                    evidence: [
                        { rule_id: 'rule-future', collector: 'posture', strength: 'posture', state: 'future_state' },
                        { rule_id: 'rule-missing', collector: 'net_config', strength: 'posture' },
                    ],
                },
            }),
        },
    });

    assert.equal(built.findings.length, 2);
    assert.deepEqual(built.findings[0], {
        rule_id: 'rule-future',
        collector: 'posture',
        strength: 'posture',
        state: 'unknown',
    });
    assert.equal(built.findings[1].rule_id, 'rule-missing');
    assert.equal(built.findings[1].state, 'unknown');
});

test('strings in findings are returned untouched', () => {
    const collector = '  <b>keep & this</b>  ';
    const ruleId = 'rule <not escaped>';
    const reason = 'reason & <text>';
    const built = view({
        report: {
            record: hashed({
                ...REPORT,
                view: {
                    ...REPORT.view,
                    evidence: [{ rule_id: ruleId, collector, strength: 'posture', state: 'unmeasured', reason }],
                },
            }),
        },
    });

    assert.equal(built.findings[0].collector, collector);
    assert.equal(built.findings[0].rule_id, ruleId);
    assert.equal(built.findings[0].reason, reason);
    assert.deepEqual(built.findings[0], {
        rule_id: ruleId,
        collector,
        strength: 'posture',
        state: 'unmeasured',
        reason,
    });
});

test('facts keep the uploader and connect addresses separate', () => {
    assert.deepEqual(view().facts, {
        openedBy: 'staff:42',
        openedAt: 1000,
        ticketState: 'consumed',
        receivedAt: null,
        uploaderAddress: '198.51.100.7:30120',
        connectAddress: '203.0.113.55',
    });
    assert.equal(view({ caseFacts: { ...CASE_FACTS, uploaderAddress: '192.0.2.99' } }).facts.uploaderAddress,
        CASE_FACTS.address);
    assert.notEqual(view().facts.uploaderAddress, view().facts.connectAddress);
});

test('policy is mapped to profile, collectors, elevation and server name', () => {
    assert.deepEqual(view().policy, {
        profile: 'posture',
        collectors: ['posture', 'net_config', 'pca'],
        elevation: true,
        serverName: 'Example City',
    });
});

test('selfAsserted carries exactly the five report-says fields', () => {
    assert.deepEqual(view().selfAsserted, {
        official_build: true,
        producer: REPORT.producer,
        rongroi_version: '0.14.0',
        issued_at: '2026-10-31T14:30:00Z',
        expires_at: '2026-10-31T14:35:00Z',
    });

    const withoutBinding = { ...REPORT, issued_at: 'top-level', expires_at: 'top-level' };
    delete withoutBinding.binding;
    assert.deepEqual(view({ report: { record: hashed(withoutBinding) } }).selfAsserted, {
        official_build: true,
        producer: REPORT.producer,
        rongroi_version: '0.14.0',
        issued_at: null,
        expires_at: null,
    });
});

test('origin comes only from caseFacts.origin', () => {
    assert.equal(view().origin, 'connect');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, origin: 'saved_file' } }).origin, 'saved_file');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, origin: 'saved-file' } }).origin, 'connect');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, origin: 'upload' } }).origin, 'connect');
    assert.equal(view({ report: { record: hashed({ ...REPORT, origin: 'saved_file' }) } }).origin, 'connect');
    assert.equal(view({ report: { record: hashed({ ...REPORT, source: 'upload' }) } }).origin, 'connect');
});

test('state is opened, received or expired from facts and the injected clock', () => {
    assert.equal(view({ caseFacts: CASE_FACTS, report: null }).state, 'opened');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, state: 'received', receivedAt: 2000 } }).state, 'received');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, state: 'opened', receivedAt: 2000 }, report: null }).state, 'opened');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, ticketState: 'expired' }, ticketState: undefined, report: null }).state, 'opened');
    assert.equal(view({ ticketState: 'expired', report: null }).state, 'expired');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, expiresAt: 3000 }, report: null, now: 3000 }).state, 'expired');
    assert.equal(view({ caseFacts: { ...CASE_FACTS, expiresAt: 3001 }, report: null, now: 3000 }).state, 'opened');
});

test('caseList makes one plain row per entry and keeps its order', () => {
    const rows = caseList([
        { caseId: 'case-a', openedBy: 'staff', openedAt: 10, state: 'received', receivedAt: 20, origin: 'connect' },
        { caseId: 'case-b', openedBy: 'staff', openedAt: 30, state: 'declined', receivedAt: null, origin: 'saved_file' },
        { caseId: 'case-c', openedBy: 'staff', openedAt: 40, state: 'opened', receivedAt: null, origin: 'connect' },
        { caseId: 'case-d', openedBy: 'staff', openedAt: 50, state: 'expired', receivedAt: null, origin: 'connect' },
    ]);

    assert.deepEqual(rows.map((row) => row.caseId), ['case-a', 'case-b', 'case-c', 'case-d']);
    assert.deepEqual(rows[0], {
        caseId: 'case-a',
        openedBy: 'staff',
        openedAt: 10,
        state: 'received',
        receivedAt: 20,
        origin: 'connect',
    });
    assert.equal(rows[1].state, 'declined');
    assert.equal(rows[2].state, 'opened');
    assert.equal(rows[3].state, 'expired');
    assert.equal(rows[0].origin, 'connect');
    assert.equal(rows[1].origin, 'saved_file');
});

test('caseList does not infer state or received time from removed aliases', () => {
    assert.deepEqual(caseList([{ caseId: 'case-a', openedBy: 'staff', openedAt: 10, consumedAt: 20 }]), [{
        caseId: 'case-a',
        openedBy: 'staff',
        openedAt: 10,
        state: null,
        receivedAt: null,
        origin: null,
    }]);
});

test('caseview exports exactly the two view helpers', () => {
    const mod = require('../server/js/caseview.js');
    assert.deepEqual(Object.keys(mod).sort(), ['caseList', 'caseView']);
});
