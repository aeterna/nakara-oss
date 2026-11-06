'use strict';

// Staff panel controller (ADR 0001, section 10). Pure: every FXServer touch is injected, so the specs run in
// plain Node. A method checks the caller first (the staff ACE, or the player's own open case for requestCode),
// then its rate limit, then its arguments, and only ever sends to that checked source.

// FXServer resolves a relative require() against the resource root, not against the requiring file, so these
// siblings only exist on plain Node. Try the file-relative path first and fall back to the resource-root path.
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

const { caseList, caseView } = loadModule(
    () => require('./caseview.js'), () => require('./server/js/caseview.js'),
);
const { createSettings, buildPolicy, canOpenCase } = loadModule(
    () => require('./settings.js'), () => require('./server/js/settings.js'),
);
const { pairingCode, policyHash } = loadModule(
    () => require('./pairing.js'), () => require('./server/js/pairing.js'),
);
const envelope = loadModule(
    () => require('./envelope.js'), () => require('./server/js/envelope.js'),
);

const STAFF_LIMIT = 20;
const CODE_LIMIT = 3;
const RATE_WINDOW_MS = 10000;
const CASE_ID_BYTES = 16;
const CASE_ID_RE = /^[0-9a-f]{32}$/;
const PANEL_DATA = 'nakara_rongroi:panel:data';
const SETTINGS_DATA = 'nakara_rongroi:settings:data';
const SHOW_CODE = 'nakara_rongroi:showCode';

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nonEmptyString(value) {
    return typeof value === 'string' && value.length > 0;
}

function validSource(src) {
    return (typeof src === 'number' && Number.isInteger(src) && src > 0) || nonEmptyString(src);
}

