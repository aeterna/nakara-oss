// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

// Staff case screens, pure part: the visual-hash grouping, the strings deny list, findings order and
// the rule that every string reaches the DOM through setText.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const caseScreen = require('../web/ui/case.js');
const casesScreen = require('../web/ui/cases.js');
const caseStrings = require('../web/ui/strings/case.js');

const HASH = 'a1b2c3d4e5f60718';
const DENY = ['score', 'verdict', 'verified', 'clean', 'risk', 'ban', 'color'];

function fixture() {
    return {
        fixedLineKey: 'rongroi.case.fixedLine',
        facts: {
            openedBy: 'staff:42',
            openedAt: 1000,
            ticketState: 'consumed',
            receivedAt: 2000,
            uploaderAddress: '198.51.100.7:30120',
            connectAddress: '203.0.113.55',
        },
        selfAsserted: {
            official_build: true,
            producer: { name: 'rongroi-connect', version: '0.1.0' },
            rongroi_version: '0.14.0',
            issued_at: '2026-10-31T14:30:00Z',
            expires_at: '2026-10-31T14:35:00Z',
        },
        policy: {
            profile: 'posture',
            collectors: ['posture', 'net_config', 'pca'],
            elevation: true,
            serverName: 'Example City',
        },
        findings: [
            { rule_id: 'rule-1', collector: 'posture', strength: 'posture', state: 'found' },
            { rule_id: 'rule-2', collector: 'net_config', strength: 'posture', state: 'not_found' },
            { rule_id: 'rule-3', collector: 'pca', strength: 'posture', state: 'unmeasured', reason: 'pca_missing' },
        ],
        visualHash: { recorded: HASH, recomputed: HASH, equal: true },
        state: 'received',
        origin: 'connect',
    };
}

function stringsOf(value, list = []) {
    if (Array.isArray(value)) {
        for (const item of value) stringsOf(item, list);
        return list;
    }
    if (value !== null && typeof value === 'object') {
        for (const key of Object.keys(value)) stringsOf(value[key], list);
        return list;
    }
    list.push(String(value));
    return list;
}

test('the visual hash is grouped in fours for display and the value stays whole', () => {
    const model = caseScreen.viewModel(fixture());

    assert.equal(model.visualHash.recorded, HASH);
    assert.deepEqual(model.visualHash.groups, ['a1b2', 'c3d4', 'e5f6', '0718']);
    assert.equal(model.visualHash.grouped, 'a1b2\u2009c3d4\u2009e5f6\u20090718');
    assert.equal(model.visualHash.equal, true);
});

test('the panel case envelope is unwrapped to the case view', () => {
    const view = fixture();
    const model = caseScreen.viewModel({ screen: 'case', case: view });

    assert.equal(model.state, view.state);
    assert.equal(model.visualHash.grouped, 'a1b2\u2009c3d4\u2009e5f6\u20090718');
    assert.deepEqual(model.findings, view.findings);
});

test('a missing visual hash stays unknown and is never guessed', () => {
    const model = caseScreen.viewModel({
        ...fixture(),
        visualHash: { recorded: null, recomputed: HASH, equal: null },
    });

    assert.equal(model.visualHash.recorded, null);
    assert.equal(model.visualHash.equal, null);
    assert.deepEqual(model.visualHash.groups, []);
    assert.equal(model.visualHash.grouped, '');
});

test('the camel-case case view and a snake-case visual_hash are both read', () => {
    const model = caseScreen.viewModel({
        ...fixture(),
        visualHash: undefined,
        visual_hash: { recorded: HASH, recomputed: HASH, equal: true },
    });

    assert.equal(model.visualHash.grouped, 'a1b2\u2009c3d4\u2009e5f6\u20090718');
});

test('findings keep the order the report declared', () => {
    const findings = [
        { rule_id: 'rule-z', collector: 'pca', strength: 'posture', state: 'unmeasured' },
        { rule_id: 'rule-a', collector: 'posture', strength: 'posture', state: 'found' },
        { rule_id: 'rule-m', collector: 'net_config', strength: 'posture', state: 'not_found' },
    ];
    const model = caseScreen.viewModel({ ...fixture(), findings });

    assert.deepEqual(model.findings.map((row) => row.rule_id), ['rule-z', 'rule-a', 'rule-m']);
    assert.deepEqual(model.findings.map((row) => row.state), ['unmeasured', 'found', 'not_found']);
});

test('the case list keeps the order the server sent', () => {
    const model = casesScreen.viewModel({
        screen: 'list',
        cases: [
            { caseId: 'case-b', state: 'received' },
            { caseId: 'case-a', state: 'opened' },
        ],
    });

    assert.deepEqual(model.cases.map((row) => row.caseId), ['case-b', 'case-a']);
});

test('case strings never contain a word from the deny list', () => {
    for (const [lang, group] of Object.entries(caseStrings)) {
        const text = stringsOf(group).join(' ').toLowerCase();
        for (const word of DENY) {
            assert.equal(text.includes(word), false, `${lang} strings contain ${word}`);
        }
    }
});

test('the case strings cover the same keys in both languages', () => {
    assert.deepEqual(Object.keys(caseStrings.en).sort(), Object.keys(caseStrings.th).sort());
});

test('the screens write text only through setText and never through markup', () => {
    for (const name of ['case.js', 'cases.js']) {
        const source = fs.readFileSync(path.join(__dirname, '..', 'web', 'ui', name), 'utf8');
        assert.equal(/innerHTML|outerHTML/.test(source), false, `${name} writes markup`);
        assert.match(source, /function setText\(/, `${name} needs a setText helper`);

        const uses = source.match(/textContent/g) || [];
        assert.equal(uses.length, 1, `${name} must set text only inside setText`);
    }
});
