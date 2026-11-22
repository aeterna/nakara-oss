// @aeterna_game/rongroi-envelope
// SPDX-License-Identifier: MIT
'use strict';

// The SDK ships the Server Kit's envelope module unchanged, so both always agree. These tests check the copy is
// identical and that it reproduces both shared vectors.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const sdk = require('../index.js');

const here = (...p) => path.join(__dirname, '..', ...p);
const kit = (...p) => path.join(__dirname, '..', '..', '..', 'packages', 'rongroi', ...p);

test('index.js is byte-identical to the Server Kit envelope module', () => {
    assert.equal(fs.readFileSync(here('index.js'), 'utf8'), fs.readFileSync(kit('server', 'js', 'envelope.js'), 'utf8'));
});

test('the bundled vectors are byte-identical to the Server Kit vectors', () => {
    for (const name of ['envelope-v1.json', 'envelope-v2.json']) {
        assert.equal(fs.readFileSync(here('test-vectors', name), 'utf8'), fs.readFileSync(kit('test-vectors', name), 'utf8'), name);
    }
});

test('v1 vector round-trips', () => {
    const v = require('../test-vectors/envelope-v1.json');
    assert.equal(sdk.sealEnvelope(v.plaintext, v.kit.publicKey, v.ticket, { ephemeralPrivate: v.ephemeral.privateKey, iv: v.iv }),
        JSON.stringify(v.envelope));
    assert.equal(sdk.openEnvelope(JSON.stringify(v.envelope), v.kit.privateKey, v.kit.publicKey, v.ticket), v.plaintext);
});

test('v2 vector round-trips with its binding', () => {
    const v = require('../test-vectors/envelope-v2.json');
    assert.equal(sdk.sealEnvelopeV2(v.plaintext, v.kit.publicKey, v.binding, { ephemeralPrivate: v.ephemeral.privateKey, iv: v.iv }),
        JSON.stringify(v.envelope));
    assert.equal(sdk.openEnvelope(JSON.stringify(v.envelope), v.kit.privateKey, v.kit.publicKey, v.binding.ticket,
        { accept: 2, binding: v.binding }), v.plaintext);
});
