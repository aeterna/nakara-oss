# oss-undeclared

Implement `undeclaredNetEvents` in `fixture/undeclared.mjs`. It is an ES module that runs on Node 22 and may use
`node:` built-ins only (none are needed).

## Required API

`export function undeclaredNetEvents(used, manifest)` returns an array of strings.

- `used`: an array of `{ name, side }` objects. `name` is a string. `side` is `'server'` or `'client'`.
- `manifest`: a parsed `oss.json` object. Net events are declared in `manifest.capabilities.netEvents.server` and
  `manifest.capabilities.netEvents.client`. Each is an array of strings.

## Rules

1. Return the names used on a side that are not declared in that same side's array. A name declared only on the
   other side is still undeclared.
2. The result is sorted ascending with the default `Array.prototype.sort()` (no comparator) and contains no
   duplicates. A name that is undeclared on both sides appears once.
3. If the result is empty, return an empty array.
4. If `manifest.capabilities.netEvents.server` or `manifest.capabilities.netEvents.client` is missing or is not an
   array of strings, throw a `TypeError`. The same applies when `manifest.capabilities` or
   `manifest.capabilities.netEvents` is missing. Validate the manifest on every call, even when `used` is empty.
5. Do not mutate `used` or `manifest`. Do no I/O.

## Example

With a manifest that declares `server: ['nakara:ping']` and `client: ['nakara:sync']`, and `used` =
`[{ name: 'nakara:ping', side: 'server' }, { name: 'nakara:sync', side: 'server' }, { name: 'nakara:sync', side: 'client' }, { name: 'nakara:ping', side: 'server' }]`,
the result is `['nakara:sync']`.

Only edit files under `fixture/`. Do not touch `check/`.
