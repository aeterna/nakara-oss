'use strict';

// Staff case view model (ADR 0001, section 8). Pure: the clock is the injected `now`, and nothing here
// scores, colours, ranks or otherwise judges a case. The NUI writes every string with `textContent`.

// FXServer resolves a relative require() against the resource root, not against the requiring file, so
// './record.js' only exists on plain Node. Try the file-relative path first and fall back to the
// resource-root path, as the other server modules do.
function isMissingModule(err) {
    if (!err) return false;
    return err.code === 'MODULE_NOT_FOUND' || /^Cannot find module\b/.test(err.message || '');
}

function loadRecord() {
    try {
        return require('./record.js');
    } catch (err) {
        if (!isMissingModule(err)) throw err;
        return require('./server/js/record.js');
    }
}

const { visualHashFact } = loadRecord();

const FIXED_LINE_KEY = 'rongroi.case.fixedLine';
const KNOWN_EVIDENCE_STATES = new Set(['found', 'not_found', 'unmeasured']);
const SAVED_FILE_ORIGINS = new Set(['saved_file', 'saved-file', 'savedfile', 'file', 'upload']);
const CONNECT_ORIGINS = new Set(['connect', 'live', 'http']);

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function hasOwn(value, name) {
    return isObject(value) && Object.prototype.hasOwnProperty.call(value, name);
}

// The first present member of `names`, or null when none is present.
function valueOf(value, names) {
    if (!isObject(value)) return null;
    for (const name of names) {
        if (Object.prototype.hasOwnProperty.call(value, name)) return value[name];
    }
    return null;
}

function firstDefined(left, right) {
    return left === null || left === undefined ? right : left;
}

// storage.getReport() returns { record } or { declined: true }; caseView takes the record itself.
function reportRecord(report) {
    if (!isObject(report)) return report;
    if (!isObject(report.record)) return report;
    if (hasOwn(report, 'visual_hash') || hasOwn(report, 'binding') || hasOwn(report, 'evidence')
        || hasOwn(report, 'findings') || hasOwn(report, 'scan') || hasOwn(report, 'policy')
        || hasOwn(report, 'view') || hasOwn(report, 'producer')) {
        return report;
    }
    return report.record;
}

function isDeclined(record, caseFacts) {
    if (isObject(record) && (record.scan === 'declined' || record.declined === true)) return true;
    return isObject(caseFacts) && caseFacts.state === 'declined';
}

function resolveState(caseFacts, ticketState, record, now) {
    if (isDeclined(record, caseFacts)) return 'declined';

    const factsState = valueOf(caseFacts, ['state']);
    const receivedAt = valueOf(caseFacts, ['receivedAt', 'received_at']);
    const consumedAt = valueOf(caseFacts, ['consumedAt', 'consumed_at']);
    if (isObject(record) || factsState === 'received'
        || (receivedAt !== null && receivedAt !== undefined)
        || (consumedAt !== null && consumedAt !== undefined)) {
        return 'received';
    }

    const ticket = firstDefined(ticketState, valueOf(caseFacts, ['ticketState', 'ticket_state']));
    if (ticket === 'expired' || factsState === 'expired') return 'expired';

    const expiresAt = valueOf(caseFacts, ['expiresAt', 'expires_at']);
    if (typeof expiresAt === 'number' && typeof now === 'number' && now >= expiresAt) return 'expired';
    return 'opened';
}

// The evidence rows may sit at the record top level or under scan/view.
function evidenceRows(record) {
    if (!isObject(record)) return [];
    const scan = isObject(record.scan) ? record.scan : null;
    const view = isObject(record.view) ? record.view : null;
    const candidates = [
        record.evidence,
        record.findings,
        scan ? scan.evidence : undefined,
        scan ? scan.findings : undefined,
        view ? view.evidence : undefined,
        view ? view.findings : undefined,
        record.results,
    ];
    for (const candidate of candidates) {
        if (Array.isArray(candidate)) return candidate;
    }
    return [];
}

function evidenceState(row) {
    const nested = isObject(row.state) ? row.state : null;
    const value = nested ? nested.state : row.state;
    return typeof value === 'string' && KNOWN_EVIDENCE_STATES.has(value) ? value : 'unknown';
}

function reasonOf(row) {
    if (hasOwn(row, 'reason')) return { present: true, value: row.reason };
    if (isObject(row.state) && hasOwn(row.state, 'reason')) {
        return { present: true, value: row.state.reason };
    }
    return { present: false, value: null };
}

function findingOf(row) {
    const finding = {
        rule_id: valueOf(row, ['rule_id', 'ruleId']),
        collector: valueOf(row, ['collector']),
        strength: valueOf(row, ['strength']),
        state: evidenceState(row),
    };
    const reason = reasonOf(row);
    if (reason.present) finding.reason = reason.value;
    return finding;
}

function findingsOf(record) {
    return evidenceRows(record).map((row) => findingOf(isObject(row) ? row : {}));
}

