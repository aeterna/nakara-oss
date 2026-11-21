'use strict';

// The Kit's side of the relay transport, kept out of main.js so it can be tested (Server Kit ADR 0001 section 14;
// aeterna-rongroi ADR 0097 section 3). One round, every few seconds:
//   1. register tickets the Relay has not confirmed yet (and again after the Relay restarted and forgot them);
//   2. post results that did not reach the Relay last time (an accepted report must not be left "pending");
//   3. pull each open relay ticket, verify every envelope with the Kit's own checks, post the result.
// Nothing here throws; a Relay that is down or slow only delays the next round.

const MAX_TICKETS_PER_ROUND = 32;

function createRelayPump({ relay, store, ingest, graceMs, log = () => {} }) {
    const toRegister = new Map(); // ticket -> { expiresAt, policyBody, registered }
    const toResult = new Map();   // `${ticket}:${sha}` -> { ticket, sha, status, until }
    const forgotten = new Set();  // tickets staff deleted while a round may still hold them
    let cursor = 0;
    const unreachable = () => typeof relay.unreachable === 'function' && relay.unreachable();
    const open = (found) => found && (found.state === 'issued' || found.state === 'uploading') && Date.now() < found.expiresAt;

    // Called when a relay code is first made for a ticket: register now and keep retrying until the Relay confirms.
    // The record stays while the ticket is open, so a Relay that restarts later (404 on poll) gets it again.
    function issued({ ticket, expiresAt, policyBody }) {
        forgotten.delete(ticket);
        toRegister.set(ticket, { expiresAt, policyBody, registered: false });
    }

    function forget(ticket) {
        forgotten.add(ticket);
        toRegister.delete(ticket);
        for (const key of [...toResult.keys()]) if (key.startsWith(`${ticket}:`)) toResult.delete(key);
    }

    // A result is posted until the Relay has it (relay.result says settled), at most until the ticket's grace ends.
    async function postResult(ticket, sha, status, until) {
        const key = `${ticket}:${sha}`;
        const settled = await relay.result(ticket, sha, status);
        if (settled || forgotten.has(ticket) || Date.now() >= until) toResult.delete(key);
        else toResult.set(key, { ticket, sha, status, until });
    }

    // One round at a time: a call while a round runs waits for it and then runs one more, so a code issued mid-round
    // is registered promptly and nothing is ingested twice in parallel.
    let running = null;
    let again = false;
    function round() {
        if (running) {
            again = true;
            return running;
        }
        running = (async () => {
            try {
                do {
                    again = false;
                    await roundOnce();
                } while (again);
            } finally {
                running = null;
            }
        })();
        return running;
    }

    // Each step that cannot reach the Relay ends the round (one timeout per round, not one per ticket). A step that
    // throws is logged and skipped so one bad ticket cannot block the rest.
    async function roundOnce() {
        forgotten.clear(); // no request from an earlier round is still in flight
        for (const [ticket, entry] of [...toRegister]) {
            const found = store.lookup(ticket);
            if (!open(found)) {
                toRegister.delete(ticket);
                continue;
            }
            if (entry.registered) continue;
            try {
                if (await relay.register({ ticket, expiresAt: entry.expiresAt, policyBody: entry.policyBody })) {
                    if (toRegister.has(ticket)) toRegister.set(ticket, { ...entry, registered: true });
                } else if (unreachable()) return;
            } catch {
                log('rongroi relay: register failed', ticket);
            }
        }
        for (const { ticket, sha, status, until } of [...toResult.values()]) {
            try {
                await postResult(ticket, sha, status, until);
            } catch {
                toResult.delete(`${ticket}:${sha}`);
                log('rongroi relay: result failed', ticket);
            }
            if (unreachable()) return;
        }

        const due = store.relayTickets(graceMs);
        if (due.length === 0) return;
        const count = Math.min(due.length, MAX_TICKETS_PER_ROUND);
        const start = cursor;
        cursor = (cursor + count) % due.length;
        for (let i = 0; i < count; i += 1) {
            const ticket = due[(start + i) % due.length];
            try {
                const polled = await relay.poll(ticket);
                if (polled.status === 0) return;
                if (polled.status === 404) {
                    const entry = toRegister.get(ticket);
                    if (entry && open(store.lookup(ticket))) toRegister.set(ticket, { ...entry, registered: false });
                    continue;
                }
                const until = Date.now() + graceMs;
                for (const e of polled.envelopes) {
                    if (forgotten.has(ticket)) break;
                    let status = ingest({ ticket, sha: e.sha256, raw: e.raw, receivedAt: e.receivedAt,
                        address: e.address, addressSource: e.addressSource });
                    if (status === 429) continue; // a slot is busy: leave it on the Relay, try next round
                    if (status === 400 || status === 413) status = 422;
                    if (![200, 404, 409, 410, 422, 500].includes(status)) status = 500;
                    await postResult(ticket, e.sha256, status, until);
                    if (unreachable()) return;
                }
            } catch {
                log('rongroi relay: ticket skipped this round', ticket);
            }
        }
    }

    // `entries` keeps the registration record (including `registered: true`) so a Relay restart can be repaired.
    function state() {
        return { toRegister: [...toRegister.keys()], toResult: [...toResult.keys()] };
    }

    return { issued, forget, round, state, _toRegister: toRegister };
}

if (typeof module !== 'undefined') {
    module.exports = { createRelayPump, MAX_TICKETS_PER_ROUND };
}
