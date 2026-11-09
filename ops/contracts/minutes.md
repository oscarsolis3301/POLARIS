# CONTRACT: minutes — proof runs where it is fast, and a release check proves bytes   (v1 — 2026-11-09)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
Measured 2026-11-09 (plans/minutes.md): the full self-test takes 166 s on CI's Linux runner and 13–37
minutes on this Windows machine; the release check then repeats it for another 37 minutes. This
contract moves the self-test's verdict to CI, keeps the goldens local and parallel, and replaces the
release check's self-test with a byte comparison. Phase 1 = § 1 and § 2. Later phases append.

## 1. The release check proves bytes — `kit/ops/pack.py`
### 1.1 `build_entries()`
The loop that builds `entries` in the packer (the `git ls-files -s` walk, the `archive/` skip, the LF
normalisation of text, the `commit:`/`built:` stamp appended to `ops/VERSION`, and the root
`__main__.py` taken from `kit/ops/bootstrap.py`) moves into ONE function:
```
build_entries() -> (entries, execs)      # entries: [(path, blob, is_exec)], execs: [path]
```
The packer calls it and writes the zip exactly as today: for the same commit the output zip is
byte-identical to today's (the golden pins that with a sha256 before/after the refactor, taken in the
builder's own session — not in the golden).

### 1.2 `dogfood()` — order of work
dirty check → read `want` + url → download → `zip_version` check → version equality check (all four
unchanged, same texts) → **byte check** → install (unchanged) → **quick check** → closing lines.
- The url: `POLARIS_DOGFOOD_ZIP` when that environment variable is set and non-empty (a test seam:
  any url `urllib` opens, e.g. `file:///…`), otherwise the `zip:` field as today.
- **Byte check.** `got` = every member of the downloaded zip as `{name: bytes}`. `exp` = from
  `build_entries()`: `__main__.py` keeps its name, every other path becomes `polaris-v5/<path>`.
  Compare the two name sets, then the bytes of each name in sorted order. One exemption:
  `polaris-v5/ops/VERSION` is compared after removing, on both sides, every line that starts with
  `commit: ` or `built: `. First difference → `sys.exit` with exactly:
  ```
  ⛔ the published kit is not this commit's kit — <name> differs. Repo untouched.
     Dogfood from the commit the tag points at, or publish again.
  ```
  (`<name>` = the first differing or one-sided member, sorted order.) Before it, print:
  `   proving the bytes:  the published kit against this commit`
- **Quick check.** Print `   proving the board still works:  ops/polaris doctor --fast` and run
  `[bash, "ops/polaris", "doctor", "--fast"]` in the repo. Non-zero → `sys.exit` with exactly:
  ```
  ⛔ <got> installs, but FAILS its quick check here. Do not ship it — this is
     exactly the bug --dogfood exists to catch. Undo with: git checkout -- .
  ```
