'use strict';

// Pairing ticket store (aeterna-rongroi ADR 0089, section 5; ADR 0001, sections 3 and 6). One ticket is
// minted per case and travels inside the pairing code; it is the HKDF salt and the envelope's additional
// data. Pure JS: the clock and the random source are injected as { now, randomBytes }, so the specs run in
// plain Node with no FXServer natives and no crypto import here.
//
// States, exactly as ADR 0089 section 5: issued -> uploading when beginUpload() accepts a direct POST or a
// first slice, only while the server's clock is before expires_at; uploading -> issued when drop() or the
// 60 s idle limit removed the ticket's last open buffer (a failed upload never consumes the ticket);
// issued -> expired at expires_at by the server's clock, never while uploading (an upload that started in
// time may finish past expires_at, bounded by the idle limit instead); -> consumed only by consume(), which
// the handler calls only after the envelope authenticates and the record's nonce matches. At most 2 open
// uploads per ticket, 16 in total. A consumed ticket is kept with its case: any further upload gets 409,
// unless it repeats the accepted envelope and gets 200 again. A restart drops issued and uploading tickets;
// the caller persists consumed ones with snapshotConsumed() and feeds them back with restoreConsumed().

const TICKET_RE = /^[0-9a-f]{32}$/;
const SHA256_RE = /^[0-9a-f]{64}$/;
const TICKET_BYTES = 16;       // 128 bits of ticket, 32 lowercase hex characters
const NONCE_BYTES = 6;         // 12 hex characters, compared with the record's nonce
const DEFAULT_TTL_MS = 300000; // 5 minutes (ADR 0001, section 3)
const IDLE_MS = 60000;         // a buffer is dropped after 60 s with no new slice
const MAX_OPEN_PER_TICKET = 2;
const MAX_OPEN_TOTAL = 16;

// Bad arguments throw a TypeError, the same contract the envelope module uses for its key parameters.
function checkTicket(ticket) {
    if (typeof ticket !== 'string' || !TICKET_RE.test(ticket)) {
        throw new TypeError('ticket must be 32 lowercase hex characters');
    }
}

function checkReportSha256(reportSha256) {
    if (typeof reportSha256 !== 'string' || !SHA256_RE.test(reportSha256)) {
        throw new TypeError('reportSha256 must be 64 lowercase hex characters');
    }
}

class TicketStore {
    constructor(adapter) {
        if (adapter === null || typeof adapter !== 'object'
            || typeof adapter.now !== 'function' || typeof adapter.randomBytes !== 'function') {
            throw new TypeError('TicketStore needs an adapter { now: () => ms, randomBytes }');
        }
        this.now = adapter.now;
        this.randomBytes = adapter.randomBytes;
        this.tickets = new Map(); // ticket -> record
        this.uploads = new Map(); // uploadId -> { ticket, lastActivity }
        this.nextUploadId = 1;
    }

    // Mint one ticket for a case. Returns { ticket, nonce, issuedAt, expiresAt }.
    issue({ caseId, policy, ttlMs = DEFAULT_TTL_MS } = {}) {
        if (typeof caseId !== 'string' || caseId.length === 0) {
            throw new TypeError('caseId must be a non-empty string');
        }
        if (policy === null || typeof policy !== 'object' || Array.isArray(policy)) {
            throw new TypeError('policy must be an object');
        }
        if (typeof ttlMs !== 'number' || !Number.isFinite(ttlMs) || ttlMs <= 0) {
            throw new TypeError('ttlMs must be a positive number of milliseconds');
        }
        const issuedAt = this.now();
        let ticket;
        do {
            ticket = this.randomBytes(TICKET_BYTES).toString('hex');
        } while (this.tickets.has(ticket));
        const record = {
            state: 'issued',
            caseId,
            policy,
            nonce: this.randomBytes(NONCE_BYTES).toString('hex'),
            issuedAt,
            expiresAt: issuedAt + ttlMs,
            reportSha256: null,
            consumedAt: null,
        };
        this.tickets.set(ticket, record);
        return { ticket, nonce: record.nonce, issuedAt, expiresAt: record.expiresAt };
    }

    // Accept a direct POST or a slice for the ticket. Statuses follow the ADR 0089 table:
    //   { ok: true,  status: 200, uploadId }    a new open upload; the ticket is now uploading
    //   { ok: true,  status: 200, repeat }      consumed ticket repeating the accepted envelope
    //   { ok: false, status: 404|410|409|429 }  unknown, expired, consumed by another envelope, capped
    beginUpload(ticket, reportSha256) {
        checkTicket(ticket);
        checkReportSha256(reportSha256);
        const record = this.tickets.get(ticket);
        if (!record) return { ok: false, status: 404 };
        if (record.state === 'consumed') {
            if (record.reportSha256 === reportSha256) return { ok: true, status: 200, repeat: true };
            return { ok: false, status: 409 };
        }
        if (record.state === 'expired') return { ok: false, status: 410 };
        if (this.now() >= record.expiresAt) {
            record.state = 'expired';
            return { ok: false, status: 410 };
        }
        const capped = this.openForTicket(ticket) >= MAX_OPEN_PER_TICKET
            || this.uploads.size >= MAX_OPEN_TOTAL;
        if (capped) return { ok: false, status: 429 };
        const uploadId = this.nextUploadId;
        this.nextUploadId += 1;
        this.uploads.set(uploadId, { ticket, lastActivity: this.now() });
        record.state = 'uploading';
        return { ok: true, status: 200, uploadId };
    }

    openForTicket(ticket) {
        let open = 0;
        for (const upload of this.uploads.values()) {
            if (upload.ticket === ticket) open += 1;
        }
        return open;
    }

