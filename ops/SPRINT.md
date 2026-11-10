# SPRINT 24 — Away means away, small means fast (6.16.0)          capacity: 20   dates: 2026-11-10–

Owner ask of 2026-11-09 (plans/away.md Phase B, approved in plan mode): approved plan + auto mode means
the owner has left, so nothing in a run waits on them; a small UI change gets quick checks and a look;
big changes stay fully proven but never take hours. Plan `away`, contract `ops/contracts/away.md` v1,
plus `ops/contracts/test-depth.md` § v2 and `ops/contracts/role-handover.md` § v4.

8 tasks / 20 pts. Wave 1, side by side: T-289 (presence hook + `polaris presence`), T-290 (stop hook
bounces an away question), T-291 (depth `ui` + keys), T-293 (the words); T-292 (brain refreshed once
per landing) joins as soon as T-225 is done (it shares integrate.sh). Wave 2: T-294 (the plan's yes
while away, after T-289) and T-295 (checks side by side, after T-291 and T-225). T-296 releases
6.16.0 LAST (after T-227 frees VERSION and CHANGELOG). Every task lands itself at handoff; each verify
list is its whole gate, and CI's Linux self-test runs once per task before handoff (T-289, T-294,
T-295 also on macOS).

## Burndown
| date | done pts | remaining |
|---|---|---|
