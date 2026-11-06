// nakara_rongroi — Rongroi Server Kit
// SPDX-License-Identifier: MIT
'use strict';

// Settings and policy screen view models: field order, safe defaults, collector selection and the
// reason-code table. Every reason below is one server/js/settings.js or server/js/panel.js can return.
const test = require('node:test');
const assert = require('node:assert/strict');
const settings = require('../web/ui/settings.js');
const policy = require('../web/ui/policy.js');
const settingsStrings = require('../web/ui/strings/settings.js');
const policyStrings = require('../web/ui/strings/policy.js');

const SETTINGS_FIELDS = ['publicOrigin', 'retentionDays', 'backendOverride', 'uploadPageEnabled'];
const POLICY_FIELDS = ['profile', 'required_collectors', 'require_elevation', 'serverName', 'policy_hash'];
const REASONS = [
    // server/js/settings.js normalize() and canOpenCase().
    'invalid_policy', 'invalid_public_origin', 'invalid_retention_days', 'invalid_backend_override',
    'invalid_upload_page_enabled', 'invalid_server_name', 'invalid_ttl_ms', 'unknown_setting',
    'public_origin_missing', 'server_name_missing',
    // server/js/panel.js refuse() and the defaults it forwards.
    'invalid_case_id', 'case_not_found', 'invalid_target', 'player_not_found', 'settings_unavailable',
    'case_not_opened', 'invalid_settings', 'delete_failed', 'invalid_identifier', 'key_rotation_failed',
];

function field(model, name) {
    return model.fields.find((entry) => entry.name === name);
}

test('settings view model keeps the field order and falls back safely', () => {
    const model = settings.viewModel({
        publicOrigin: 'https://server.example:30120',
        retentionDays: 45,
        backendOverride: 'file',
        uploadPageEnabled: true,
        confirmRotation: true,
        reason: 'invalid_ttl_ms',
    });
    assert.deepEqual(model.fields.map((entry) => entry.name), SETTINGS_FIELDS);
    assert.equal(field(model, 'publicOrigin').value, 'https://server.example:30120');
    assert.equal(field(model, 'retentionDays').value, 45);
    assert.equal(field(model, 'backendOverride').value, 'file');
    assert.deepEqual(field(model, 'backendOverride').options, ['auto', 'kvp', 'file']);
    assert.equal(field(model, 'uploadPageEnabled').value, true);
    assert.equal(model.rotation.confirming, true);
    assert.equal(model.reason, 'invalid_ttl_ms');

    const empty = settings.viewModel({});
    assert.equal(field(empty, 'publicOrigin').value, '');
    assert.equal(field(empty, 'retentionDays').value, 30);
    assert.equal(field(empty, 'retentionDays').min, 1);
    assert.equal(field(empty, 'backendOverride').value, 'auto');
    assert.equal(field(empty, 'uploadPageEnabled').value, false);
    assert.equal(empty.rotation.confirming, false);

    const bad = settings.viewModel({ retentionDays: 'many', backendOverride: 'sqlite', uploadPageEnabled: 'yes' });
    assert.equal(field(bad, 'retentionDays').value, 30);
    assert.equal(field(bad, 'backendOverride').value, 'auto');
    assert.equal(field(bad, 'uploadPageEnabled').value, false);
    const wrapped = settings.viewModel({ settings: { retentionDays: 12, corrupt: ['serverName'] } });
    assert.equal(field(wrapped, 'retentionDays').value, 12);
    assert.deepEqual(wrapped.corrupt, ['serverName']);
});

test('policy view model keeps the field order, selection and grouped hash', () => {
    const model = policy.viewModel({
        policy: { profile: 'custom', required_collectors: ['posture', 'net_config'], require_elevation: true },
        serverName: 'Example City',
        policy_hash: '94b51d336f083fe5',
    });
    assert.deepEqual(model.fields.map((entry) => entry.name), POLICY_FIELDS);
    assert.equal(field(model, 'profile').value, 'custom');
    assert.deepEqual(field(model, 'profile').options, ['posture', 'standard', 'custom']);
    assert.deepEqual(field(model, 'required_collectors').value, ['posture', 'net_config']);
    assert.equal(field(model, 'require_elevation').value, true);
    assert.equal(field(model, 'serverName').value, 'Example City');
    assert.equal(field(model, 'policy_hash').value, '94b51d336f083fe5');
    assert.equal(model.groupedHash, '94b5\u20091d33\u20096f08\u20093fe5');
    assert.deepEqual(
        model.collectors.filter((entry) => entry.selected).map((entry) => entry.id).sort(),
        ['net_config', 'posture'],
    );
    assert.equal(model.collectors.every((entry) => entry.editable), true);

    const posture = policy.viewModel({ policy: { profile: 'posture' } });
    assert.deepEqual(field(posture, 'required_collectors').value, [
        'posture', 'os_image', 'install_marker', 'defender_exclusion', 'net_config', 'driver_service',
    ]);
    assert.equal(posture.collectors.every((entry) => entry.editable), false);
    const standard = policy.viewModel({ policy: { profile: 'standard' } });
    assert.equal(standard.collectors.filter((entry) => entry.selected).length, 20);

    for (const data of [undefined, {}, { policy: null }, { policy: 'posture' }]) {
        const fallback = policy.viewModel(data);
        assert.equal(field(fallback, 'profile').value, 'posture');
        assert.equal(field(fallback, 'policy_hash').value, '');
        assert.equal(fallback.groupedHash, '');
    }
    assert.equal(policy.viewModel({ policyHash: '0123456789abcdef' }).policyHash, '0123456789abcdef');
});

test('the reason tables cover every code the controller can return', () => {
    for (const [name, table] of [['settings', settingsStrings], ['policy', policyStrings]]) {
        for (const lang of ['en', 'th']) {
            assert.deepEqual(Object.keys(table[lang].reasons).sort(), [...REASONS].sort(), `${name}.${lang}`);
            const texts = Object.values(table[lang].reasons);
            assert.ok(texts.every((text) => typeof text === 'string' && text.length > 0), `${name}.${lang}`);
        }
    }
});
