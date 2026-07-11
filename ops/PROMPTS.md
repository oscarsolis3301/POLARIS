# PROMPTS — copy, paste, go
Every kickoff below is complete; do not add context (the role files carry it). Constraints live in the repo, so these stay one line on purpose. In Claude Code the `polaris` skill auto-routes even without these; other CLIs need the paste.

## Once per repo
```
You are INIT.
```

## Every sprint
**1 — Plan** (one session):
```
You are the PLANNER. Groom this into the backlog and promote what's ready: <your idea>
```

**2 — Fan out** (N parallel sessions, identical message — or `bash ops/polaris fleet N`):
```
You are a BUILDER. Claim the top ready task and complete it end to end. Stop at the review handoff.
```
Keep a session claiming until ready/ is empty — append:
```
 Run in loop mode.
```

**3 — Integrate** (one session):
```
You are the INTEGRATOR. Land everything in ops/board/review/.
```

## Between sprints (optional, data-driven tuning)
```
You are EVOLVE.
```

## Replies the human gives mid-run
- High-risk merge approval (Integrator asks): `approve <ID>`
- EVOLVE amendment approval: `approve <n>`
- Resume a kicked-back task (fresh session): 
```
You are a BUILDER. Resume <ID>: it was kicked back — read its Notes for the failure, fix, and hand off again.
```

## Watching
```
bash ops/polaris dash        # live board · http://127.0.0.1:7373
bash ops/polaris status      # terminal view
bash ops/polaris metrics     # cycle · throughput · kickbacks · per-point calibration
bash ops/polaris drift       # board hygiene audit (add --strict in CI)
bash ops/polaris rules       # repo policy lines + health
```
