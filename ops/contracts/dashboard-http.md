# CONTRACT: dashboard observable surface            (v1 — 2026-07-14)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Separates `kit/ops/dashboard.py` (human-maintained code, see ops/CONVENTIONS.md write routing) from the
smoke test that drills it. The test asserts THIS surface and nothing deeper.

## Interface
```
python kit/ops/dashboard.py --port <N> [--host <H>]     # defaults: 7373, 127.0.0.1
  startup:  prints one line starting "✦ POLARIS live board → http://"
  GET /       → 200 text/html      # page with embedded bootstrap state
  GET /state  → 200 application/json
      body: object; body["columns"] has EXACTLY the keys
            backlog ready active review blocked done — each an array
  GET /events → 200 text/event-stream (SSE)   # not smoke-tested; long-lived
```

## Invariants
- The smoke test never binds 7373 — a live `polaris dash` must be untouched.
- The test treats dashboard.py as read-only. A surface change is a human act → `## v2` here first.
- Server must be killed on every exit path of the test (trap), no orphan process.

## Example
```bash
python kit/ops/dashboard.py --port 7999 &  # then: GET http://127.0.0.1:7999/state
# → {"columns": {"backlog": [...], "ready": [...], ...}, ...}
```

## Changelog
- v1 2026-07-14: created for T-003. Descriptive of dashboard.py as shipped (do_GET, kit/ops/dashboard.py:309).
