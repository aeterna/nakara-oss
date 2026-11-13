'use strict';

// Report storage (ADR 0001, sections 4 and 5). One backend stores in KVP (Legacy) and one in resource files
// (Enhanced). The index is a list of pages of at most 100 entries. An index entry is written before its case
// and removed after the case file is emptied, so a crash leaves a reachable entry, never an orphan file.

const crypto = require('crypto');

const NAME_RE = /^(case|index|report)-[0-9a-f]{1,64}$/;
const TICKET_RE = /^[0-9a-f]{32}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const PAGE_SIZE = 100;
const EMPTY_RUN = 16;

function checkName(name) {
    if (typeof name !== 'string' || !NAME_RE.test(name)) {
        throw new TypeError('name must be case-, index- or report- followed by 1 to 64 lowercase hex characters');
    }
}

function createKvpBackend({ get, set, del } = {}) {
    if (typeof get !== 'function' || typeof set !== 'function' || typeof del !== 'function') {
        throw new TypeError('kvp backend needs get, set and del functions');
    }
    function key(name) {
        checkName(name);
        return `rongroi:${name.replace('-', ':')}`;
    }
    function read(name) {
        const stored = get(key(name));
        if (typeof stored !== 'string') return null;
        try {
            return JSON.parse(stored);
        } catch {
            return null;
        }
    }
    function write(name, obj) {
        set(key(name), JSON.stringify(obj));
    }
    const writeOnce = write;
    function remove(name) {
        del(key(name));
    }
    return { read, write, writeOnce, remove };
}

function detectEdition(getConvar) {
    if (typeof getConvar !== 'function') throw new TypeError('getConvar must be a function');
    return getConvar('gamename', '') === 'gta5enhanced' ? 'enhanced' : 'legacy';
}

