'use strict';

// Report storage (ADR 0001, sections 4 and 5). One backend stores in KVP (Legacy) and one in resource files
// (Enhanced). The index is a list of pages of at most 100 entries. An index entry is written before its case
// and removed after the case file is emptied, so a crash leaves a reachable entry, never an orphan file.

const crypto = require('crypto');

const NAME_RE = /^(case|index|report)-[0-9a-f]{1,64}$/;
const TICKET_RE = /^[0-9a-f]{32}$/;
const PAGE_SIZE = 100;

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
        for (let page = 0; ; page += 1) {
            const entries = backend.read(`index-${page}`);
            if (entries === null) return;
            pages.push(Array.isArray(entries) ? entries : []);
        }
    }

    function openCase({ caseId, ticket, openedAt, ...facts } = {}) {
        caseKey(caseId);
        if (findEntry(caseId)) throw new TypeError('case id is already open');
        let page = pages[pages.length - 1];
        if (!page || page.length >= PAGE_SIZE) pages.push(page = []);
        page.push({ caseId, ticket, openedAt, reportSha256: null, consumedAt: null });
        backend.write(`index-${pages.length - 1}`, page);
        backend.write(caseKey(caseId), { caseId, ticket, openedAt, ...facts });
    }

    function getCase(caseId) {
        return backend.read(caseKey(caseId));
    }

    function listCases({ page } = {}) {
        const entries = pages[page];
        return entries ? entries.map((entry) => ({ ...entry })) : [];
    }

    function saveReport({ caseId, ticket, reportSha256, receivedAt, record, declined } = {}) {
        const found = findEntry(caseId);
        if (!found) throw new Error('rongroi storage: case is not in the index');
        backend.writeOnce(`report-${ticket}`, declined ? { declined: true } : { record });
        const stored = backend.read(caseKey(caseId));
        const data = stored && typeof stored === 'object' && !Array.isArray(stored) ? stored : {};
        backend.write(caseKey(caseId), {
            ...data,
            caseId,
            ticket: found.entry.ticket,
            openedAt: found.entry.openedAt,
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

    function deleteCase(caseId) {
        const found = findEntry(caseId);
        if (found === null) return false;
        backend.remove(`report-${found.entry.ticket}`);
        backend.remove(caseKey(caseId));
        pages[found.page].splice(found.index, 1);
        backend.write(`index-${found.page}`, pages[found.page]);
        return true;
    }

    function consumedSnapshot() {
        const snapshot = [];
        for (const entry of entries()) {
            if (entry.consumedAt === null || entry.consumedAt === undefined) continue;
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

    return { caseKey, load, openCase, getCase, listCases, saveReport, getReport, deleteCase, consumedSnapshot, entries };
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { createKvpBackend, detectEdition, createStorage };
}
