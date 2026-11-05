'use strict';

// Settings storage (ADR 0001, section 11): defaults, validation, corrupt reads, and the policy a ticket
// carries. The adapter is a plain in-memory map, so no test needs FXServer or a real KVP store.
const test = require('node:test');
const assert = require('node:assert/strict');
const {
    createSettings,
    buildPolicy,
    canOpenCase,
    POSTURE_COLLECTORS,
    STANDARD_COLLECTORS,
} = require('../server/js/settings.js');
const { policyHash } = require('../server/js/pairing.js');

const POSTURE = [
    'posture',
    'os_image',
    'install_marker',
    'defender_exclusion',
    'net_config',
    'driver_service',
];

const STANDARD = [
    'antivirus_product',
    'autostart',
    'bam',
    'defender_exclusion',
    'driver_service',
    'event_fields',
    'evtx',
    'fivem_dir',
    'hid_device',
    'install_marker',
    'net_config',
    'os_image',
    'pca',
    'pci_device',
    'posture',
    'prefetch',
    'process',
    'userassist',
    'usn',
    'windows_start',
];

function memoryKvp(initial) {
    const store = new Map(initial ? Object.entries(initial) : []);
    const writes = [];
    return {
        get(key) {
            return store.get(key);
        },
        set(key, value) {
            writes.push([key, value]);
            store.set(key, value);
        },
        store,
        writes,
    };
}

test('every setting reads its documented default', () => {
    const settings = createSettings(memoryKvp());
    assert.deepEqual(settings.get(), {
        publicOrigin: null,
        retentionDays: 30,
        backendOverride: 'auto',
        uploadPageEnabled: false,
        serverName: null,
        policy: { profile: 'posture', require_elevation: false },
        ttlMs: 300000,
        corrupt: [],
    });
});

test('a valid write of each setting is stored and read back', () => {
    const kvp = memoryKvp();
    const settings = createSettings(kvp);
    const values = {
        publicOrigin: 'https://server.example:30120',
        retentionDays: 45,
        backendOverride: 'file',
        uploadPageEnabled: true,
        serverName: 'Nakara City',
        policy: {
            profile: 'custom',
            required_collectors: ['posture', 'os_image'],
            require_elevation: true,
        },
        ttlMs: 60000,
    };
    for (const [name, value] of Object.entries(values)) {
        assert.deepEqual(settings.set(name, value), { ok: true }, name);
    }
    const stored = settings.get();
    for (const [name, value] of Object.entries(values)) {
        assert.deepEqual(stored[name], value, name);
    }
    assert.deepEqual(stored.corrupt, []);
    assert.equal(kvp.store.get('rongroi:settings:retentionDays'), '45');
});

test('invalid writes are refused with a reason and write nothing', () => {
    const kvp = memoryKvp();
    const settings = createSettings(kvp);
    const bad = [
        ['publicOrigin', 'https://server.example/path', 'invalid_public_origin'],
        ['publicOrigin', 'https://user@server.example', 'invalid_public_origin'],
        ['retentionDays', '30', 'invalid_retention_days'],
        ['backendOverride', 'sqlite', 'invalid_backend_override'],
        ['uploadPageEnabled', 'yes', 'invalid_upload_page_enabled'],
        ['serverName', '', 'invalid_server_name'],
        ['serverName', 'x'.repeat(129), 'invalid_server_name'],
        ['serverName', 'bad\nname', 'invalid_server_name'],
        ['policy', 'posture', 'invalid_policy'],
        ['ttlMs', 59999, 'invalid_ttl_ms'],
        ['ttlMs', 3600001, 'invalid_ttl_ms'],
        ['ttlMs', 1.5, 'invalid_ttl_ms'],
        ['noSuchSetting', true, 'unknown_setting'],
    ];
    for (const [name, value, reason] of bad) {
        assert.deepEqual(settings.set(name, value), { ok: false, reason }, `${name}=${String(value)}`);
    }
    assert.equal(kvp.writes.length, 0);
});

test('retentionDays is clamped to 1..365', () => {
    const settings = createSettings(memoryKvp());
    settings.set('retentionDays', 999);
    assert.equal(settings.get().retentionDays, 365);
    settings.set('retentionDays', 0);
    assert.equal(settings.get().retentionDays, 1);
    settings.set('retentionDays', 12.9);
    assert.equal(settings.get().retentionDays, 12);
});