    // Mark activity on a slice: true while the upload is still open, false when the buffer is gone.
    touch(uploadId) {
        const upload = this.uploads.get(uploadId);
        if (!upload) return false;
        upload.lastActivity = this.now();
        return true;
    }

    // Drop one open upload (a 422, an envelope that does not authenticate, a finished direct POST).
    // Idempotent.
    drop(uploadId) {
        const upload = this.uploads.get(uploadId);
        if (!upload) return false;
        this.uploads.delete(uploadId);
        this.settle(upload.ticket);
        return true;
    }

    // uploading -> issued when the ticket has no open buffer left, or expired when the clock passed
    // expires_at while the upload ran.
    settle(ticket) {
        for (const upload of this.uploads.values()) {
            if (upload.ticket === ticket) return;
        }
        const record = this.tickets.get(ticket);
        if (record && record.state === 'uploading') {
            record.state = this.now() >= record.expiresAt ? 'expired' : 'issued';
        }
    }

    // Consume the ticket once the envelope authenticated and the nonce matched. Like beginUpload, with the
    // ADR 0089 statuses:
    //   { ok: true,  status: 200, caseId, policy, dropped }  the ticket is now consumed; dropped lists the
    //                                                        open uploads the handler must free
    //   { ok: true,  status: 200, repeat, caseId, policy }   already consumed with the same envelope
    //   { ok: false, status: 404|410|409 }
    consume(ticket, reportSha256) {
        checkTicket(ticket);
        checkReportSha256(reportSha256);
        const record = this.tickets.get(ticket);
        if (!record) return { ok: false, status: 404 };
        if (record.state === 'expired') return { ok: false, status: 410 };
        if (record.state === 'consumed') {
            if (record.reportSha256 === reportSha256) {
                return { ok: true, status: 200, repeat: true, caseId: record.caseId, policy: record.policy };
            }
            return { ok: false, status: 409 };
        }
        record.state = 'consumed';
        record.reportSha256 = reportSha256;
        record.consumedAt = this.now();
        return {
            ok: true,
            status: 200,
            caseId: record.caseId,
            policy: record.policy,
            dropped: this.dropTicketUploads(ticket),
        };
    }

    // Drop every open upload of one ticket and return their ids.
    dropTicketUploads(ticket) {
        const dropped = [];
        for (const [uploadId, upload] of this.uploads) {
            if (upload.ticket === ticket) {
                this.uploads.delete(uploadId);
                dropped.push(uploadId);
            }
        }
        return dropped;
    }

    // issued -> expired at expires_at, by the server's clock. Returns the number of tickets expired.
    expireDue() {
        const now = this.now();
        let expired = 0;
        for (const record of this.tickets.values()) {
            if (record.state === 'issued' && now >= record.expiresAt) {
                record.state = 'expired';
                expired += 1;
            }
        }
        return expired;
    }

    // Drop every open buffer idle for IDLE_MS with no new slice. Returns the dropped upload ids so the
    // caller can free its reassembly bytes; tickets left without open buffers go uploading -> issued.
    sweepIdle() {
        const now = this.now();
        const dropped = [];
        const idleTickets = new Set();
        for (const [uploadId, upload] of this.uploads) {
            if (now >= upload.lastActivity + IDLE_MS) {
                idleTickets.add(upload.ticket);
                this.uploads.delete(uploadId);
                dropped.push(uploadId);
            }
        }
        for (const ticket of idleTickets) this.settle(ticket);
        return dropped;
    }

    // The ticket's state ('issued', 'uploading', 'consumed', 'expired') or 'unknown'. The case view shows
    // it as a fact (ADR 0001, section 8).
    stateOf(ticket) {
        const record = this.tickets.get(ticket);
        return record ? record.state : 'unknown';
    }

    // The consumed tickets as plain JSON, for the caller to persist (KVP or a resource-folder file).
    snapshotConsumed() {
        const snapshot = [];
        for (const [ticket, record] of this.tickets) {
            if (record.state !== 'consumed') continue;
            snapshot.push({
                ticket,
                caseId: record.caseId,
                reportSha256: record.reportSha256,
                consumedAt: record.consumedAt,
            });
        }
        return snapshot;
    }

    // Restore a snapshot taken before a restart, so a reuse still gets 409 and a repeat still gets 200.
    // Every entry is validated before anything is applied; a bad entry throws a TypeError.
    restoreConsumed(snapshot) {
        if (!Array.isArray(snapshot)) throw new TypeError('snapshot must be an array');
        const entries = snapshot.map((entry) => {
            if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
                throw new TypeError('snapshot entries must be objects');
            }
            checkTicket(entry.ticket);
            checkReportSha256(entry.reportSha256);
            if (typeof entry.caseId !== 'string' || entry.caseId.length === 0) {
                throw new TypeError('snapshot caseId must be a non-empty string');
            }
            if (typeof entry.consumedAt !== 'number' || !Number.isFinite(entry.consumedAt)) {
                throw new TypeError('snapshot consumedAt must be a number of milliseconds');
            }
            return entry;
        });
        for (const entry of entries) {
            if (this.tickets.has(entry.ticket)) {
                throw new TypeError('snapshot ticket is already known to the store');
            }
        }
        for (const entry of entries) {
            this.tickets.set(entry.ticket, {
                state: 'consumed',
                caseId: entry.caseId,
                policy: null,
                nonce: null,
                issuedAt: null,
                expiresAt: null,
                reportSha256: entry.reportSha256,
                consumedAt: entry.consumedAt,
            });
        }
    }
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { TicketStore };
}
