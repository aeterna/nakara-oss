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

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function hasOwn(value, name) {
    return isObject(value) && Object.prototype.hasOwnProperty.call(value, name);
}

// The named member of an object, or null when it is absent.
function member(value, name) {
    return hasOwn(value, name) ? value[name] : null;
}

// storage.getReport() returns { record }, { declined: true } or null.
function reportRecord(report) {
    return isObject(report) && isObject(report.record) ? report.record : null;
}

function isDeclined(report, caseFacts) {
    return (isObject(report) && report.declined === true)
        || (isObject(caseFacts) && caseFacts.state === 'declined');
}

function resolveState(caseFacts, ticketState, record, report, now) {
    if (isDeclined(report, caseFacts)) return 'declined';
    if (isObject(record) || (isObject(caseFacts) && caseFacts.state === 'received')) return 'received';
    if (ticketState === 'expired') return 'expired';

    const expiresAt = member(caseFacts, 'expiresAt');
    if (typeof expiresAt === 'number' && typeof now === 'number' && now >= expiresAt) return 'expired';
    return 'opened';
}

// Schema 2 evidence rows are flat members of record.view.evidence.
function evidenceRows(record) {
    if (!isObject(record) || !isObject(record.view) || !Array.isArray(record.view.evidence)) return [];
    return record.view.evidence;
}

function evidenceState(row) {
    const value = member(row, 'state');
    return typeof value === 'string' && KNOWN_EVIDENCE_STATES.has(value) ? value : 'unknown';
}

function findingOf(row) {
    const finding = {
        rule_id: member(row, 'rule_id'),
        collector: member(row, 'collector'),
        strength: member(row, 'strength'),
        state: evidenceState(row),
    };
    if (hasOwn(row, 'reason')) finding.reason = row.reason;
    return finding;
}

function findingsOf(record) {
    return evidenceRows(record).map((row) => findingOf(isObject(row) ? row : {}));
}

function policyOf(caseFacts, record) {
    const fromCase = isObject(caseFacts) && isObject(caseFacts.policy) ? caseFacts.policy : null;
    const fromReport = isObject(record) && isObject(record.policy) ? record.policy : null;
    const source = fromCase || fromReport || {};
    const collectors = member(source, 'required_collectors');
    const elevation = member(source, 'require_elevation');
    return {
        profile: member(source, 'profile'),
        collectors: Array.isArray(collectors) ? collectors.slice() : [],
        elevation: typeof elevation === 'boolean' ? elevation : null,
        serverName: member(source, 'server_name'),
    };
}

function selfAssertedOf(record) {
    const binding = isObject(record) && isObject(record.binding) ? record.binding : {};
    return {
        official_build: member(record, 'official_build'),
        producer: member(record, 'producer'),
        rongroi_version: member(record, 'rongroi_version'),
        issued_at: member(binding, 'issued_at'),
        expires_at: member(binding, 'expires_at'),
    };
}

// The record is written by the player's machine, so it can never choose the origin.
function originOf(caseFacts) {
    return isObject(caseFacts) && caseFacts.origin === 'saved_file' ? 'saved_file' : 'connect';
}

function caseView(input) {
    const { caseFacts, ticketState, report, now } = input || {};
    const record = reportRecord(report);
    const declined = isDeclined(report, caseFacts);

    return {
        fixedLineKey: FIXED_LINE_KEY,
        facts: {
            openedBy: member(caseFacts, 'openedBy'),
            openedAt: member(caseFacts, 'openedAt'),
            ticketState: ticketState === undefined ? null : ticketState,
            receivedAt: member(caseFacts, 'receivedAt'),
            uploaderAddress: member(caseFacts, 'address'),
            connectAddress: member(caseFacts, 'connectAddress'),
        },
        selfAsserted: selfAssertedOf(record),
        policy: policyOf(caseFacts, record),
        findings: declined ? [] : findingsOf(record),
        visualHash: declined
            ? { recorded: null, recomputed: null, equal: null }
            : visualHashFact(record),
        state: resolveState(caseFacts, ticketState, record, report, now),
        origin: originOf(caseFacts),
    };
}

// storage.listCases() rows already carry the fields the list shows.
function caseList(entries) {
    if (!Array.isArray(entries)) return [];
    return entries.map((entry) => {
        const source = isObject(entry) ? entry : {};
        return {
            caseId: member(source, 'caseId'),
            openedBy: member(source, 'openedBy'),
            openedAt: member(source, 'openedAt'),
            state: member(source, 'state'),
            receivedAt: member(source, 'receivedAt'),
            origin: member(source, 'origin'),
        };
    });
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the export.
if (typeof module !== 'undefined') {
    module.exports = { caseList, caseView };
}