function createStorage(backend) {
    if (!backend || typeof backend.read !== 'function' || typeof backend.write !== 'function'
        || typeof backend.writeOnce !== 'function' || typeof backend.remove !== 'function') {
        throw new TypeError('storage needs a backend with read, write, writeOnce and remove');
    }
    const pages = [];
    const damagedPages = new Set();

    function caseKey(caseId) {
        if (typeof caseId !== 'string' || caseId.length === 0) throw new TypeError('caseId must be a non-empty string');
        return `case-${crypto.createHash('sha256').update(caseId).digest('hex').slice(0, 32)}`;
    }

    function findEntry(caseId) {
        for (let page = 0; page < pages.length; page += 1) {
            const index = pages[page].findIndex((entry) => entry.caseId === caseId);
            if (index !== -1) return { page, index, entry: pages[page][index] };
        }
        return null;
    }
    function load() {
        pages.length = 0;
        damagedPages.clear();
        let pending = 0; // consecutive missing page numbers, kept only if a later page exists
        for (let page = 0; ; page += 1) {
            const entries = backend.read(`index-${page}`);
            if (entries === null) {
                pending += 1;
                if (pending >= EMPTY_RUN) break;
                continue;
            }
            while (pending > 0) {
                damagedPages.add(pages.length);
                pages.push([]);
                pending -= 1;
            }
            if (Array.isArray(entries)) {
                pages.push(entries);
            } else {
                damagedPages.add(pages.length);
                pages.push([]);
            }
        }
        return { damaged: damagedPages.size };
    }

    function openCase({ caseId, ticket, openedAt, ...facts } = {}) {
        caseKey(caseId);
        if (findEntry(caseId)) throw new TypeError('case id is already open');
        let page = pages[pages.length - 1];
        let addedPage = false;
        if (!page || page.length >= PAGE_SIZE || damagedPages.has(pages.length - 1)) {
            pages.push(page = []);
            addedPage = true;
        }
        page.push({ caseId, ticket, openedAt, reportSha256: null, consumedAt: null });
        try {
            backend.write(`index-${pages.length - 1}`, page);
        } catch (err) {
            page.pop();
            if (addedPage) pages.pop();
            throw err;
        }
        backend.write(caseKey(caseId), { caseId, ticket, openedAt, ...facts });
    }

    function getCase(caseId) {
        return backend.read(caseKey(caseId));
    }

    function hasCase(caseId) {
        return findEntry(caseId) !== null;
    }

    function listCases({ page } = {}) {
        const entries = pages[page];
        return entries ? entries.map((entry) => ({ ...entry })) : [];
    }

    function saveReport({ caseId, ticket, reportSha256, receivedAt, record, declined, address } = {}) {
        const found = findEntry(caseId);
        if (!found) throw new Error('rongroi storage: case is not in the index');
        if (ticket !== found.entry.ticket) {
            throw new Error('rongroi storage: ticket does not match the case');
        }
        backend.writeOnce(`report-${ticket}`, declined ? { declined: true } : { record });
        const stored = backend.read(caseKey(caseId));
        const data = stored && typeof stored === 'object' && !Array.isArray(stored) ? stored : {};
        // The uploader's address is kept as given: its shape differs between FXServer editions.
        const addressFacts = typeof address === 'string'
            ? { address, address_edition_form: 'as_given' }
            : {};
        backend.write(caseKey(caseId), {
            ...data,
            caseId,
            ticket: found.entry.ticket,
            openedAt: found.entry.openedAt,
            ...addressFacts,
            state: declined ? 'declined' : 'received',
            receivedAt,
        });
        found.entry.reportSha256 = reportSha256;
        found.entry.consumedAt = receivedAt;
        backend.write(`index-${found.page}`, pages[found.page]);
    }

    function getReport(ticket) {
        if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)) throw new TypeError('ticket must be 32 lowercase hex characters');
        return backend.read(`report-${ticket}`);
    }

    // Delete one case and return its ticket so the caller can forget it in the ticket store. Returns false
    // when the case is not in the index.
    function deleteCase(caseId) {
        const found = findEntry(caseId);
        if (found === null) return false;
        const remaining = pages[found.page].slice();
        remaining.splice(found.index, 1);
        backend.remove(`report-${found.entry.ticket}`);
        backend.remove(caseKey(caseId));
        backend.write(`index-${found.page}`, remaining);
        pages[found.page] = remaining;
        return found.entry.ticket;
    }

    // The case ids whose case file carries this identifier. An unknown identifier returns no cases.
    function casesByIdentifier(identifier) {
        if (typeof identifier !== 'string' || identifier.length === 0) {
            throw new TypeError('identifier must be a non-empty string');
        }
        const found = [];
        for (const entry of entries()) {
            if (typeof entry.caseId !== 'string' || entry.caseId.length === 0) continue;
            const data = getCase(entry.caseId);
            if (data !== null && typeof data === 'object' && !Array.isArray(data)
                && data.identifier === identifier) {
                found.push(entry.caseId);
            }
        }
        return found;
    }

    // Delete every case of one identifier and return the tickets the caller must forget.
    function deletePlayerData(identifier) {
        const tickets = [];
        for (const caseId of casesByIdentifier(identifier)) {
            const ticket = deleteCase(caseId);
            if (ticket !== false) tickets.push(ticket);
        }
        return tickets;
    }

    function consumedSnapshot() {
        const snapshot = [];
        for (const entry of entries()) {
            if (entry.consumedAt === null || entry.consumedAt === undefined) continue;
            if (typeof entry.ticket !== 'string' || !TICKET_RE.test(entry.ticket)) continue;
            if (typeof entry.reportSha256 !== 'string' || !SHA256_RE.test(entry.reportSha256)) continue;
            if (typeof entry.consumedAt !== 'number' || !Number.isFinite(entry.consumedAt)) continue;
            if (typeof entry.caseId !== 'string' || entry.caseId.length === 0) continue;
            snapshot.push({
                ticket: entry.ticket,
                caseId: entry.caseId,
                reportSha256: entry.reportSha256,
                consumedAt: entry.consumedAt,
            });
        }
        return snapshot;
    }

    function entries() {
        const all = [];
        for (const page of pages) {
            for (const entry of page) all.push({ ...entry });
        }
        return all;
    }

    return {
        caseKey,
        load,
        openCase,
        getCase,
        hasCase,
        listCases,
        saveReport,
        getReport,
        deleteCase,
        casesByIdentifier,
        deletePlayerData,
        consumedSnapshot,
        entries,
    };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { createKvpBackend, detectEdition, createStorage };
}