test('a corrupt stored value falls back to its default and is listed in corrupt', () => {
    const kvp = memoryKvp({
        'rongroi:settings:publicOrigin': 'not a url',
        'rongroi:settings:retentionDays': 'soon',
        'rongroi:settings:backendOverride': 'tape',
        'rongroi:settings:uploadPageEnabled': 'yes',
        'rongroi:settings:serverName': '',
        'rongroi:settings:policy': '{',
        'rongroi:settings:ttlMs': '0',
    });
    const settings = createSettings(kvp);
    const stored = settings.get();
    assert.equal(stored.publicOrigin, null);
    assert.equal(stored.retentionDays, 30);
    assert.equal(stored.backendOverride, 'auto');
    assert.equal(stored.uploadPageEnabled, false);
    assert.equal(stored.serverName, null);
    assert.deepEqual(stored.policy, { profile: 'posture', require_elevation: false });
    assert.equal(stored.ttlMs, 300000);
    assert.deepEqual(stored.corrupt, [
        'publicOrigin',
        'retentionDays',
        'backendOverride',
        'uploadPageEnabled',
        'serverName',
        'policy',
        'ttlMs',
    ]);

    // Writing a valid value repairs that one key and clears it from corrupt.
    settings.set('serverName', 'Repaired');
    assert.deepEqual(settings.get().corrupt, [
        'publicOrigin',
        'retentionDays',
        'backendOverride',
        'uploadPageEnabled',
        'policy',
        'ttlMs',
    ]);
});

test('a write of an unchanged value calls kvp.set zero times', () => {
    const kvp = memoryKvp();
    const settings = createSettings(kvp);
    settings.set('serverName', 'Nakara City');
    assert.equal(kvp.writes.length, 1);
    settings.set('serverName', 'Nakara City');
    assert.equal(kvp.writes.length, 1);

    // Setting the current default, or a normalized posture list, changes nothing either.
    settings.set('retentionDays', 30);
    assert.equal(kvp.writes.length, 1);
    settings.set('policy', { profile: 'posture', required_collectors: ['wrong'] });
    assert.equal(kvp.writes.length, 2);
    settings.set('policy', { profile: 'posture', require_elevation: false });
    assert.equal(kvp.writes.length, 2);
});

test('posture fixes required_collectors to exactly the six posture collectors', () => {
    assert.deepEqual(POSTURE, [
        'posture',
        'os_image',
        'install_marker',
        'defender_exclusion',
        'net_config',
        'driver_service',
    ]);
    assert.deepEqual(POSTURE_COLLECTORS, POSTURE);
    assert.equal(Object.isFrozen(POSTURE_COLLECTORS), true);
    const settings = createSettings(memoryKvp());
    assert.deepEqual(
        settings.set('policy', { profile: 'posture', required_collectors: ['wrong'] }),
        { ok: true },
    );
    assert.deepEqual(settings.get().policy, {
        profile: 'posture',
        required_collectors: POSTURE,
        require_elevation: false,
    });
    settings.set('policy', { profile: 'posture', require_elevation: true });
    assert.deepEqual(settings.get().policy, {
        profile: 'posture',
        required_collectors: POSTURE,
        require_elevation: true,
    });
    const built = buildPolicy(settings);
    assert.deepEqual(built.required_collectors, POSTURE);
    assert.equal(built.require_elevation, true);
});

test('custom policy refuses an empty list, a non-string and a duplicate', () => {
    const settings = createSettings(memoryKvp());
    const invalid = [
        [],
        ['posture', 5],
        ['posture', 'posture'],
        [''],
        Array.from({ length: 65 }, (_, index) => `collector-${index}`),
    ];
    for (const required_collectors of invalid) {
        assert.deepEqual(
            settings.set('policy', { profile: 'custom', required_collectors }),
            { ok: false, reason: 'invalid_policy' },
            JSON.stringify(required_collectors),
        );
    }
    assert.deepEqual(
        settings.set('policy', {
            profile: 'custom',
            required_collectors: ['posture', 'net_config'],
        }),
        { ok: true },
    );
});

