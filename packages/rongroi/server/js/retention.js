'use strict';

// Retention sweep (ADR 0001, sections 4 and 5). Pure JS: the clock and the entries are passed in, so the
// specs run in plain Node with no FXServer natives and nothing here touches storage.
const DAY_MS = 86400000;
const DEFAULT_DAYS = 30;
const MIN_DAYS = 1;
const MAX_DAYS = 365;

// A retention setting in days: 1 to 365, default 30 for anything that is not a finite number, fractions floor.
function clampDays(value) {
    if (typeof value !== 'number' || !Number.isFinite(value)) return DEFAULT_DAYS;
    return Math.min(MAX_DAYS, Math.max(MIN_DAYS, Math.floor(value)));
}

// The caseIds whose last activity is at least `days` days before `now`. An entry uses consumedAt, or openedAt
// when consumedAt is null; an entry with neither is left out.
function dueCases(entries, now, days) {
    const due = [];
    for (const entry of entries) {
        const at = entry.consumedAt === null || entry.consumedAt === undefined
            ? entry.openedAt
            : entry.consumedAt;
        if (typeof at !== 'number' || !Number.isFinite(at)) continue;
        if (now - at >= days * DAY_MS) due.push(entry.caseId);
    }
    return due;
}

// Loaded directly as a server_script FXServer provides no CommonJS `module`; the specs still get the exports.
if (typeof module !== 'undefined') {
    module.exports = { clampDays, dueCases };
}
