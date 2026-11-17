# SPRINT 25 — The hour: push once, one heavy job, fewer cards, a price on every plan (6.17.0)          capacity: 30   dates: 2026-11-16–

Owner ask of 2026-11-16 (plans/hour.md, approved in plan mode): Sonoba quoted 60–70 hours for one
stakeholder round; the bar is the same day, an hour at most. Measured cause: time = cards on the
critical path × cost per card, and POLARIS pushes both up. Plan `hour`, contract `ops/contracts/hour.md` v1.

6 tasks / 26 pts. Wave 1, side by side: T-300 (the heavy slot + the three new keys), T-301 (handoff
stops pushing under push: end, last lane out counts only this run, seal on demand, pack steps, one-pass
seal scan), T-302 (speed by lanes + speed --plan), T-303 (chain cards with steps: + next in one pass).
Wave 2: T-304 (seal/done/finish/status under push: end, one atomic push; after T-300 and T-301) and
T-305 (the words + version 6.17.0 + changelog; after T-300..T-303). Every task lands itself at handoff;
each verify list is its whole gate, and CI's Linux serial self-test runs once per task before handoff.

## Burndown
| date | done pts | remaining |
|---|---|---|
| 2026-11-16 | 18 | 8 |
| 2026-11-16 | 8 | 0 |