function createPanel(deps) {
    if (!isObject(deps)) throw new TypeError('deps must be an object');
    const { settings, storage, store, kit, now, isStaff, getPlayer, send } = deps;
    if (!isObject(settings) || typeof settings.get !== 'function') {
        throw new TypeError('settings must provide get()');
    }
    if (!isObject(storage) || typeof storage.getCase !== 'function' || typeof storage.openCase !== 'function') {
        throw new TypeError('storage must provide getCase() and openCase()');
    }
    if (!isObject(store) || typeof store.issue !== 'function') throw new TypeError('store must provide issue()');
    if (!isObject(kit)) throw new TypeError('kit must be an object');
    if (typeof now !== 'function' || typeof isStaff !== 'function'
        || typeof getPlayer !== 'function' || typeof send !== 'function') {
        throw new TypeError('deps must provide now, isStaff, getPlayer and send functions');
    }
    const randomBytes = typeof deps.randomBytes === 'function'
        ? deps.randomBytes
        : (typeof store.randomBytes === 'function' ? store.randomBytes : null);
    if (typeof randomBytes !== 'function') throw new TypeError('deps.randomBytes must be a function');
    const caseFacts = deps.caseFacts;

    const windows = new Map(); // `${kind}:${source}` -> { end, count }
    const playerCases = new Map(); // player source -> { caseId, ticket, expiresAt, ... }

    // Fixed 10 s window per source and kind. Returns false once the window is over its limit.
    function rateLimit(kind, src, limit) {
        const key = `${kind}:${String(src)}`;
        const at = now();
        let window = windows.get(key);
        if (!window || at >= window.end) {
            window = { end: at + RATE_WINDOW_MS, count: 0 };
            windows.set(key, window);
        }
        window.count += 1;
        return window.count <= limit;
    }

    function refuse(src, reason) {
        send(src, PANEL_DATA, { screen: 'error', reason });
    }

    function allEntries() {
        if (typeof storage.entries === 'function') {
            const entries = storage.entries();
            if (Array.isArray(entries)) return entries;
        }
        if (typeof storage.listCases !== 'function') return [];
        const entries = [];
        for (let page = 0; ; page += 1) {
            const rows = storage.listCases({ page });
            if (!Array.isArray(rows) || rows.length === 0) return entries;
            for (const row of rows) entries.push(row);
        }
    }

    // The list shows index facts plus the case file's safe fields, never a report body.
    function listRows() {
        const rows = [];
        for (const entry of allEntries()) {
            if (!isObject(entry) || !nonEmptyString(entry.caseId)) {
                rows.push(entry);
                continue;
            }
            let data = null;
            try { data = storage.getCase(entry.caseId); } catch { data = null; }
            rows.push(isObject(data) ? { ...entry, ...data } : entry);
        }
        return caseList(rows);
    }

    function safeReport(ticket) {
        if (!nonEmptyString(ticket) || typeof storage.getReport !== 'function') return null;
        try { return storage.getReport(ticket); } catch { return null; }
    }

    function factsFor(caseId, data) {
        const base = isObject(data) ? { ...data } : {};
        if (typeof caseFacts !== 'function') return base;
        try { return { ...base, ...(caseFacts(caseId, base) || {}) }; }
        catch { return base; }
    }

    function viewFor(data) {
        if (!isObject(data)) return null;
        const facts = factsFor(data.caseId, data);
        const ticket = nonEmptyString(facts.ticket) ? facts.ticket : data.ticket;
        const ticketState = typeof store.stateOf === 'function' && nonEmptyString(ticket) ? store.stateOf(ticket) : null;
        return caseView({ caseFacts: facts, ticketState, report: safeReport(ticket), now: now() });
    }

    function makePairingCode(serverOrigin, issued, policy) {
        return pairingCode({
            serverOrigin,
            ticket: issued.ticket,
            nonce: issued.nonce,
            expiresAt: issued.expiresAt,
            policyHash: policyHash(policy),
            kitPublicKey: kit.publicKey,
        });
    }
    function newCaseId() {
        for (let attempt = 0; attempt < 16; attempt += 1) {
            const bytes = randomBytes(CASE_ID_BYTES);
            const caseId = bytes && typeof bytes.toString === 'function' ? bytes.toString('hex') : '';
            if (!CASE_ID_RE.test(caseId)) continue;
            const known = typeof storage.hasCase === 'function' ? storage.hasCase(caseId) : storage.getCase(caseId) !== null;
            if (!known) return caseId;
        }
        throw new Error('could not allocate a case id');
    }

    // A kit adapter may rotate itself. The injected pair is otherwise rotated in memory, which is what the
    // pure specs exercise; main.js supplies an adapter that also persists the new pair.
    function rotateKit() {
        const rotate = [kit.rotate, kit.rotateKey, deps.rotateKit, deps.rotateKey, deps.rotateKitKey]
            .find((fn) => typeof fn === 'function');
        const pair = typeof rotate === 'function' ? rotate.call(kit) : envelope.generateKeyPair();
        if (isObject(pair) && nonEmptyString(pair.publicKey)) {
            kit.publicKey = pair.publicKey;
            if (nonEmptyString(pair.privateKey)) kit.privateKey = pair.privateKey;
        }
        return nonEmptyString(kit.publicKey);
    }

    // Validate the whole patch against a throw-away settings instance before touching the real one, so a
    // bad value cannot leave the earlier members of the same patch applied.
    function checkSettingsPatch(patch) {
        if (!isObject(patch)) return { ok: false, reason: 'invalid_settings' };
        const probe = createSettings({ get: () => undefined, set: () => {} });
        for (const [name, value] of Object.entries(patch)) {
            const result = probe.set(name, value);
            if (!isObject(result) || result.ok !== true) {
                return {
                    ok: false,
                    reason: isObject(result) && nonEmptyString(result.reason)
                        ? result.reason
                        : 'invalid_settings',
                };
            }
        }
        return { ok: true };
    }

    function forgetTicket(ticket) {
        if (!nonEmptyString(ticket) || typeof store.forget !== 'function') return false;
        try { return store.forget(ticket) === true; } catch { return false; }
    }

    // Delete one case and forget its ticket, the pair main.js's retention pass needs later.
    function deleteCaseAndForget(caseId) {
        const ticket = storage.deleteCase(caseId);
        if (nonEmptyString(ticket)) forgetTicket(ticket);
        return ticket;
    }

    function dropPlayerCases(match) {
        for (const [key, entry] of playerCases) {
            if (isObject(entry) && match(entry)) playerCases.delete(key);
        }
    }

    // Key rotation invalidates open tickets only: consumed and expired tickets keep their state.
    function forgetOpenTickets() {
        const forgotten = new Set();
        const tickets = store.tickets;
        if (!(tickets instanceof Map)) return forgotten;
        for (const [ticket, record] of tickets) {
            if (!isObject(record) || (record.state !== 'issued' && record.state !== 'uploading')) continue;
            if (forgetTicket(ticket)) forgotten.add(ticket);
        }
        return forgotten;
    }

    function liveCaseFor(src) {
        const key = String(src);
        const entry = playerCases.get(key);
        if (!entry) return null;
        if (now() >= entry.expiresAt) {
            playerCases.delete(key);
            return null;
        }
        return entry;
    }
    function requestCode(src) {
        const entry = liveCaseFor(src);
        if (!entry || !rateLimit('code', src, CODE_LIMIT)) return false;
        let code = entry.code;
        if (!nonEmptyString(code)) {
            try { code = makePairingCode(entry.serverOrigin, entry, entry.policy); }
            catch { code = null; }
        }
        if (!nonEmptyString(code)) return false;
        send(src, SHOW_CODE, { code, expiresAt: entry.expiresAt });
        return true;
    }
    function panelOpen(src) {
        if (!isStaff(src) || !rateLimit('staff', src, STAFF_LIMIT)) return false;
        send(src, PANEL_DATA, { screen: 'list', cases: listRows() });
        return true;
    }

    function panelCase(src, caseId) {
        if (!isStaff(src) || !rateLimit('staff', src, STAFF_LIMIT)) return false;
        if (!nonEmptyString(caseId)) {
            refuse(src, 'invalid_case_id');
            return false;
        }
        let data = null;
        try { data = storage.getCase(caseId); } catch { data = null; }
        if (!isObject(data)) {
            refuse(src, 'case_not_found');
            return false;
        }
        send(src, PANEL_DATA, { screen: 'case', case: viewFor(data) });
        return true;
    }

    function panelOpenCase(src, target) {
        if (!isStaff(src) || !rateLimit('staff', src, STAFF_LIMIT)) return false;
        if (!validSource(target)) {
            refuse(src, 'invalid_target');
            return false;
        }
        const player = getPlayer(target);
        if (!isObject(player) || !nonEmptyString(player.identifier)) {
            refuse(src, 'player_not_found');
            return false;
        }
        let values;
        let open;
        try {
            values = settings.get();
            open = canOpenCase(settings);
        } catch {
            refuse(src, 'settings_unavailable');
            return false;
        }
        if (!open || open.ok !== true) {
            refuse(src, open && nonEmptyString(open.reason) ? open.reason : 'case_not_opened');
            return false;
        }
        const policy = buildPolicy(settings);
        let caseId;
        let issued;
        try {
            caseId = newCaseId();
            const ttlMs = Number.isInteger(values.ttlMs) && values.ttlMs > 0 ? values.ttlMs : undefined;
            issued = store.issue({ caseId, policy, ttlMs });
        } catch {
            refuse(src, 'case_not_opened');
            return false;
        }
        const facts = {
            openedBy: `staff:${String(src)}`,
            openedAt: issued.issuedAt,
            identifier: player.identifier,
            connectAddress: player.endpoint,
            policy,
            expiresAt: issued.expiresAt,
            origin: 'connect',
            state: 'opened',
        };
        try {
            storage.openCase({ caseId, ticket: issued.ticket, openedAt: issued.issuedAt, ...facts });
        } catch {
            if (typeof store.cancel === 'function') store.cancel(issued.ticket);
            refuse(src, 'case_not_opened');
            return false;
        }
        let code = null;
        try { code = makePairingCode(values.publicOrigin, issued, policy); } catch { code = null; }
        playerCases.set(String(target), {
            caseId,
            ticket: issued.ticket,
            nonce: issued.nonce,
            expiresAt: issued.expiresAt,
            serverOrigin: values.publicOrigin,
            policy,
            code,
        });
        let data = null;
        try { data = storage.getCase(caseId); } catch { data = null; }
        send(src, PANEL_DATA, {
            screen: 'case',
            case: viewFor(data || { caseId, ticket: issued.ticket, ...facts }),
        });
        return true;
    }
    function saveSettings(src, patch) {
        if (!isStaff(src) || !rateLimit('staff', src, STAFF_LIMIT)) return false;
        const checked = checkSettingsPatch(patch);
        if (checked.ok !== true) {
            refuse(src, checked.reason);
            return false;
        }
        for (const [name, value] of Object.entries(patch)) {
            const result = settings.set(name, value);
            if (!isObject(result) || result.ok !== true) {
                refuse(src, isObject(result) && nonEmptyString(result.reason)
                    ? result.reason
                    : 'invalid_settings');
                return false;
            }
        }
        let values;
        try { values = settings.get(); } catch {
            refuse(src, 'settings_unavailable');
            return false;
        }
        send(src, SETTINGS_DATA, values);
        return true;
    }

    function deleteCase(src, caseId) {
        if (!isStaff(src) || !rateLimit('staff', src, STAFF_LIMIT)) return false;
        if (!nonEmptyString(caseId)) {
            refuse(src, 'invalid_case_id');
            return false;
        }
        let ticket;
        try { ticket = deleteCaseAndForget(caseId); } catch {
            refuse(src, 'delete_failed');
            return false;
        }
        if (!nonEmptyString(ticket)) {
            refuse(src, 'case_not_found');
            return false;
        }
        dropPlayerCases((entry) => entry.caseId === caseId);
        send(src, PANEL_DATA, { screen: 'list', cases: listRows() });
        return true;
    }

    function deletePlayer(src, identifier) {
        if (!isStaff(src) || !rateLimit('staff', src, STAFF_LIMIT)) return false;
        if (!nonEmptyString(identifier)) {
            refuse(src, 'invalid_identifier');
            return false;
        }
        if (typeof storage.deletePlayerData !== 'function') {
            refuse(src, 'delete_failed');
            return false;
        }
        let tickets;
        try { tickets = storage.deletePlayerData(identifier); } catch {
            refuse(src, 'delete_failed');
            return false;
        }
        const deleted = Array.isArray(tickets) ? tickets.filter(nonEmptyString) : [];
        for (const ticket of deleted) forgetTicket(ticket);
        const removed = new Set(deleted);
        dropPlayerCases((entry) => removed.has(entry.ticket));
        send(src, PANEL_DATA, { screen: 'list', cases: listRows() });
        return true;
    }

    function rotateKey(src) {
        if (!isStaff(src) || !rateLimit('staff', src, STAFF_LIMIT)) return false;
        let rotated = false;
        try { rotated = rotateKit(); } catch { rotated = false; }
        if (!rotated) {
            refuse(src, 'key_rotation_failed');
            return false;
        }
        const forgotten = forgetOpenTickets();
        dropPlayerCases((entry) => forgotten.has(entry.ticket));
        let values;
        try { values = settings.get(); } catch { values = {}; }
        send(src, SETTINGS_DATA, values);
        return true;
    }

    return {
        requestCode,
        panelOpen,
        panelCase,
        panelOpenCase,
        saveSettings,
        deleteCase,
        deletePlayer,
        rotateKey,
        deleteCaseAndForget,
    };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { createPanel };
}
