# @aeterna_game/rongroi-envelope

The report envelope that Rongroi Connect seals and a server opens: envelope v1 (aeterna-rongroi ADR 0089 §5) and v2
(ADR 0097 §4). X25519, HKDF-SHA256 and AES-256-GCM with Node's `crypto`; no dependencies.

Use it when your server is not FiveM, or you write your own receiver or a Rongroi Relay integration. The FiveM Server
Kit (`packages/rongroi`) ships the same file.

```js
const { generateKeyPair, openEnvelope } = require('@aeterna_game/rongroi-envelope');

const kit = generateKeyPair();               // keep privateKey on the server only
// v1 (an rr1 code): the ticket is the additional data
openEnvelope(body, kit.privateKey, kit.publicKey, ticket);
// v2 (an rr2 code): the five members you put in the code are the additional data
openEnvelope(body, kit.privateKey, kit.publicKey, ticket, {
  accept: 2,
  binding: { base_path, policy_hash, server_origin, ticket, transport },
});
```

A ticket accepts one version: the one its code was issued for. A bad key or binding throws `TypeError`; a bad envelope
throws `EnvelopeError` with `code` `malformed` or `not_authentic`.

What the record inside means, and what a server may and may not do with it (evidence only, no verdict), is in
aeterna-rongroi ADR 0002 and ADR 0089.

## Test vectors

`test-vectors/envelope-v1.json` and `envelope-v2.json` hold fixed test keys and the expected bytes. An implementation in
another language should reproduce both. They are test keys, never a server key.

## Licence

MIT. Not published to npm yet; install from this repository.
