# CONTRACT: rea — REA as standard equipment, its updates, its routing, and the Laya/Jev study      (v1 — 2026-10-11)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `C:\Users\Owner\.claude\plans\i-want-to-ensure-vectorized-token.md` § Sprint A (owner-approved
2026-10-11) · tasks T-187 (A3 arming), T-188 (A4 updates), T-189 (A5 routing), T-190 (A6 study) ·
`plan: effort-ceiling-rea`. Owner decision **R1**: REA (github.com/morluto/rea, npm package
`rea-agents`) is standard equipment — every POLARIS install sets it up and keeps it updated; its first
job is to study Laya and Jev. Installing `rea-agents` on machines POLARIS arms is the owner's explicit
request of 2026-10-11 (the "adding a dependency" stop is answered — a machine-level tool, like the
Laya venv of T-181, not a repo dependency).

## Purpose
Put REA on every armed machine and keep it current WITHOUT ever blocking an install, a session or a
hook, and without touching the owner's existing REA registration on this machine during the build.

## Shared values
```
REA_FLOOR   = "6.4.0"          # the version proven on this machine; first install pins exactly this
NODE_FLOOR  = 22.19            # `node --version` ≥ v22.19.0, else "no usable Node"
install     : npm install -g rea-agents@<REA_FLOOR>
register    : rea setup --client claude_code --yes --json      # machine-wide: every project
update      : rea update   then   rea setup --client claude_code --yes --json   # update does not re-register
POLARIS_REA=off                # env opt-out: every REA step below is skipped SILENTLY (tests, CI, the owner)
POLARIS_REA_PATH=<dir>         # test seam: node/npm/rea are resolved from this dir ONLY (stubs); unset = PATH
POLARIS_REA_NOW=<epoch secs>   # test seam: "now" for the soak and the daily throttle
```

## 1. Arming — `kit/ops/bootstrap.py` (T-187)
- New top-level `def arm_rea():` and module constant `REA_FLOOR`, called from `arm_machine` inside the
  same `if permissions:` gate that arms model-guard (registration writes user-level Claude config, so
  `--no-permissions` skips it exactly like the settings.json writers; `--no-machine-setup` never reaches
  `arm_machine` at all). `POLARIS_REA=off` ⇒ return at once, print nothing.
- **Already armed** ⇒ run nothing: `rea` resolves AND `~/.claude/skills/reverse-engineer-anything/`
  exists. (This machine is already armed, so a real install here is a no-op and never re-registers.)
- **Node check:** `node --version` must be ≥ 22.19; absent/older ⇒ ONE line, carry on.
- **Install if missing:** `rea` does not resolve ⇒ `npm install -g rea-agents@6.4.0` with a timeout
  (≤ 180 s); failure or timeout ⇒ ONE line, carry on.
- **Register:** then `rea setup --client claude_code --yes --json`; failure ⇒ ONE line, carry on.
- **Output:** every line goes through `out()` (verbose-only) — NEVER `always=True`: ci.yml's quiet-install
  tripwire allows ≤ 2 lines before the epilogue and `.github/` is human-only. Windows: npm is `npm.cmd`;
  resolve with `shutil.which` (honouring `POLARIS_REA_PATH`) and run the resolved path.
- `arm_rea` never raises, never exits, never changes `arm_machine`'s return value (it must not make the
  one-off "machine armed" line nag).