test('standard fixes required_collectors to the twenty standard collectors', () => {
    assert.deepEqual(STANDARD, [
        'antivirus_product',
        'autostart',
        'bam',
        'defender_exclusion',
        'driver_service',
        'event_fields',
        'evtx',
        'fivem_dir',
        'hid_device',
        'install_marker',
        'net_config',
        'os_image',
        'pca',
        'pci_device',
        'posture',
        'prefetch',
        'process',
        'userassist',
        'usn',
        'windows_start',
    ]);
    assert.deepEqual(STANDARD_COLLECTORS, STANDARD);
    assert.equal(Object.isFrozen(STANDARD_COLLECTORS), true);
    assert.equal(STANDARD.length, 20);
    assert.equal(new Set(STANDARD).size, 20);
    assert.deepEqual([...STANDARD].sort(), STANDARD);
    for (const fullTier of ['powershell_text', 'fivem_servers', 'recorded_files']) {
        assert.equal(STANDARD.includes(fullTier), false, fullTier);
    }

    const settings = createSettings(memoryKvp());
    assert.deepEqual(
        settings.set('policy', {
            profile: 'standard',
            required_collectors: ['posture'],
            require_elevation: false,
        }),
        { ok: true },
    );
    assert.deepEqual(settings.get().policy, {
        profile: 'standard',
        required_collectors: STANDARD,
        require_elevation: false,
    });
    const built = buildPolicy(settings);
    assert.deepEqual(built.required_collectors, STANDARD);
});

test('buildPolicy always carries required_collectors', () => {
    const settings = createSettings(memoryKvp());
    settings.set('serverName', 'Example City');

    settings.set('policy', { profile: 'posture', require_elevation: false });
    const posture = buildPolicy(settings);
    assert.equal(Object.prototype.hasOwnProperty.call(posture, 'required_collectors'), true);
    assert.deepEqual(posture.required_collectors, POSTURE);

    settings.set('policy', { profile: 'standard', require_elevation: true });
    const standard = buildPolicy(settings);
    assert.equal(Object.prototype.hasOwnProperty.call(standard, 'required_collectors'), true);
    assert.deepEqual(standard.required_collectors, STANDARD);
    assert.equal(standard.require_elevation, true);

    settings.set('policy', {
        profile: 'custom',
        required_collectors: ['posture', 'net_config'],
        require_elevation: false,
    });
    const custom = buildPolicy(settings);
    assert.equal(Object.prototype.hasOwnProperty.call(custom, 'required_collectors'), true);
    assert.deepEqual(custom.required_collectors, ['posture', 'net_config']);
});

test('buildPolicy is stable through policyHash and changes when serverName changes', () => {
    const settings = createSettings(memoryKvp());
    settings.set('serverName', 'Example City');
    const first = buildPolicy(settings);
    const second = buildPolicy(settings);
    assert.deepEqual(first, {
        profile: 'posture',
        required_collectors: POSTURE,
        require_elevation: false,
        server_name: 'Example City',
    });
    assert.equal(policyHash(first), policyHash(second));

    const before = policyHash(first);
    settings.set('serverName', 'Other City');
    const changed = buildPolicy(settings);
    assert.equal(changed.server_name, 'Other City');
    assert.notEqual(policyHash(changed), before);
});

test('an origin with a path or userinfo is refused', () => {
    const settings = createSettings(memoryKvp());
    for (const origin of [
        'https://server.example/path',
        'https://user@server.example',
        'https://user:pass@server.example',
    ]) {
        assert.deepEqual(
            settings.set('publicOrigin', origin),
            { ok: false, reason: 'invalid_public_origin' },
        );
    }
});

test('canOpenCase names the missing public origin first, then the missing server name', () => {
    const settings = createSettings(memoryKvp());
    assert.deepEqual(canOpenCase(settings), { ok: false, reason: 'public_origin_missing' });
    settings.set('publicOrigin', 'http://192.0.2.10:30120');
    assert.deepEqual(canOpenCase(settings), { ok: false, reason: 'server_name_missing' });
    settings.set('serverName', 'Nakara City');
    assert.deepEqual(canOpenCase(settings), { ok: true });
});

test('settings.js source does not read a convar', () => {
    const sources = [createSettings, buildPolicy, canOpenCase].map((fn) => fn.toString());
    assert.equal(sources.join('\n').includes('GetConvar'), false);
});
