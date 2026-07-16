# PROMPTS — copy, paste, go
Every kickoff below is complete; do not add context (the role files carry it). Constraints live in the repo, so these stay one line on purpose. In Claude Code the `polaris` skill auto-routes even without these; other CLIs need the paste.

## Getting the kit into a repo — say this, in Claude Code, in the project
```
install POLARIS
```
That's it. On a machine that has never seen POLARIS, name the source once and it takes it from there:
```
install POLARIS from github.com/oscarsolis3301/POLARIS
```
The install also **arms the machine** — it caches the kit into `~/.claude/` and pre-authorizes its own commands — so every install after the first is offline and prompt-free. Then it interviews you and plans your first sprint **in the same chat**. There is no "now open a new session".

By hand, if you'd rather:
```bash
python polaris-v5.zip                    # install into the git repo you're standing in
python polaris-v5.zip --verbose          # ...with the full log instead of the one-line result
python polaris-v5.zip --no-machine-setup # ...and leave ~/.claude alone
```
One file, no `.git` attached, safe over an existing `CLAUDE.md` and hooks.

## Once per repo — only if you're doing it manually
```
You are INIT.
```
INIT asks how you want agents to talk to you (plain English or dense and technical), what you want to build first, and confirms the test/build commands it found in your repo. Three interactions, then it plans your first sprint. Change the voice later: edit `voice:` in `ops/CONVENTIONS.md` (`standard` | `technical`); `bash ops/polaris doctor` prints the one in force.

## Kit lifecycle — just say "update POLARIS" in any chat, in any POLARIS repo
It fetches the latest kit, refreshes kit code only (your board, RULES, CONVENTIONS, MAP and SPRINT are never touched), **and re-caches the new kit into `~/.claude`** — so the next repo you install into on this machine gets it too. One update, whole machine current. And if the repo was never set up (the interview never ran), install and update both finish by running that setup **in the same chat** — you are never left holding homework.

```bash
ops/polaris version            # which POLARIS this repo runs · what's latest on the channel
ops/polaris update             # ^ the above. --repo-only skips the ~/.claude refresh
ops/polaris uninstall --yes    # remove POLARIS; keeps your CLAUDE.md content and your other hooks
```
⚠ `upgrade` is **not** `update`. `ops/polaris upgrade` migrates an old v3/v4 *board* to v5 and downloads nothing. If you want the newer POLARIS, you want `update`.

## Every sprint
> In Claude Code you rarely type any of these. Just say what you want in plain English —
> *"improve the UI/UX of the settings page"*, *"add CSV export to reports"* — and POLARIS runs the
> **whole loop in that one chat**: it asks you simple questions until it truly understands, shows you
> what it understood, plans, then builds and integrates with live progress — each phase a fresh
> subagent, so the chat never degrades. That is the **Conductor**. You approve once (the plan);
> everything after is hands-free except real decisions. Prefer watching Builders in terminal panes
> beside you instead? Set `builders: panes` in `ops/CONVENTIONS.md`. The kickoffs below are the
> manual forms, for other agent CLIs or when you want a specific role. (Ordinary questions —
> *"what does auth do?"* — and commands — *"start the dev server"* — stay normal; they don't get planned.)

**0 — The whole loop** (one session, subagent-capable CLI):
```
You are the CONDUCTOR: <your idea>
```

**1 — Plan** (one session):
```
You are the PLANNER. Groom this into the backlog and promote what's ready: <your idea>
```

**2 — Fan out.** The Planner does this for you at the end of planning, per the `autolaunch:` setting in `ops/CONVENTIONS.md`:
- `wt` — opens a Builder session per ready task in **side-by-side Windows Terminal panes**, each claiming its own task. No prompt.
- `ask` *(default)* — offers once after planning: "Open N builders beside you?"
- `off` — just prints the kickoff; you start the sessions.

To do it by hand: `bash ops/polaris fleet N --launch` (drop `--launch` to only print; add `--dry-run` to preview the command; needs tmux or Windows Terminal + `claude` on PATH). Or, in one Claude Code session, one word does it:
```
start
```
`start` means "take the next piece of work": in a subagent-capable CLI it becomes the CONDUCTOR (drains the queue, integrates, reports); otherwise a BUILDER when tasks are queued, and a PLANNER when the board is empty. In any other agent CLI, paste the long form:
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
