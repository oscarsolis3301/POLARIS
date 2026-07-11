# CONTRACT: <seam name>            (v1 — <date>)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
One sentence: what this seam separates.

## Interface
Exact signatures — no prose where code is clearer.
```
POST /auth/reset            # or: def reset_password(username: str) -> ResetResult
  request:  { "username": string }
  response: 202 { "status": "queued" }        # always 202, even unknown user (no enumeration)
  errors:   429 rate-limited { "retry_after": int }
```

## Shared types / schema
```
ResetToken: { token: string(32), expires_at: iso8601, used: bool }   # single-use, 15-min TTL
```
DB changes, if any: table, columns, migration id.

## Executable check (when the seam is code-level)
Test file: `<path>` — owned by task `<earlier-ID>`, listed in `<later-ID>`'s `verify:`.
Run: `<command>`. The check IS the contract; prose above is commentary.

## Invariants
Things every implementer of/against this seam must preserve.

## Example
One realistic request→response (or call→return) pair.

## Changelog
- v1 <date>: created for <task IDs>
