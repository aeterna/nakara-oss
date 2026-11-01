# nakara_rongroi

The Rongroi Server Kit. This is the first part of lane 2b: envelope crypto, the shared test vectors and a
start-up self-test. **There is no HTTP surface, no ticket store and no UI yet.** See
[ADR 0001](../../docs/adr/0001-rongroi-server-kit.md) for the layout. The protocol is aeterna-rongroi ADR 0089,
section 5 (not public yet).

## Envelope v1

`server/js/envelope.js` (Node `crypto` only, CommonJS) implements the envelope of aeterna-rongroi ADR 0089,
section 5:

- `generateKeyPair()`: X25519 key pair as raw 32-byte base64url values.
- `sealEnvelope(plaintext, kitPublic, ticket)`: encrypts to the Kit's public key. Used by tests and the vector
  generator; the optional fourth argument fixes the ephemeral key and iv for the vectors only.
- `openEnvelope(envelopeJson, kitPrivate, kitPublic, ticket)`: returns the UTF-8 plaintext or throws an
  `EnvelopeError` with `code` `malformed` or `not_authentic`.
- `deriveKey` and `agree` are the primitives the vectors check.

Wire form: `{ "v": 1, "epk": …, "iv": …, "ct": … }`, base64url without padding. `epk` is 32 bytes, `iv` is 12
bytes, and `ct` is the AES-256-GCM ciphertext followed by the 16-byte tag. The key is HKDF-SHA256 with salt =
the ticket as 32 lowercase hex ASCII bytes and info = `rongroi-connect report v1` || Kit public key || `epk`.
The AES-GCM additional data is the ticket string.

## Test vectors

`test-vectors/envelope-v1.json` holds fixed inputs (a Kit key pair, an ephemeral key, an iv, a ticket and a
plaintext) and the expected values. **Connect tests against the same file.** The keys in it are test keys only
and are not used by any Server Kit.

## Self-test

When the resource starts, `server/js/selftest.js` checks the vectors once and prints exactly one line:

```
nakara_rongroi selftest: ok x25519 hkdf aes-gcm
nakara_rongroi selftest: fail <step> <message>
```

The steps are `x25519`, `hkdf`, `aes-gcm` and `vectors` (the vector file could not be read). The line never
contains key material.

## Capabilities

From [`oss.json`](oss.json): none. The resource makes no HTTP requests, runs no commands, reads and writes no
convars, declares no net events, has no NUI and no database, and writes no files.

## Tests

`npm test` inside `packages/rongroi/` runs the specs in `spec/` with `node --test`. The repository's `npm test`
picks them up once this package is listed in the root workspaces.
