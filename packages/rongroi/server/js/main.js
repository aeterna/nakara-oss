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

    const { createHandler } = loadModule(
        () => require('./http.js'),
        () => require('./server/js/http.js'),
    );
    const { loadOrCreateKitKey } = loadModule(
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
    const crypto = require('crypto');

    function log(...parts) {
        console.log(`nakara_rongroi: ${parts.join(' ')}`);
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

        // One case every 250 ms: a storage write blocks the tick, and Enhanced's writes are the slowest
        // (ADR 0001, section 4). A second sweep waits for the running one.
        let retentionRunning = false;

        function runRetention() {
            if (retentionRunning) return;
            retentionRunning = true;
            const storedDays = GetResourceKvpString('rongroi:settings:retentionDays');
            const days = clampDays(
                storedDays === null || storedDays === undefined ? undefined : Number(storedDays),
            );
            const due = dueCases(storage.entries(), Date.now(), days);
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
                    if (storage.deleteCase(caseId)) removed += 1;
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
            const issued = store.issue({ caseId, policy, ttlMs });
            storage.openCase({ caseId, ticket: issued.ticket, openedAt: issued.issuedAt });
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
        }

        exports('api', (version) => (version === 1 ? { openCase } : null));
        SetHttpHandler(handler);
        setInterval(() => handler.sweep(), 10000);
    } catch {
        console.log('nakara_rongroi: startup failed');
    }
})();