- **Fixtures that run the installer set `POLARIS_REA=off`:** `ops/tests/machine-armed.cmd` (every
  `python polaris-v5.zip …` line) and `kit/ops/selftest-install.sh` (exported once near the top). Their
  `.expected` output does not change. CI (`.github/workflows/ci.yml`) is HUMAN-only: the conductor offers
  the owner that one-line change; until then CI arming fails open (GitHub runners' Node is below 22.19).
- **api-kit delta, byte-exact** (T-187 owns `ops/tests/api-kit.expected`; these two rows and NO other hunk —
  STOP on any unexpected hunk, refresh by content diff, never `check --update` on faith):
  ```
  kit/ops/bootstrap.py	const	REA_FLOOR
  kit/ops/bootstrap.py	fn	arm_rea
  ```
  (each inserted at its sorted position among the existing `kit/ops/bootstrap.py` rows.)
- **Uninstall:** `polaris uninstall` leaves REA in place; `rea uninstall` is the human's to run. No code.

### Executable check — `ops/tests/rea-arm.{cmd,expected}` (T-187)
Hermetic: `mktemp -d` HOME and USERPROFILE (ntpath reads USERPROFILE), `POLARIS_REA_PATH` pointing at
stub `node`/`npm`/`rea` that only log their argv into the fixture (write `.cmd` twins so Windows Git Bash
resolves them too). Never the real npm, node, rea or HOME. Cases, one result line each:
armed (missing → install + register, argv shown) · already armed (nothing run) · no Node · Node too old ·
failed npm install · failed setup · `POLARIS_REA=off` (nothing run, nothing printed). Every case: the
install continues (rc 0). Worktree-true: `bash ops/tests/rea-arm.cmd 2>/dev/null | diff - ops/tests/rea-arm.expected`.

## 2. Updates — the SessionStart update path (T-188)
`polaris update` lives in `kit/ops/lib/admin.sh` (`cmd_update` / `cmd_update_auto`), but
`kit/ops/hooks/update-hook.sh` returns WITHOUT starting the CLI on almost every session (the T-176
no-CLI fast path) and exits early in the kit's own repo — so the daily REA trigger lives in the HOOK,
and the work in a new flat script. `admin.sh` is not touched.
- **`kit/ops/hooks/rea-update.sh`** (new; installed to `ops/hooks/` by install.sh's `hooks/` copy) — a
  flat script, **no functions** (api-kit stays frozen), rc 0 always, fail-open everywhere:
  1. `POLARIS_REA=off` ⇒ exit. `rea` not resolvable ⇒ exit (arming is the installer's job, not this one's).
  2. Write the machine stamp `$HOME/.claude/polaris/rea-update` = `checked: <YYYY-MM-DD>` FIRST (so a
     second session the same day does nothing even mid-run).
  3. `npm view rea-agents dist-tags.latest time --json` (parse with `node -e`, Node is present if rea is);
     failure ⇒ exit.
  4. Installed = `rea --version`. If latest ≤ installed ⇒ `last: current <ver>` and exit.
  5. **7-day soak:** if `time[latest]` is less than 7×86400 s before now (`POLARIS_REA_NOW` or the clock)
     ⇒ `last: waiting <latest> (published <date>)` and exit. `rea update` always takes `latest`, so a fresh
     latest means WAIT — never install an older "soaked" one instead.
  6. Soaked ⇒ `rea update`, then `rea setup --client claude_code --yes --json`; record
     `last: updated <old> → <new>` or `last: failed <step>` in the stamp file.
  Why the soak: a same-day bad release never reaches every machine, and updates still need nobody.
- **`kit/ops/hooks/update-hook.sh`** — inline in `uh_main` (no new function), placed right after the
  primary is resolved and BEFORE the self-hosting exit (REA is machine equipment; the kit repo's machine
  updates too): a builtin read of `$HOME/.claude/polaris/rea-update`; `checked:` not today, AND
  `POLARIS_REA` ≠ `off`, AND `"$p/ops/hooks/rea-update.sh"` exists ⇒
  `( cd "$p" && bash ops/polaris bg run rea-update -- bash ops/hooks/rea-update.sh ) >/dev/null 2>&1 || true`.
  Nothing reaches the hook's stdout (that line belongs to the POLARIS update notice). `--test` prints
  exactly `update-hook: would start rea-update` instead of launching, then continues as before. The
  due-check is builtins only; the non-due path starts no process.
- **Footprint** (bytes REA's tool names add per context) is measured by T-190, not here. The owner's
  registration is NOT changed by this sprint beyond what `rea setup` does on a soaked update; any
  footprint change (MCP on demand) is a proposal to the owner first.

### Executable check — `ops/tests/rea-update.{cmd,expected}` (T-188)
Hermetic (`mktemp -d` HOME, stubs via `POLARIS_REA_PATH`, a fixed `POLARIS_REA_NOW`). Cases, one line each:
a newer release too fresh (skipped, nothing run) · a soaked one (update then setup, argv shown) · already
current (nothing) · stamp already today (no npm call at all) · `POLARIS_REA=off` · `rea` absent · npm view
fails (fail open) · `update-hook.sh --test` in a fixture repo: stamp stale ⇒ the `would start rea-update`
line; stamp today ⇒ no such line; a self-hosting fixture (has `kit/ops/pack.py`) still gets the line.
SURFACES row (T-188's `surface:`): `kit/ops/hooks/rea-update.sh` → `ops/tests/rea-update.*`.

## 3. Routing — `kit/CLAUDE.md` (T-189)
One clause in § ROLE DISPATCH (beside the Guard bullet), ≤ 160 B added, no new heading (api-kit
frozen), meaning: "Use REA to…" ⇒ REA's skill (`reverse-engineer-anything`) gathers the evidence first;
then a question is answered, and a build request goes to `triage` with that evidence attached.

## 4. The study — `docs/spikes/laya-jev-rea.md` (T-190, no kit code)
REA is for shipped artifacts and runtime evidence, not source reading. Targets: (a) the shipped `laya`
package and its checkpoints — which checkpoint answers which question, how confidence is calibrated;
(b) the `laya-serve` runtime — the real `POST /v1/systemone` exchange (becomes S19's client contract);
(c) Jev's hosted API — ONLY with the owner's own account, the key named by an env var (name only,
Invariant 10), within Jev's terms; no key ⇒ skipped and said so. Measure `laya-typed-decisions` vs the
T-181 base checkpoint on the 30 spawn-difficulty labels plus 30 NEW effort labels from real spawns judged
by outcome, each beside its majority baseline, with GPU p50/p95. Plus the REA footprint: bytes REA's
tool names add to a main chat and to a subagent, against the `polaris slim` budget.
Headings, pinned (Sprint 19 reads them):
```
## Verdict              checkpoint · host · Jev vs Laya on cost and latency · go/no-go for shadow-mode effort
## Checkpoints          (a)
## laya-serve exchange  (b)
## Jev                  (c) — or "skipped: no key"
## Accuracy             both label sets, each beside its baseline
## Latency              p50/p95 per host
## REA footprint        bytes per main chat and per subagent vs the slim budget, and the proposal if over
## Method
```
Downloads (the `laya-typed-decisions` checkpoint) need the owner's yes FIRST: the builder hands back
with the URL and size; the conductor relays it.

## Changelog
- v1 2026-10-11: created for T-187, T-188, T-189, T-190.