function policyOf(caseFacts, record) {
    const fromCase = isObject(caseFacts) && isObject(caseFacts.policy) ? caseFacts.policy : null;
    const fromReport = isObject(record) && isObject(record.policy) ? record.policy : null;
    const source = fromCase || fromReport || {};
    const collectors = valueOf(source, ['required_collectors', 'collectors', 'collectorList']);
    const elevation = valueOf(source, ['require_elevation', 'elevation']);
    return {
        profile: valueOf(source, ['profile']),
        collectors: Array.isArray(collectors) ? collectors.slice() : [],
        elevation: typeof elevation === 'boolean' ? elevation : null,
        serverName: valueOf(source, ['server_name', 'serverName']),
    };
}

function selfAssertedOf(record) {
    const binding = isObject(record) && isObject(record.binding) ? record.binding : {};
    const issuedAt = valueOf(binding, ['issued_at', 'issuedAt']);
    const expiresAt = valueOf(binding, ['expires_at', 'expiresAt']);
    return {
        official_build: valueOf(record, ['official_build', 'officialBuild']),
        producer: valueOf(record, ['producer']),
        rongroi_version: valueOf(record, ['rongroi_version', 'rongroiVersion']),
        issued_at: firstDefined(issuedAt, valueOf(record, ['issued_at', 'issuedAt'])),
        expires_at: firstDefined(expiresAt, valueOf(record, ['expires_at', 'expiresAt'])),
    };
}

function normalizeOrigin(value) {
    if (typeof value !== 'string') return null;
    const key = value.toLowerCase();
    if (SAVED_FILE_ORIGINS.has(key)) return 'saved_file';
    if (CONNECT_ORIGINS.has(key)) return 'connect';
    return null;
}

function originOf(caseFacts, record) {
    for (const source of [caseFacts, record]) {
        if (!isObject(source)) continue;
        for (const name of ['origin', 'source', 'transport', 'uploadedFrom', 'uploaded_from']) {
            if (hasOwn(source, name)) {
                const origin = normalizeOrigin(source[name]);
                if (origin !== null) return origin;
            }
        }
        if (source.saved_file === true || source.savedFile === true
            || source.uploadedFromFile === true || source.uploaded_from_file === true) {
            return 'saved_file';
        }
    }
    const producer = isObject(record) && isObject(record.producer) ? record.producer : null;
    if (producer) {
        for (const name of ['mode', 'name', 'kind']) {
            const value = valueOf(producer, [name]);
            const origin = normalizeOrigin(value);
            if (origin !== null) return origin;
            if (typeof value === 'string' && /saved|upload|file/i.test(value)) return 'saved_file';
        }
    }
    // Connect requires schema 2 with a binding (ADR 0001, section 12).
    if (isObject(record) && record.schema === 1 && !isObject(record.binding)) return 'saved_file';
    return 'connect';
}

function caseView(input) {
    const { caseFacts, ticketState, report, now } = input || {};
    const record = reportRecord(report);
    const declined = isDeclined(record, caseFacts);
    const receivedAt = valueOf(caseFacts, ['receivedAt', 'received_at']);

    return {
        fixedLineKey: FIXED_LINE_KEY,
        facts: {
            openedBy: valueOf(caseFacts, ['openedBy', 'opened_by']),
            openedAt: valueOf(caseFacts, ['openedAt', 'opened_at']),
            ticketState: firstDefined(ticketState, valueOf(caseFacts, ['ticketState', 'ticket_state'])),
            receivedAt: firstDefined(receivedAt, valueOf(record, ['receivedAt', 'received_at'])),
            uploaderAddress: valueOf(caseFacts, ['uploaderAddress', 'uploader_address', 'uploader']),
            connectAddress: valueOf(caseFacts, ['connectAddress', 'connect_address', 'playerAddress', 'player_address']),
        },
        selfAsserted: selfAssertedOf(record),
        policy: policyOf(caseFacts, record),
        findings: declined ? [] : findingsOf(record),
        visualHash: declined
            ? { recorded: null, recomputed: null, equal: null }
            : visualHashFact(record),
        state: resolveState(caseFacts, ticketState, record, now),
        origin: originOf(caseFacts, record),
    };
}

function caseList(entries) {
    if (!Array.isArray(entries)) return [];
    return entries.map((entry) => {
        const source = isObject(entry) ? entry : {};
        const facts = isObject(source.facts) ? source.facts : source;
        const combined = facts === source ? source : { ...source, ...facts };
        const record = reportRecord(source.report);
        const declared = source.state;
        const state = declared === 'opened' || declared === 'received'
            || declared === 'declined' || declared === 'expired'
            ? declared
            : resolveState(combined, valueOf(source, ['ticketState', 'ticket_state']), record, undefined);
        return {
            caseId: firstDefined(valueOf(source, ['caseId', 'case_id']), valueOf(facts, ['caseId', 'case_id'])),
            openedBy: firstDefined(valueOf(facts, ['openedBy', 'opened_by']), valueOf(source, ['openedBy', 'opened_by'])),
            openedAt: firstDefined(valueOf(facts, ['openedAt', 'opened_at']), valueOf(source, ['openedAt', 'opened_at'])),
            state,
            receivedAt: firstDefined(
                valueOf(facts, ['receivedAt', 'received_at']),
                firstDefined(
                    valueOf(source, ['receivedAt', 'received_at']),
                    valueOf(source, ['consumedAt', 'consumed_at']),
                ),
            ),
            origin: originOf(combined, record),
        };
    });
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { caseList, caseView };
}
