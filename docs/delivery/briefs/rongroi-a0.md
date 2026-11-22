# Rongroi Kit A0 · reports that vanish after a folder-replacing update

Plan row A0 (https://claude.ai/artifact/1DX1TpQ6EXf2vixS6dbB26) · decision: `docs/adr/0001-rongroi-server-kit.md` §14 item 4.
Use file tools only; do not run shell commands. Scratch files only in `$TMPDIR`, never in the repo. Never print keys.
HARD LIMIT: the whole patch stays under 300 changed lines. Only files under `packages/rongroi/`.

## Problem (measured)

On Enhanced the file backend (`server/js/filestore.js`) keeps **both** the case/report files **and** the index pages
(`index-<n>`) in `cache/rongroi-reports/` inside the resource folder. Spike S7 (2026-11-21, FXServer b177) showed
`SaveResourceFile` cannot write into another resource, so the files must stay there. When an owner updates the Kit by
replacing the folder, the index is gone too, and `storage.load()` sees zero cases: every stored report disappears with
no message. KVP survives a folder replace (it belongs to the resource name, not the folder).

## Deliverables (new names this patch adds)

1. `server/js/storage.js` — `createStorage(backend, { marker } = {})`. `marker` is optional `{ get(): number|null,
   set(n: number): void }`. When given, after every successful index page write (open, delete, any index change) call
   `marker.set(<total entries across all pages>)`. New method `checkIntegrity()` returning
   `{ expected, found, missingCaseFiles }`: `expected` = `marker.get()` (or `null` without a marker), `found` = total
   index entries after `load()`, `missingCaseFiles` = number of index entries whose case file reads `null`.
   New method `forgetMissing()`: removes index entries whose case file reads `null` (writing the affected pages), then
   sets the marker to the new total; returns the number removed. Without a marker both still work (`expected: null`).
2. `server/js/main.js` — for the **file backend only**, build the marker on KVP key `rongroi:filestore:entries`
   (string of a non-negative integer; anything else reads as `null`) and pass it to `createStorage`. After `load()`,
   call `checkIntegrity()`. When `expected > found` or `missingCaseFiles > 0`, log one line:
   `stored reports missing: expected <e>, found <f>, case files missing <m> — was the folder replaced without cache/?`
   and pass `storageWarning: { expected, found, missingCaseFiles }` to `createPanel`. Otherwise pass `null`.
   On a first start with no marker and an empty index, write the marker as `0`; with no marker and a non-empty index,
   write the current total (an upgrade from a Kit without the marker is not a loss).
3. `server/js/panel.js` — `createPanel` accepts `storageWarning`; the staff panel payload (`nakara_rongroi:panel:data`)
   carries it as `storageWarning`. New staff action `forgetMissingReports(src)`: staff only (same check as the other
   staff actions), rate-limited like them, calls `storage.forgetMissing()`, clears `storageWarning`, and replies with
   fresh panel data. Wire it to a new net event `nakara_rongroi:panel:forgetMissing` in `main.js` like the existing
   staff events, and add the event to `oss.json` next to the other `panel:*` events.
4. `web/ui/cases.js` + `web/ui/strings/case.js` — when the payload has `storageWarning`, show one banner above the case
   list with the counts and a button that sends `forgetMissing` (follow how existing buttons post events; set text with `textContent` only, never `innerHTML`). Strings in
   `en` and `th`:
   - en: "{n} stored reports are missing. The Kit folder was probably replaced without cache/. The reports cannot be
     recovered from here." · button "Remove the missing entries"
   - th: "รายงานที่บันทึกไว้หายไป {n} รายการ น่าจะเป็นเพราะแทนโฟลเดอร์ Kit โดยไม่ได้เก็บ cache/ ไว้ กู้คืนจากหน้านี้ไม่ได้"
     · ปุ่ม "ลบรายการที่หายไป"
   `{n}` = `max(expected - found, 0) + missingCaseFiles`. No verdict words, no colour that implies a PC result.

## Tests first (write them before the code; each must fail on the current code)

In `spec/storage.test.js` (file backend with a fake native, as the existing tests do) and `spec/panel.test.js`:
- marker is set to the total after open and after delete; `checkIntegrity()` reports `expected` 3 / `found` 0 when the
  index files are wiped but the marker says 3; reports `missingCaseFiles` 1 when one case file is emptied.
- `forgetMissing()` removes exactly the entries without a case file, rewrites the marker, and leaves the others.
- without a marker, `checkIntegrity().expected === null` and nothing throws.
- panel: `storageWarning` appears in panel data; `forgetMissingReports` from a non-staff source is refused; from staff
  it calls `forgetMissing` and the next panel data has `storageWarning: null`.
- every test file still reaches its final summary line; the full `npm test -w packages/rongroi` passes.

## Out of scope

The update script, README text and ADR wording (the Orchestrator writes those). Legacy/KVP backend behaviour must not
change (no marker there). Do not touch `filestore.js` path rules or the scanner exception.
