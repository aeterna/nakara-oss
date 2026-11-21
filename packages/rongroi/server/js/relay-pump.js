'use strict';

// The Kit's side of the relay transport, kept out of main.js so it can be tested (Server Kit ADR 0001 section 14;
// aeterna-rongroi ADR 0097 section 3). One round, every few seconds:
//   1. register tickets the Relay has not confirmed yet (and again after the Relay restarted and forgot them);
//   2. post results that did not reach the Relay last time (an accepted report must not be left "pending");
//   3. pull each open relay ticket, verify every envelope with the Kit's own checks, post the result.
// Nothing here throws; a Relay that is down or slow only delays the next round.

const MAX_TICKETS_PER_ROUND = 32;

function createRelayPump({ relay, store, ingest, graceMs, log = () => {} }) {
    const toRegister = new Map(); // ticket -> { expiresAt, policyBody }
    const toResult = new Map();   // `${ticket}:${sha}` -> { ticket, sha, status }
    let cursor = 0;

    // Called when a relay code is first made for a ticket: register now and keep retrying until the Relay confirms.
    function issued({ ticket, expiresAt, policyBody }) {
        toRegister.set(ticket, { expiresAt, policyBody });
    }

    function forget(ticket) {
        toRegister.delete(ticket);
        for (const key of [...toResult.keys()]) if (key.startsWith(`${ticket}:`)) toResult.delete(key);
    }

    async function postResult(ticket, sha, status) {
        const ok = await relay.result(ticket, sha, status);
        if (ok) toResult.delete(`${ticket}:${sha}`);
        else toResult.set(`${ticket}:${sha}`, { ticket, sha, status });
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

    async function roundOnce() {
        for (const [ticket, entry] of [...toRegister]) {
            const found = store.lookup(ticket);
            if (!found || found.state !== 'issued') {
                toRegister.delete(ticket);
                continue;
            }
            if (entry.registered) continue;
            if (await relay.register({ ticket, expiresAt: entry.expiresAt, policyBody: entry.policyBody })) {
                toRegister.set(ticket, { ...entry, registered: true });
            }
        }
        for (const { ticket, sha, status } of [...toResult.values()]) await postResult(ticket, sha, status);

        const due = store.relayTickets(graceMs);
        if (due.length === 0) return;
        const count = Math.min(due.length, MAX_TICKETS_PER_ROUND);
        for (let i = 0; i < count; i += 1) {
            const ticket = due[(cursor + i) % due.length];
            const polled = await relay.poll(ticket);
            if (polled.status === 404) {
                const entry = toRegister.get(ticket);
                const found = store.lookup(ticket);
                if (entry && found && found.state === 'issued' && Date.now() < found.expiresAt) {
                    toRegister.set(ticket, { expiresAt: entry.expiresAt, policyBody: entry.policyBody });
                }
                continue;
            }
            for (const e of polled.envelopes) {
                let status = ingest({ ticket, sha: e.sha256, raw: e.raw, receivedAt: e.receivedAt,
                    address: e.address, addressSource: e.addressSource });
                if (status === 429) continue; // a slot is busy: leave it on the Relay, try next round
                if (status === 400 || status === 413) status = 422;
                if (![200, 404, 409, 410, 422, 500].includes(status)) status = 500;
                await postResult(ticket, e.sha256, status);
            }
        }
        cursor = (cursor + count) % Math.max(due.length, 1);
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
