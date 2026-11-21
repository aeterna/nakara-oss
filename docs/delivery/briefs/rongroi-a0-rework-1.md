# Rongroi Kit A0 · rework 1 · Q3 findings on 2ede3cb6

Base: branch `feat/rongroi-a0` at `2ede3cb6` (run `20261121-214545-9f0006`). Local CI on that commit passed
(rongroi specs 224/0, devkit 125/0, busted 175/0, check and safety 0 errors). Q3 (another model) found the defects below.
Use file tools only; do not run shell commands. Scratch only in `$TMPDIR`. HARD LIMIT: under 150 changed lines. Only
files under `packages/rongroi/`.

Keep the existing write order in `storage.js` (index entry before the case file on open; files emptied before the index
entry is removed on delete). It is deliberate: no native lists a folder, so an orphan file could never be found by
retention (ADR 0001 §4 "No orphans").

## Fixes

1. **The warning must not be erased by a later write.** After a wiped index, `recordTotal()` writes the smaller
   in-memory total on the next open, delete, report save or retention removal, so the loss disappears after one
   write and one restart. Fix in `storage.js`: keep `lost` (starts at 0). `checkIntegrity()` sets
   `lost = max(expected - found, 0)` when a marker exists. `recordTotal()` writes `total + lost`. `forgetMissing()` sets
   `lost = 0` before its final `recordTotal()`.
2. **No false warning after a failed case write in `openCase`.** When `backend.write(caseKey(…))` throws after the index
   entry was written, roll back: remove the entry from the page, write the page again, call `recordTotal()`, and
   rethrow (mirror the existing index-write rollback). A crash between the two writes is still possible; leave it.
3. **`forgetMissingReports` returns early** (reply with the cases payload, no storage scan) when `storageWarning` is
   `null`.
4. **Banner style.** Add one neutral rule to `web/ui/case.css` for `.storage-warning`: margin, padding, a 1px border
   using an existing line/border variable from that file or `base.css`, no red/green or any colour that reads as a PC
   result. The button keeps its existing classes.

## Tests first (each must fail on 2ede3cb6)

In `spec/storage.test.js` (file backend, fake native, `memoryMarker` already exists):
- wipe `index-0` with marker 3, restart, `load()`, `checkIntegrity()`, then open one case: marker is 4 (3 lost + 1),
  and a second restart's `checkIntegrity()` still reports `expected` 4, `found` 1.
- `forgetMissing()` after that resets: marker equals the real total.
- `openCase` whose case write throws (make the fake `SaveResourceFile` fail for `case-` names only): the call throws,
  the index has no entry for it, the marker equals the count before, and a restart's `checkIntegrity()` reports
  `missingCaseFiles` 0.
- the marker follows `deletePlayerData` (two cases of one identifier removed ⇒ marker drops by 2).

In `spec/panel.test.js`:
- `forgetMissingReports` with `storageWarning: null` replies with the cases payload and never calls
  `storage.forgetMissing` (wrap it with a counter).

Every test file still reaches its final summary line; `npm test -w packages/rongroi` passes.
