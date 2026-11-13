'use strict';

// Rongroi settings (ADR 0001, section 11). The in-game panel writes these through an injected resource KVP
// adapter; nothing here reads a convar. A stored value that does not validate on read falls back to its
// default and is listed in get().corrupt.

// FXServer resolves a relative require() against the resource root, not against the requiring file, so
// './pairing.js' only exists on plain Node. Try the file-relative path first and fall back to the
// resource-root path. This needs no fs probe beyond require() itself.
function isMissingModule(err) {
    if (!err) return false;
    return err.code === 'MODULE_NOT_FOUND' || /^Cannot find module\b/.test(err.message || '');
}

function loadModule(relative, rootRelative) {
    try { return relative(); }
    catch (err) {
        if (!isMissingModule(err)) throw err;
        return rootRelative();
    }
}

const { checkOrigin } = loadModule(
    () => require('./pairing.js'),
    () => require('./server/js/pairing.js'),
);
const { clampDays } = loadModule(
    () => require('./retention.js'),
    () => require('./server/js/retention.js'),
);

const KEY_PREFIX = 'rongroi:settings:';
const KEYS = {
    publicOrigin: `${KEY_PREFIX}publicOrigin`,
    retentionDays: `${KEY_PREFIX}retentionDays`,
    backendOverride: `${KEY_PREFIX}backendOverride`,
    uploadPageEnabled: `${KEY_PREFIX}uploadPageEnabled`,
    serverName: `${KEY_PREFIX}serverName`,
    policy: `${KEY_PREFIX}policy`,
    ttlMs: `${KEY_PREFIX}ttlMs`,
};
const NAMES = Object.keys(KEYS);
const BACKENDS = new Set(['auto', 'kvp', 'file']);
const PROFILES = new Set(['posture', 'standard', 'custom']);
const POSTURE_COLLECTORS = Object.freeze([
    'posture',
    'os_image',
    'install_marker',
    'defender_exclusion',
    'net_config',
    'driver_service',
]);
// The standard-tier collectors of the client this Kit version targets. The three full-tier ids are left out
// because a client never scans them without its own question (ADR 0052 in aeterna-rongroi).
const STANDARD_COLLECTORS = Object.freeze([
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
const MAX_COLLECTORS = 64;
const MIN_TTL_MS = 60000;
const MAX_TTL_MS = 3600000;
// Same 5 minute default as tickets.js (ADR 0001, section 3); tickets.js does not export its constant.
const DEFAULT_TTL_MS = 300000;
const CONTROL_RE = /[\u0000-\u001f\u007f-\u009f]/;

function defaultPolicy() {
    return { profile: 'posture', require_elevation: false };
}

function defaultFor(name) {
    switch (name) {
        case 'publicOrigin': return null;
        case 'retentionDays': return clampDays(undefined);
        case 'backendOverride': return 'auto';
        case 'uploadPageEnabled': return false;
        case 'serverName': return null;
        case 'policy': return defaultPolicy();
        case 'ttlMs': return DEFAULT_TTL_MS;
        default: return undefined;
    }
}

function bad(reason) {
    return { ok: false, reason };
}

function normalizePolicy(value) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return bad('invalid_policy');
    if (typeof value.profile !== 'string' || !PROFILES.has(value.profile)) return bad('invalid_policy');
    const elevation = value.require_elevation === undefined ? false : value.require_elevation;
    if (typeof elevation !== 'boolean') return bad('invalid_policy');

    if (value.profile === 'posture') {
        return {
            ok: true,
            value: {
                profile: 'posture',
                required_collectors: [...POSTURE_COLLECTORS],
                require_elevation: elevation,
            },
        };
    }
    if (value.profile === 'standard') {
        return {
            ok: true,
            value: {
                profile: 'standard',
                required_collectors: [...STANDARD_COLLECTORS],
                require_elevation: elevation,
            },
        };
    }

    const collectors = value.required_collectors;
    if (!Array.isArray(collectors) || collectors.length === 0
        || collectors.length > MAX_COLLECTORS) {
        return bad('invalid_policy');
    }
    const seen = new Set();
    for (const collector of collectors) {
        if (typeof collector !== 'string' || collector.length === 0 || seen.has(collector)) {
            return bad('invalid_policy');
        }
        seen.add(collector);
    }
    return {
        ok: true,
        value: {
            profile: 'custom',
            required_collectors: [...collectors],
            require_elevation: elevation,
        },
    };
}

function normalize(name, value) {
    switch (name) {
        case 'publicOrigin':
            try {
                return { ok: true, value: checkOrigin(value) };
            } catch {
                return bad('invalid_public_origin');
            }
        case 'retentionDays':
            if (typeof value !== 'number' || !Number.isFinite(value)) {
                return bad('invalid_retention_days');
            }
            return { ok: true, value: clampDays(value) };
        case 'backendOverride':
            if (typeof value !== 'string' || !BACKENDS.has(value)) return bad('invalid_backend_override');
            return { ok: true, value };
        case 'uploadPageEnabled':
            if (typeof value !== 'boolean') return bad('invalid_upload_page_enabled');
            return { ok: true, value };
        case 'serverName':
            if (typeof value !== 'string' || value.length < 1 || value.length > 128
                || CONTROL_RE.test(value)) {
                return bad('invalid_server_name');
            }
            return { ok: true, value };
        case 'policy':
            return normalizePolicy(value);
        case 'ttlMs':
            if (!Number.isInteger(value) || value < MIN_TTL_MS || value > MAX_TTL_MS) {
                return bad('invalid_ttl_ms');
            }
            return { ok: true, value };
        default:
            return bad('unknown_setting');
    }
}

// Scalars keep the raw KVP string form the existing retention key already uses; the policy is JSON.
function decode(name, stored) {
    if (stored === undefined || stored === null) {
        return { value: defaultFor(name), corrupt: false };
    }
    if (typeof stored !== 'string') {
        return { value: defaultFor(name), corrupt: true };
    }
    let parsed;
    if (name === 'policy') {
        try {
            parsed = JSON.parse(stored);
        } catch {
            return { value: defaultFor(name), corrupt: true };
        }
    } else if (name === 'retentionDays' || name === 'ttlMs') {
        if (stored.trim().length === 0) return { value: defaultFor(name), corrupt: true };
        parsed = Number(stored);
    } else if (name === 'uploadPageEnabled') {
        if (stored === 'true') parsed = true;
        else if (stored === 'false') parsed = false;
        else return { value: defaultFor(name), corrupt: true };
    } else {
        parsed = stored;
    }
    const checked = normalize(name, parsed);
    if (!checked.ok) return { value: defaultFor(name), corrupt: true };
    return { value: checked.value, corrupt: false };
}

function encode(name, value) {
    if (name === 'policy') return JSON.stringify(value);
    if (name === 'uploadPageEnabled') return value ? 'true' : 'false';
    if (typeof value === 'number') return String(value);
    return value;
}

function sameValue(name, left, right) {
    if (name !== 'policy') return left === right;
    if (left.profile !== right.profile || left.require_elevation !== right.require_elevation) return false;
    const leftList = left.required_collectors;
    const rightList = right.required_collectors;
    if (leftList === undefined || rightList === undefined) return leftList === rightList;
    return leftList.length === rightList.length
        && leftList.every((collector, index) => collector === rightList[index]);
}

function readOne(kvp, name) {
    return decode(name, kvp.get(KEYS[name]));
}

function valuesOf(settings) {
    if (settings === null || typeof settings !== 'object') {
        throw new TypeError('settings must be an object');
    }
    if (typeof settings.get === 'function') return settings.get();
    return settings;
}

function createSettings(kvp) {
    if (!kvp || typeof kvp.get !== 'function' || typeof kvp.set !== 'function') {
        throw new TypeError('kvp must provide get(key) and set(key, value)');
    }

    function get() {
        const values = {};
        const corrupt = [];
        for (const name of NAMES) {
            const read = readOne(kvp, name);
            values[name] = read.value;
            if (read.corrupt) corrupt.push(name);
        }
        values.corrupt = corrupt;
        return values;
    }

    function set(name, value) {
        if (typeof name !== 'string' || !Object.prototype.hasOwnProperty.call(KEYS, name)) {
            return bad('unknown_setting');
        }
        const checked = normalize(name, value);
        if (!checked.ok) return checked;
        const current = readOne(kvp, name);
        if (!current.corrupt && sameValue(name, current.value, checked.value)) return { ok: true };
        kvp.set(KEYS[name], encode(name, checked.value));
        return { ok: true };
    }

    return { get, set };
}

// The policy object a ticket carries: the profile's collector list, elevation, and the server name.
function buildPolicy(settings) {
    const values = valuesOf(settings);
    const checked = normalizePolicy(values.policy);
    const policy = checked.ok ? checked.value : normalizePolicy(defaultPolicy()).value;
    return {
        profile: policy.profile,
        required_collectors: [...policy.required_collectors],
        require_elevation: policy.require_elevation,
        server_name: typeof values.serverName === 'string' ? values.serverName : null,
    };
}

function canOpenCase(settings) {
    const values = valuesOf(settings);
    if (typeof values.publicOrigin !== 'string' || values.publicOrigin.length === 0) {
        return { ok: false, reason: 'public_origin_missing' };
    }
    if (typeof values.serverName !== 'string' || values.serverName.length === 0) {
        return { ok: false, reason: 'server_name_missing' };
    }
    return { ok: true };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = {
        createSettings,
        buildPolicy,
        canOpenCase,
        POSTURE_COLLECTORS,
        STANDARD_COLLECTORS,
    };
}
