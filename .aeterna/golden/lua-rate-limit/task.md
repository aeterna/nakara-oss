# lua-rate-limit

Implement a per-source sliding-window rate limiter for server net event handlers, in `fixture/ratelimit.lua`.

`fixture/ratelimit.lua` is a natives-free Lua module shaped like `packages/cargen-fix/client/logic.lua`:
`local L = {} ... return L`. It must run under stock Lua 5.4 with no game natives. It must not create or write
globals.

## Required API

`L.allow(state, source, now, max, windowMs) -> boolean`

- `state`: a table owned by the caller (starts empty). All bookkeeping lives in this table. Two different state
  tables are independent of each other.
- `source`: a string identifying the caller (for example a player source id).
- `now`: the caller's clock in milliseconds (a number). You may assume the clock never goes backwards between calls.
- `max`: a positive integer.
- `windowMs`: a positive number.

## Rules

1. Return `true` when the call is allowed and `false` when it is rejected.
2. A call is allowed when fewer than `max` earlier **allowed** calls from the same `source` satisfy
   `now - t < windowMs`, where `t` is the time of that earlier allowed call.
3. An earlier allowed call at time `t` counts while `now - t < windowMs`. At `now - t == windowMs` it no longer counts.
4. A rejected call is not recorded and does not count against later calls.
5. Separate sources are independent: a call from one source never affects the decision for another.
6. If `max` is not a positive integer, or `windowMs` is not a positive number, raise an error (use `error()`).
   Check this on every call, before any state changes.

## Example

With `max = 2` and `windowMs = 1000`, for one source:

- calls at `0`, `10`, `20` return `true`, `true`, `false`;
- a call at `999` returns `false` (the calls at 0 and 10 still count);
- a call at `1000` returns `true` (the call at 0 has expired, the call at 10 still counts);
- a call at `1009` returns `false`;
- a call at `1010` returns `true` (the call at 10 has expired).

Only edit files under `fixture/`. Do not touch `check/`.