- **Closing line** (replaces today's ✅ line; the "review, then commit" listing after it is unchanged):
  `✅ POLARIS <got> installed from the published release — same bytes CI proved, and the quick check passes.`
- **`--dogfood --full`**: skips nothing above, and runs today's `doctor --selftest` INSTEAD of the
  quick check, with today's two texts (the "proving the board still works:  ops/polaris doctor
  --selftest" line and today's ✅ and ⛔ lines), byte for byte.

### 1.3 Executable check — golden `dogfood-bytes`
Hermetic: a `git clone` of this repo at HEAD into a temp dir, `core.autocrlf=false`, fake HOME **and**
USERPROFILE. In the clone: `python kit/ops/pack.py` builds the zip; then, each on a fresh copy of the
clone, with `POLARIS_DOGFOOD_ZIP` pointing at a `file://` url:
1. the zip as built → rc 0, the closing line, the clone's `ops/VERSION` equals `kit/ops/VERSION`'s version;
2. the same zip with ONE byte changed in one member other than `ops/VERSION` → rc ≠ 0, the ⛔ byte
   line naming that member, and `git status --porcelain` in the clone is empty (nothing installed);
3. the zip as built, dogfooded after one extra commit that touches only a file outside `kit/` → rc 0
   (the stamp exemption).
The golden prints verdict lines only (no timings, no temp paths).

## 2. CI is the self-test's judge — `tools/proof.sh` (this repo's own tool; never shipped in the kit)
`bash tools/proof.sh` proves ONE commit, HEAD, with two halves that overlap in time.
### 2.1 The run
1. `sha` = `git rev-parse HEAD`, `s7` = its first 7 characters, `br` = `proof/<first 12 of sha>`.
2. **CI half — find or start.** `$GH run list --workflow ci.yml --commit "$sha" --json databaseId --jq '.[0].databaseId'`
   - an id → reuse it; say `proof: <s7> — CI run <id> (found)`.
   - none → delete every OTHER remote `proof/*` branch (`git ls-remote --heads origin 'proof/*'`,
     `git push -q origin --delete <name>`, failures ignored); `git push -q origin "$sha:refs/heads/$br"`;
     `$GH workflow run ci.yml --ref "$br"`; poll the listing every `PROOF_FIND_POLL` s (default 5),
     at most 90 s, until an id appears; say `proof: <s7> — CI run <id> (started)`.
3. **Goldens half, meanwhile.** Run `$PROOF_GOLDENS` when set; otherwise every golden, 12 at a time:
   each name from `ops/tests/*.cmd` through `bash kit/ops/polaris check --only <name>`, its output and
   exit code kept per name in a temp dir. Say `proof: goldens — <n> green`, or
   `proof: goldens — <k> red: <names, space-separated>` followed by each red golden's output.
4. **Wait for Linux.** Poll `$GH run view <id> --json jobs` every `PROOF_POLL` s (default 15) for the
   job named `ubuntu-latest`, at most 20 minutes. Say `proof: linux — green`, or `proof: linux — RED`
   followed by the last 40 lines of `$GH run view <id> --log-failed`, or
   `proof: linux — no answer after 20 minutes` (counts red).
5. Write `.polaris/ci-proof` = `<sha> <id>` (one line). Close with `✅ proof: <s7> green` and rc 0 when
   both halves are green, else `⛔ proof: <s7> red` and rc 1. Other CI jobs (`macos-latest`,
   `windows-latest`, `one version, everywhere`) are never read here: the version job is expected red
   whenever `kit/ops/VERSION` is ahead of the newest tag.
### 2.2 No CI
`$GH` missing, `$GH auth status` failing, no `origin` remote, a failed push or dispatch, or no run id
within 90 s → say `proof: no CI here (<reason>) — running the self-test on this machine` and run
`bash kit/ops/polaris doctor --selftest --parallel 3` as the first half; the goldens half and the
closing lines are unchanged; `.polaris/ci-proof` is not written.
### 2.3 Flags
- `--await <job>`: needs `.polaris/ci-proof` naming HEAD's sha, else
  `⛔ proof: no recorded run for <s7> — run tools/proof.sh first` and rc 1. Polls that job as in step 4
  and says `proof: <job> — green` (rc 0), `proof: <job> — RED` (rc 1) or the 20-minute line (rc 1).
- `--report`: one line per job of the recorded run, `<name>: <status> <conclusion>`; rc 0.
### 2.4 Seams and limits
`GH="${PROOF_GH:-gh}"`. bash 3.2-safe (no `case` inside `$(...)`, no `${v,,}`, no `wait -n`, no
arrays). No `sleep` longer than the poll interval. Never touches the primary's branch or index; the
only refs it writes are remote `proof/*` branches.
### 2.5 Executable check — golden `proof-ci`
A scratch repo with a bare `origin`, a stub `gh` first on PATH (reads its answers from files), and
`PROOF_GOLDENS` set to a stub, so the golden never recurses into the real goldens:
found-run green · started-run green (asserts the `proof/…` branch was pushed and an older `proof/*`
branch deleted) · red Linux job (rc 1, the log tail printed) · red goldens (rc 1) · no `gh` (the
fallback line; `PROOF_SELFTEST` stubs the self-test command) · `--await macos-latest` green and red ·
`--await` with no state file · `--report`.

## Changelog
- v1 2026-11-09: created for the Phase 1 tasks of plans/minutes.md.
