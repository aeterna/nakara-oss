(function () {
    'use strict';

    // FXServer resolves a relative require() against the resource root, not against the requiring file, so
    // './http.js' only exists on plain Node. Try the file-relative path first and fall back to the
    // resource-root path, as the other server modules do.
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

    // Every module below is loaded with require(); main.js is the only script that wires them up.
    const { createHandler } = loadModule(
        () => require('./http.js'),
        () => require('./server/js/http.js'),
    );
    const { loadOrCreateKitKey, rotateKitKey } = loadModule(
        () => require('./keys.js'),
        () => require('./server/js/keys.js'),
    );
    const { TicketStore } = loadModule(
        () => require('./tickets.js'),
        () => require('./server/js/tickets.js'),
    );
    const { pairingCode, policyHash } = loadModule(
        () => require('./pairing.js'),
        () => require('./server/js/pairing.js'),
    );
    const { clampDays, dueCases } = loadModule(
        () => require('./retention.js'),
        () => require('./server/js/retention.js'),
    );
    const { createStorage, createKvpBackend, detectEdition } = loadModule(
        () => require('./storage.js'),
        () => require('./server/js/storage.js'),
    );
    const { createFileBackend } = loadModule(
        () => require('./filestore.js'),
        () => require('./server/js/filestore.js'),
    );
    const { createSettings } = loadModule(
        () => require('./settings.js'),
        () => require('./server/js/settings.js'),
    );
    const { createPanel, nativeBool } = loadModule(
        () => require('./panel.js'),
        () => require('./server/js/panel.js'),
    );
    const crypto = require('crypto');

    const STAFF_ACE = 'nakara_rongroi.staff';
    const NET_WINDOW_MS = 10000;
    const NET_LIMIT = 60;
    const NET_WINDOW_MAX = 256;

    function log(...parts) {
        console.log(`nakara_rongroi: ${parts.join(' ')}`);
    }

    function isObject(value) {
        return value !== null && typeof value === 'object' && !Array.isArray(value);
    }

    // Read the first present member of a net-event payload.
    function field(payload, names) {
        if (!isObject(payload)) return undefined;
        for (const name of names) {
            if (Object.prototype.hasOwnProperty.call(payload, name)) return payload[name];
        }
        return undefined;
    }

    function asCaseId(payload) {
        if (typeof payload === 'string') return payload;
        const value = field(payload, ['caseId', 'case_id', 'id']);
        return typeof value === 'string' ? value : undefined;
    }

    function asTarget(payload) {
        if (typeof payload === 'number' || typeof payload === 'string') return payload;
        return field(payload, ['target', 'source', 'player', 'playerId', 'serverId']);
    }

    function asIdentifier(payload) {
        if (typeof payload === 'string') return payload;
        const value = field(payload, ['identifier', 'playerIdentifier']);
        return typeof value === 'string' ? value : undefined;
    }

    function asScreen(payload) {
        if (typeof payload === 'string') return payload;
        const value = field(payload, ['screen']);
        return typeof value === 'string' ? value : undefined;
    }

    // A settings patch may arrive directly, wrapped, or as a bare policy from the policy editor.
    function asSettingsPatch(payload) {
        if (!isObject(payload)) return undefined;
        if (typeof payload.profile === 'string'
            && !Object.prototype.hasOwnProperty.call(payload, 'policy')) {
            return { policy: payload };
        }
        const nested = field(payload, ['patch', 'settings', 'values']);
        return isObject(nested) ? nested : payload;
    }

    try {
        const kvp = {
            get(key) { return GetResourceKvpString(key); },
            set(key, value) { SetResourceKvp(key, value); },
            del(key) { DeleteResourceKvp(key); },
        };
        const edition = detectEdition((_, fallback) => GetConvar('gamename', fallback));
        const backend = edition === 'enhanced' ? createFileBackend() : createKvpBackend(kvp);
        const storage = createStorage(backend);
        const settings = createSettings(kvp);
        const kit = loadOrCreateKitKey(kvp);
        const store = new TicketStore({ now: Date.now, randomBytes: crypto.randomBytes });
        const onReport = (event) => {
            storage.saveReport(event);
            log(`report received ${event.ticket}`);
        };
        const { damaged } = storage.load();
        if (damaged > 0) log(`index damaged: ${damaged} pages`);
        store.restoreConsumed(storage.consumedSnapshot());
        log(`storage ${edition}`);

        function isStaff(src) {
            return nativeBool(IsPlayerAceAllowed(src, STAFF_ACE));
        }

        function getPlayer(src) {
            const id = Number(src);
            if (!Number.isSafeInteger(id) || id <= 0) return null;
            const identifier = GetPlayerIdentifierByType(id, 'license');
            const endpoint = GetPlayerEndpoint(id);
            if (typeof identifier !== 'string' || identifier.length === 0) return null;
            return { identifier, endpoint: typeof endpoint === 'string' ? endpoint : '' };
        }

        function send(src, event, payload) {
            emitNet(event, src, payload);
        }

        const panel = createPanel({
            settings,
            storage,
            store,
            kit,
            now: Date.now,
            isStaff,
            getPlayer,
            send,
            randomBytes: crypto.randomBytes,
            rotateKitKey: () => rotateKitKey(kvp),
        });

        // One case every 250 ms: a storage write blocks the tick, and Enhanced's writes are the slowest
        // (ADR 0001, section 4). A second sweep waits for the running one.
        let retentionRunning = false;

        function runRetention() {
            if (retentionRunning) return;
            retentionRunning = true;
            let due;
            try {
                const days = clampDays(settings.get().retentionDays);
                due = dueCases(storage.entries(), Date.now(), days);
            } catch {
                retentionRunning = false;
                log('retention scan failed');
                return;
            }
            let index = 0;
            let removed = 0;
            function removeNext() {
                if (index >= due.length) {
                    retentionRunning = false;
                    if (removed > 0) log(`retention removed ${removed} cases`);
                    return;
                }
                const caseId = due[index];
                index += 1;
                try {
                    if (panel.deleteCaseAndForget(caseId)) removed += 1;
                } catch {
                    log('retention failed to remove one case');
                }
                setTimeout(removeNext, 250);
            }
            removeNext();
        }

        runRetention();
        setInterval(runRetention, 3600000);

        const handler = createHandler({ store, kit, now: Date.now, onReport, log });

        function openCase({ caseId, policy, serverOrigin, ttlMs } = {}) {
            if (storage.hasCase(caseId)) throw new TypeError('case id is already open');
            const issued = store.issue({ caseId, policy, ttlMs });
            try {
                storage.openCase({
                    caseId,
                    ticket: issued.ticket,
                    openedAt: issued.issuedAt,
                    policy,
                    expiresAt: issued.expiresAt,
                    serverOrigin,
                });
                return {
                    ticket: issued.ticket,
                    nonce: issued.nonce,
                    expiresAt: issued.expiresAt,
                    pairingCode: pairingCode({
                        serverOrigin,
                        ticket: issued.ticket,
                        nonce: issued.nonce,
                        expiresAt: issued.expiresAt,
                        policyHash: policyHash(policy),
                        kitPublicKey: kit.publicKey,
                    }),
                };
            } catch (err) {
                store.cancel(issued.ticket);
                throw err;
            }
        }

        function getCase(caseId) {
            if (typeof caseId !== 'string' || caseId.length === 0) return null;
            return storage.getCase(caseId);
        }

        function listCases() {
            return storage.entries();
        }

        function deleteCase(caseId) {
            if (typeof caseId !== 'string' || caseId.length === 0) return false;
            return panel.deleteCaseAndForget(caseId);
        }

        function deletePlayerData(identifier) {
            if (typeof identifier !== 'string' || identifier.length === 0) return 0;
            const deleted = panel.deletePlayerDataAndForget(identifier);
            return Array.isArray(deleted) ? deleted.length : 0;
        }

        function getPairingCode(caseId) {
            if (typeof caseId !== 'string' || caseId.length === 0) return null;
            const data = storage.getCase(caseId);
            if (!isObject(data) || typeof data.ticket !== 'string') return null;
            const found = store.lookup(data.ticket);
            if (!isObject(found) || (found.state !== 'issued' && found.state !== 'uploading')) return null;
            if (!Number.isSafeInteger(data.expiresAt)) return null;
            let serverOrigin = data.serverOrigin;
            if (typeof serverOrigin !== 'string' || serverOrigin.length === 0) {
                let values;
                try { values = settings.get(); } catch { return null; }
                serverOrigin = values.publicOrigin;
            }
            if (typeof serverOrigin !== 'string' || serverOrigin.length === 0) return null;
            const policy = isObject(found.policy) ? found.policy : data.policy;
            if (!isObject(policy)) return null;
            try {
                return pairingCode({
                    serverOrigin,
                    ticket: data.ticket,
                    nonce: found.nonce,
                    expiresAt: data.expiresAt,
                    policyHash: policyHash(policy),
                    kitPublicKey: kit.publicKey,
                });
            } catch {
                return null;
            }
        }

        // A fixed 10 s guard per source in front of the panel's own per-kind limits. Every handler below
        // still checks the ACE, or the player's own open case, inside panel.js.
        const netWindows = new Map();
        function pruneNetWindows(at) {
            if (netWindows.size <= NET_WINDOW_MAX) return;
            for (const [key, window] of netWindows) {
                if (!isObject(window) || at >= window.end) netWindows.delete(key);
            }
        }
        function rateLimit(src) {
            const key = String(src);
            const at = Date.now();
            let window = netWindows.get(key);
            if (!window || at >= window.end) {
                window = { end: at + NET_WINDOW_MS, count: 0 };
                netWindows.set(key, window);
            }
            window.count += 1;
            pruneNetWindows(at);
            return window.count <= NET_LIMIT;
        }

        onNet('nakara_rongroi:requestCode', () => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.requestCode(src);
        });
        onNet('nakara_rongroi:panel:open', () => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.panelOpen(src);
        });
        onNet('nakara_rongroi:panel:case', (payload) => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.panelCase(src, asCaseId(payload));
        });
        onNet('nakara_rongroi:panel:openCase', (payload) => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.panelOpenCase(src, asTarget(payload));
        });
        onNet('nakara_rongroi:settings:save', (payload) => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.saveSettings(src, asSettingsPatch(payload));
        });
        onNet('nakara_rongroi:settings:open', (payload) => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.settingsOpen(src, asScreen(payload));
        });
        onNet('nakara_rongroi:settings:rotateKey', () => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.rotateKey(src);
        });
        onNet('nakara_rongroi:case:delete', (payload) => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.deleteCase(src, asCaseId(payload));
        });
        onNet('nakara_rongroi:player:delete', (payload) => {
            const src = source;
            if (!rateLimit(src)) return;
            panel.deletePlayer(src, asIdentifier(payload));
        });

        on('playerDropped', () => {
            const src = source;
            panel.playerDropped(src);
        });

        RegisterCommand('rongroi', (src) => {
            if (typeof src !== 'number' || !Number.isInteger(src) || src <= 0) return;
            if (isStaff(src)) {
                panel.panelOpen(src);
                return;
            }
            panel.requestCode(src);
        }, false);

        exports('api', (version) => (version === 1 ? {
            openCase,
            getCase,
            listCases,
            deleteCase,
            deletePlayerData,
            getPairingCode,
        } : null));
        SetHttpHandler(handler);
        setInterval(() => handler.sweep(), 10000);
    } catch {
        console.log('nakara_rongroi: startup failed');
    }
})();
